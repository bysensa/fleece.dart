part of '../fleece.dart';

enum _ModelRead { value, type, keys, presence }

/// A field, a nullable child's type, or the keys/length of a collection.
final class FleeceDependency {
  FleeceDependency._(this._cursor, this._kind);
  final FleeceCursor _cursor;
  final _ModelRead _kind;
  KeyPath get path => _cursor._path;
}

/// Optional bridge to a reactive runtime. Each document owns its bridge.
abstract interface class FleeceTracking {
  void track(FleeceDependency field);
  Iterable<FleeceDependency> get fields;
  void publish(List<FleeceDependency> changed);
  void dispose();
}

abstract interface class _ModelAccess {
  ValueRef? _get(FleeceCursor cursor, {_ModelRead kind = _ModelRead.value});
}

// Custom codecs may retain a ValueRef. Its backing buffers must stay
// immutable even when that reference outlives the transaction or document.
ValueRef _modelRoot(Uint8List bytes,
        {SharedKeys? sharedKeys, Uint8List? base}) =>
    Doc(bytes.asUnmodifiableView(),
            sharedKeys: sharedKeys, base: base?.asUnmodifiableView())
        .root;

/// A stable location, resolved against the current committed or draft root.
final class FleeceCursor {
  FleeceCursor._(this._access, this._path, [this._parent, this._field]);
  final _ModelAccess _access;
  final KeyPath _path;
  final FleeceCursor? _parent;
  final FleeceField<Object?>? _field;
  Map<Object, FleeceCursor>? _fields;
  _ItemCursors? _items;
  Object? _model;
  bool _binding = false;
  _Transaction? _initializing;
  late final _defaultValue = _field?._encodeDefault();
  late final _valueRead = FleeceDependency._(this, _ModelRead.value);
  late final _typeRead = FleeceDependency._(this, _ModelRead.type);
  late final _keysRead = FleeceDependency._(this, _ModelRead.keys);
  late final _presenceRead = FleeceDependency._(this, _ModelRead.presence);

  FleeceCursor _at(Object step, [FleeceField<Object?>? field]) {
    FleeceCursor create() => FleeceCursor._(
        _access, KeyPath._([..._path._steps, step]), this, field);
    if (field != null) return (_fields ??= {}).putIfAbsent(step, create);
    return (_items ??= _ItemCursors()).get(step, create);
  }

  FleeceCursor child<T>(FleeceField<T> field) => _at(field.key, field);

  ValueRef? _memberOf(ValueRef? parent,
      {bool strict = false, List<(KeyPath, ValueRef)>? defaults}) {
    final step = _path._steps.last;
    if (step is BigInt) {
      final array = parent?.asArray;
      if (array != null) return array.get(step.toInt());
    } else {
      final dict = parent?.asDict;
      if (dict != null) {
        final member = dict[step as String];
        if (member != null) return member;
        final fallback = _defaultValue;
        if (defaults != null &&
            fallback != null &&
            (fallback.type == ValueType.dict ||
                fallback.type == ValueType.array)) {
          defaults.add((_path, fallback));
        }
        return fallback;
      }
    }
    if (strict) throw FormatException('Missing parent collection for "$step"');
    return null;
  }

  ValueRef? _resolve(ValueRef root) {
    final parent = _parent;
    if (parent == null) return root;
    return _memberOf(parent._resolve(root));
  }

  T get<T>(FleeceField<T> field) {
    final at = child(field);
    if (field.codec._hasBinding) return field.codec.bindValue(at);
    return field.read(at._get());
  }

  /// Initializes a superclass constructor without subscribing a caller to its
  /// arguments. Inherited methods subsequently read the live properties.
  T initial<T>(FleeceField<T> field) {
    return field.read(child(field)._get(track: false));
  }

  FleeceCursor? get _bindingOwner {
    if (_document._bindings == 0) return null;
    FleeceCursor? owner;
    for (FleeceCursor? at = this; at != null; at = at._parent) {
      if (at._binding) owner = at;
    }
    return owner;
  }

  ValueRef? _get({_ModelRead kind = _ModelRead.value, bool track = true}) {
    final owner = _bindingOwner;
    final access = owner?._initializing ?? _access;
    if (access is _ModelDocument && (owner != null || !track)) {
      access._checkOpen();
      return access._locate(this);
    }
    return access._get(this, kind: kind);
  }

  void set<T>(FleeceField<T> field, T value) =>
      child(field)._write(field.codec, value);

  /// Runs a hand-written domain setter with its validation and side effects.
  /// Only changed schema fields are staged. Missing defaults and unknown
  /// dictionary entries survive an edit to an unrelated property.
  void applySetter<T>(FleeceModelCodec<T, T> codec, void Function(T) setter) =>
      _edit((tx) {
        final source = tx._get(this);
        if (source == null) throw const FormatException('Missing Fleece model');
        final model = codec.read(source);
        DictRef project() =>
            FleeceCodecs.dictionary(_modelRoot(codec.encode(model)));
        final before = project();
        setter(model);
        final after = project();
        for (final entry in after.entries) {
          if (!_sameModelValue(before[entry.key], entry.value)) {
            tx._stage(_at(entry.key), _PatchNode.inside(entry.value));
          }
        }
      });

  void _write<T>(FleeceCodec<T> codec, T value) => _edit((tx) {
        tx._stage(this, _PatchNode.inside(_modelRoot(codec.encode(value))));
      });

  R _edit<R>(R Function(_Transaction) change) {
    final access = _access;
    // A domain constructor can use virtual setters and mutate collections.
    // Let it see its own initializers while opening an existing document.
    final owner = _bindingOwner;
    if (owner != null) {
      final tx = owner._initializing ??= _ModelDocument._(
              access is _ModelDocument
                  ? access._root
                  : access._get(FleeceCursor._(access, KeyPath._(const [])))!,
              null,
              false)
          ._begin();
      return tx._change(change);
    }
    final implicit = access is _ModelDocument;
    final tx = implicit ? access._begin() : access as _Transaction;
    try {
      final result = tx._change(change);
      if (implicit) tx.commit();
      return result;
    } finally {
      if (implicit) tx._close();
    }
  }

  static FleeceCursor _snapshot(ValueRef ref) =>
      FleeceCursor._(_ModelDocument._(ref, null, false), KeyPath._(const []));

  bool get hasValue {
    final ref = _get(kind: _ModelRead.type);
    if (ref == null && _field != null && _field.whenMissing == null) {
      throw FormatException('Missing required Fleece field "${_field.key}"');
    }
    return ref?.isNull == false;
  }

  M? optionalObject<M>(M Function(FleeceCursor) bind) {
    final ref = _get(kind: _ModelRead.type);
    if (ref == null || ref.isNull) return null;
    FleeceCodecs.dictionary(ref);
    return (_model ??= bind(this)) as M;
  }

  M object<M>(M Function(FleeceCursor) bind) =>
      optionalObject(bind) ??
      (throw FormatException(
          'Missing required Fleece dictionary at ${_path._steps.lastOrNull ?? 'root'}'));

  /// Used by older generated parts that provide only an element reader.
  List<T> listItems<T>(T Function(FleeceCursor) read) {
    if (_get(kind: _ModelRead.type)?.asArray == null) {
      throw const FormatException('Expected Fleece array');
    }
    return _ModelList(this, read);
  }

  /// Used by older generated parts that provide only an element reader.
  Map<String, T> mapItems<T>(T Function(FleeceCursor) read) {
    if (_get(kind: _ModelRead.type)?.asDict == null) {
      throw const FormatException('Expected Fleece dictionary');
    }
    return _ModelMap(this, read);
  }

  /// The element codec accepts domain objects; the optional reader binds each
  /// nested model to its location and can return a more specific subtype.
  FleeceList<T, V> list<T, V extends T>(FleeceCodec<T> item,
      [V Function(FleeceCursor)? bind]) {
    if (_get(kind: _ModelRead.type)?.asArray == null) {
      throw const FormatException('Expected Fleece array');
    }
    return _list(item, bind);
  }

  FleeceList<T, V> _list<T, V extends T>(
      FleeceCodec<T> item, V Function(FleeceCursor)? bind) {
    final model = _model;
    if (model is FleeceList<T, V>) return model;
    return _model = FleeceList<T, V>._(this, item, bind);
  }

  FleeceMap<T, V> map<T, V extends T>(FleeceCodec<T> item,
      [V Function(FleeceCursor)? bind]) {
    if (_get(kind: _ModelRead.type)?.asDict == null) {
      throw const FormatException('Expected Fleece dictionary');
    }
    return _map(item, bind);
  }

  FleeceMap<T, V> _map<T, V extends T>(
      FleeceCodec<T> item, V Function(FleeceCursor)? bind) {
    final model = _model;
    if (model is FleeceMap<T, V>) return model;
    return _model = FleeceMap<T, V>._(this, item, bind);
  }

  Iterable<String> get _dictionaryKeys {
    // Register reads of the property and of a retained iterable. Enumerating
    // a draft with staged children only builds its dictionary when needed.
    final access = _access;
    if (access is _Transaction) {
      access._checkActive();
    } else {
      _get(kind: _ModelRead.keys);
    }
    return _readKeys();
  }

  Iterable<String> _readKeys() sync* {
    final dict = _get(kind: _ModelRead.keys)?.asDict;
    if (dict == null) throw const FormatException('Expected Fleece dictionary');
    for (final entry in dict.entries) {
      yield entry.key;
    }
  }

  _ModelDocument get _document {
    final access = _access;
    return access is _ModelDocument ? access : (access as _Transaction)._owner;
  }

  FleeceCursor _in(_ModelAccess access) {
    final parent = _parent;
    return parent == null
        ? FleeceCursor._(access, _path)
        : parent._in(access)._at(_path._steps.last, _field);
  }

  /// Read an independent instance, including any changes staged at this path.
  T read<T>(FleeceCodec<T> codec) {
    final ref = _get();
    if (ref == null) throw const FormatException('Missing Fleece model');
    return codec.read(ref);
  }

  /// Copies the dictionary, including unknown keys. For a present field whose
  /// codec has changed, [writeField] may write its value and return true.
  void writeTo(Encoder encoder, {bool Function(String key)? writeField}) {
    final ref = _get();
    final dict = ref?.asDict;
    if (ref == null || dict == null)
      throw const FormatException('Missing Fleece model');
    final room = _ReadRoom(ref.doc)..takeValue();
    encoder._copyDict(dict, room, true, writeField: writeField);
  }

  Uint8List toBytes({SharedKeys? sharedKeys}) {
    final access = _access;
    if (sharedKeys == null &&
        _parent == null &&
        access is _ModelDocument &&
        _bindingOwner == null) {
      final root = access._get(this)!;
      if (root.position == root.doc.root.position) {
        return Uint8List.fromList(root.doc.bytes);
      }
    }
    final encoder = Encoder(
        sharedKeys: sharedKeys ?? _document._doc.sharedKeys,
        fixedSharedKeys: sharedKeys == null);
    writeTo(encoder);
    return encoder.finish();
  }

  Uint8List? get sharedKeyState {
    _document._checkOpen();
    if (_access case final _Transaction tx) tx._checkActive();
    return _document._doc.sharedKeys?.toState();
  }

  _Transaction _begin() {
    final access = _access;
    if (access is! _ModelDocument) {
      throw StateError('Begin a transaction on a committed model');
    }
    return access._begin();
  }

  M beginTransaction<M>(M Function(FleeceCursor) bind) {
    final tx = _begin();
    try {
      return bind(_in(tx));
    } catch (_) {
      tx._close();
      rethrow;
    }
  }

  FutureOr<R> transaction<M, R>(
      M Function(FleeceCursor) bind, FutureOr<R> Function(M) edit) {
    final tx = _begin().._managed = true;
    try {
      final result = edit(bind(_in(tx)));
      if (result is Future<R>) {
        return result.then((value) {
          tx.commit();
          return value;
        }, onError: (Object error, StackTrace stack) {
          tx._close();
          Error.throwWithStackTrace(error, stack);
        });
      }
      tx.commit();
      return result;
    } catch (_) {
      tx._close();
      rethrow;
    }
  }

  _Transaction get _transaction {
    final access = _access;
    if (access is _Transaction) return access;
    throw StateError('This model is outside an explicit transaction');
  }

  bool get isActive => _access is _Transaction && _transaction.isActive;
  void commit() => (_transaction.._checkManual()).commit();
  void rollback() => (_transaction.._checkManual()).rollback();
  void dispose() {
    final access = _access;
    if (access is _Transaction) {
      if (access.isActive) access._checkManual();
      access._close();
    } else {
      _document.dispose();
    }
  }
}

// A long-lived document can encounter arbitrarily many dictionary keys or
// array positions. Preserve identity while a model or subscription uses it.
final class _ItemCursors {
  final _items = <Object, WeakReference<FleeceCursor>>{};
  int _sweepAt = 64;
  FleeceCursor get(Object key, FleeceCursor Function() create) {
    final existing = _items[key]?.target;
    if (existing != null) return existing;
    if (_items.length >= _sweepAt) {
      _items.removeWhere((_, value) => value.target == null);
      _sweepAt = math.max(64, _items.length * 2);
    }
    final cursor = create();
    _items[key] = WeakReference(cursor);
    return cursor;
  }
}

// Structural changes replace a collection through its setter. Looking up an
// element binds its path in the same document and transaction as its parent.
final class _ModelList<T> extends ListBase<T> {
  _ModelList(this.cursor, this.read);
  final FleeceCursor cursor;
  final T Function(FleeceCursor) read;
  @override
  int get length =>
      cursor._get(kind: _ModelRead.keys)?.asArray?.length ??
      (throw const FormatException('Missing Fleece array'));
  @override
  T operator [](int index) {
    RangeError.checkValidIndex(index, this, 'index', length);
    return read(cursor._at(BigInt.from(index)));
  }

  @override
  set length(int _) =>
      throw UnsupportedError('Replace the list through its setter');
  @override
  void operator []=(int index, T value) =>
      throw UnsupportedError('Replace the list through its setter');
}

final class _ModelMap<T> extends MapBase<String, T> {
  _ModelMap(this.cursor, this.read);
  final FleeceCursor cursor;
  final T Function(FleeceCursor) read;
  @override
  Iterable<String> get keys => cursor._dictionaryKeys;

  @override
  T? operator [](Object? key) {
    if (key is! String) return null;
    final dict = cursor._get(kind: _ModelRead.type)?.asDict;
    if (dict == null) throw const FormatException('Missing Fleece dictionary');
    if (dict[key] == null) {
      cursor._get(kind: _ModelRead.keys);
      return null;
    }
    return read(cursor._at(key));
  }

  Never _readOnly() =>
      throw UnsupportedError('Replace the map through its setter');
  @override
  void operator []=(String key, T value) => _readOnly();
  @override
  void clear() => _readOnly();
  @override
  T? remove(Object? key) => _readOnly();
}

final class _ModelDocument implements _ModelAccess {
  _ModelDocument._(this._root, this._tracking, this._compacted);
  factory _ModelDocument.open(Uint8List bytes, Uint8List? base,
      SharedKeys? keys, FleeceTracking Function()? tracking) {
    final table = keys == null ? null : SharedKeys._snapshot(keys);
    var root = _modelRoot(Uint8List.fromList(bytes),
        sharedKeys: table,
        base: base == null ? null : Uint8List.fromList(base));
    FleeceCodecs.dictionary(root);
    if (base != null) {
      final encoder = Encoder(sharedKeys: table, fixedSharedKeys: true)
        .._copyWithRoom(root, _ReadRoom(root.doc), canonical: true);
      root = _modelRoot(encoder.finish(), sharedKeys: table);
    }
    return _ModelDocument._(root, tracking?.call(), base != null);
  }

  ValueRef _root;
  Doc get _doc => _root.doc;
  final FleeceTracking? _tracking;
  // Cache offsets only within the current committed buffer.
  var _locations = Expando<(ValueRef?,)>();
  bool _compacted;
  int _revision = 0;
  int _bindings = 0;
  bool _disposed = false;
  _Transaction? _active;

  void _checkOpen() {
    if (_disposed) throw StateError('Fleece document is disposed');
  }

  @override
  ValueRef? _get(FleeceCursor cursor, {_ModelRead kind = _ModelRead.value}) {
    _checkOpen();
    _tracking?.track(switch (kind) {
      _ModelRead.value => cursor._valueRead,
      _ModelRead.type => cursor._typeRead,
      _ModelRead.keys => cursor._keysRead,
      _ModelRead.presence => cursor._presenceRead,
    });
    return _locate(cursor);
  }

  ValueRef? _locate(FleeceCursor cursor) {
    final cached = _locations[cursor];
    if (cached != null) return cached.$1;
    final parent = cursor._parent;
    final ref = parent == null
        ? _root
        : cursor._memberOf(_locate(parent), strict: true);
    _locations[cursor] = (ref,);
    return ref;
  }

  _Transaction _begin() {
    _checkOpen();
    if (_active != null)
      throw StateError('A Fleece transaction is already open');
    return _active = _Transaction(this);
  }

  void dispose() {
    if (_disposed) return;
    _active?._close();
    _disposed = true;
    _locations = Expando();
    _tracking?.dispose();
  }
}

final class _Transaction implements _ModelAccess {
  _Transaction(this._owner);
  final _ModelDocument _owner;
  final _patch = Patch();
  bool _managed = false;
  bool _editing = false;
  bool get isActive => identical(_owner._active, this);

  void _checkActive() {
    if (!isActive) throw StateError('Fleece transaction is closed');
  }

  void _checkManual() {
    _checkActive();
    if (_managed || _editing) {
      throw StateError('The current operation owns the transaction');
    }
  }

  R _change<R>(R Function(_Transaction) change) {
    _checkActive();
    if (_editing)
      throw StateError('A collection or field write is in progress');
    _editing = true;
    try {
      return change(this);
    } finally {
      _editing = false;
    }
  }

  (ValueRef?, _PatchNode?) _resolve(
    FleeceCursor cursor, {
    List<(KeyPath, ValueRef)>? defaults,
    bool strict = true,
  }) {
    final parent = cursor._parent;
    if (parent == null)
      return (_patch._root.source ?? _owner._root, _patch._root);
    final (at, patch) = _resolve(parent, defaults: defaults, strict: strict);
    final step = cursor._path._steps.last;
    final node = patch?.children?[step];
    if (identical(node, _remove)) return (null, node);
    if (node?.source != null) return (node!.source, node);
    final appended = patch?.appended;
    if (appended != null && step is BigInt) {
      final index = step.toInt() - at!.asArray!.length;
      if (index >= 0)
        return (index < appended.length ? appended[index] : null, node);
    }
    return (cursor._memberOf(at, strict: strict, defaults: defaults), node);
  }

  int _arrayLength(FleeceCursor cursor) {
    _checkActive();
    final (at, node) = _resolve(cursor);
    final array = at?.asArray;
    if (array == null) throw const FormatException('Expected Fleece array');
    return array.length + (node?.appended?.length ?? 0);
  }

  void _append(FleeceCursor cursor, List<ValueRef> values) {
    _checkActive();
    final (at, current) = _resolve(cursor);
    if (at?.asArray == null)
      throw const FormatException('Expected Fleece array');
    if (values.isEmpty) return;
    final tail = current?.appended;
    if (tail != null) {
      tail.addAll(values);
    } else {
      final replacement = _PatchNode.inside(at, values);
      if (current?.children case final children?) {
        replacement.children!.addAll(children);
      }
      _stage(cursor, replacement);
    }
  }

  @override
  ValueRef? _get(FleeceCursor cursor, {_ModelRead kind = _ModelRead.value}) {
    _checkActive();
    final (at, node) = _resolve(cursor);
    if ((kind != _ModelRead.value && kind != _ModelRead.keys) ||
        at == null ||
        node?.children?.isNotEmpty != true && node?.appended == null) return at;
    // A getter for an entire parent includes pending edits to its children.
    // Reading a leaf never constructs the parent or its siblings.
    final encoder = Encoder()
      .._writeUpdated(at, Patch().._root = node!, canonical: true);
    return _modelRoot(encoder.finish());
  }

  void _stage(FleeceCursor cursor, _PatchNode change) {
    _checkActive();
    final parent = cursor._parent;
    if (parent != null) {
      final defaults = <(KeyPath, ValueRef)>[];
      final (at, parentPatch) =
          _resolve(parent, defaults: defaults, strict: false);
      final step = cursor._path._steps.last;
      if (step is BigInt) {
        final array = at?.asArray;
        if (array == null) throw StateError('The parent array is missing');
        RangeError.checkValidIndex(step.toInt(), array, 'index',
            array.length + (parentPatch?.appended?.length ?? 0));
      } else if (at?.asDict == null) {
        throw StateError(
            'Assign the parent dictionary before editing its fields');
      }
      for (final (path, value) in defaults) {
        _patch._put(path, _PatchNode.inside(value));
      }
    }
    _patch._put(cursor._path, change);
  }

  bool _touches(KeyPath path) {
    _PatchNode? node = _patch._root;
    for (final step in path._steps) {
      if (node?.source != null || identical(node, _remove)) return true;
      node = node?.children?[step];
    }
    return node?.source != null ||
        identical(node, _remove) ||
        node?.children?.isNotEmpty == true;
  }

  void commit() {
    _checkActive();
    final old = _owner._root;
    final tracking = _owner._tracking;
    final changed = <FleeceDependency>[];
    try {
      if (!_patch.isEmpty || !_owner._compacted) {
        // update writes only the reachable tree into a fresh standalone buffer.
        final keys = old.doc.sharedKeys;
        final encoder = Encoder(sharedKeys: keys, fixedSharedKeys: true)
          .._writeUpdated(old, _patch, canonical: true);
        final next = _modelRoot(encoder.finish(), sharedKeys: keys);
        if (tracking != null) {
          for (final field in tracking.fields) {
            if (!_touches(field.path)) continue;
            final a = field._cursor._resolve(old),
                b = field._cursor._resolve(next);
            final differs = switch (field._kind) {
              _ModelRead.value => !_sameModelValue(a, b),
              _ModelRead.type => (a?.type ?? ValueType.nullValue) !=
                  (b?.type ?? ValueType.nullValue),
              _ModelRead.keys => !_sameKeys(a, b),
              _ModelRead.presence => (a == null) != (b == null),
            };
            if (differs) changed.add(field);
          }
        }
        _owner._root = next;
        _owner._revision++;
        _owner._locations = Expando();
        _owner._compacted = true;
      }
    } finally {
      _close();
    }
    // Effects can read every committed field and can start a new transaction.
    if (changed.isNotEmpty) tracking!.publish(changed);
  }

  void rollback() {
    _checkActive();
    _close();
  }

  void _close() {
    if (isActive) {
      _owner._active = null;
      _patch._root = _PatchNode.inside();
    }
  }
}

bool _sameKeys(ValueRef? a, ValueRef? b) {
  if (a?.type != b?.type) return false;
  final array = a?.asArray;
  if (array != null) return array.length == b!.asArray!.length;
  final dict = a?.asDict;
  if (dict == null) return true;
  final other = b!.asDict!;
  return dict.length == other.length &&
      dict.entries.every((entry) => other[entry.key] != null);
}

bool _sameModelValue(ValueRef? a, ValueRef? b) {
  if (a == null || b == null) return a == b;
  if (identical(a.doc, b.doc) && a.position == b.position) return true;
  final h = a._header, k = b._header;
  if (h.type != k.type) return false;
  switch (h.type) {
    case ValueType.array:
      final left = a.asArray!, right = b.asArray!;
      if (left.length != right.length) return false;
      for (var i = 0; i < left.length; i++) {
        if (!_sameModelValue(left[i], right[i])) return false;
      }
      return true;
    case ValueType.dict:
      final left = a.asDict!, right = b.asDict!;
      if (left.length != right.length) return false;
      for (final entry in left.entries) {
        if (!_sameModelValue(entry.value, right[entry.key])) return false;
      }
      return true;
    case ValueType.extended:
      return h.arg == k.arg && _sameModelValue(a.payload, b.payload);
    case ValueType.integer:
      return a._number(h) == b._number(k);
    case ValueType.string || ValueType.data:
      return h.arg == k.arg &&
          _compareBytes(a._contents(h), b._contents(k)) == 0;
    case ValueType.float64:
      return FleeceCodecs.float64.read(a).bits ==
          FleeceCodecs.float64.read(b).bits;
    case ValueType.float32:
      return FleeceCodecs.float32.read(a).bits ==
          FleeceCodecs.float32.read(b).bits;
    case ValueType.boolean || ValueType.undefined || ValueType.nullValue:
      return h.arg == k.arg;
  }
}
