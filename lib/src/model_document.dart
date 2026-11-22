part of '../fleece.dart';

enum _ModelRead { value, type, keys }

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
  void _set<T>(FleeceCursor cursor, FleeceCodec<T> codec, T value);
}

/// A stable location, resolved against the current committed or draft root.
final class FleeceCursor {
  FleeceCursor._(this._access, this._path, [this._parent, this._field]);
  final _ModelAccess _access;
  final KeyPath _path;
  final FleeceCursor? _parent;
  final FleeceField<Object?>? _field;
  final _children = <Object, FleeceCursor>{};
  Object? _model;
  bool _binding = false;
  late final _defaultValue = _field?._encodeDefault();
  late final _valueRead = FleeceDependency._(this, _ModelRead.value);
  late final _typeRead = FleeceDependency._(this, _ModelRead.type);
  late final _keysRead = FleeceDependency._(this, _ModelRead.keys);

  FleeceCursor _at(Object step, [FleeceField<Object?>? field]) =>
      _children.putIfAbsent(
          step,
          () => FleeceCursor._(
              _access, KeyPath._([..._path._steps, step]), this, field));

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

  T get<T>(FleeceField<T> field) => field.read(_access._get(child(field)));

  /// Initializes a superclass constructor without subscribing a caller to its
  /// arguments. Inherited methods subsequently read the live properties.
  T initial<T>(FleeceField<T> field) {
    final access = _access;
    if (access is _ModelDocument) {
      access._checkOpen();
      return field.read(access._locate(child(field)));
    }
    return get(field);
  }

  bool get _constructing => _binding || (_parent?._constructing ?? false);

  void set<T>(FleeceField<T> field, T value) {
    // A superclass constructor can initialize fields via their virtual setters.
    // Opening an existing document must not turn those assignments into edits.
    if (!_constructing) _access._set(child(field), field.codec, value);
  }

  bool get hasValue =>
      _access._get(this, kind: _ModelRead.type)?.isNull == false;

  M? optionalObject<M extends Object>(M Function(FleeceCursor) bind) {
    final ref = _access._get(this, kind: _ModelRead.type);
    if (ref == null || ref.isNull) return null;
    FleeceCodecs.dictionary(ref);
    return (_model ??= bind(this)) as M;
  }

  M object<M extends Object>(M Function(FleeceCursor) bind) =>
      optionalObject(bind) ??
      (throw FormatException(
          'Missing required Fleece dictionary at ${_path._steps.last}'));

  List<T> listItems<T>(T Function(FleeceCursor) read) {
    if (_access._get(this, kind: _ModelRead.type)?.asArray == null) {
      throw const FormatException('Expected Fleece array');
    }
    return _ModelList(this, read);
  }

  Map<String, T> mapItems<T>(T Function(FleeceCursor) read) {
    if (_access._get(this, kind: _ModelRead.type)?.asDict == null) {
      throw const FormatException('Expected Fleece dictionary');
    }
    return _ModelMap(this, read);
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
    final ref = _access._get(this);
    if (ref == null) throw const FormatException('Missing Fleece model');
    return codec.read(ref);
  }

  void writeTo(Encoder encoder) {
    final ref = _access._get(this);
    if (ref?.asDict == null)
      throw const FormatException('Missing Fleece model');
    encoder.writeCopy(ref!);
  }

  Uint8List toBytes({SharedKeys? sharedKeys}) {
    final access = _access;
    if (sharedKeys == null && _parent == null && access is _ModelDocument) {
      access._checkOpen();
      return Uint8List.fromList(access._doc.bytes);
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
    final tx = _begin();
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
  void commit() => _transaction.commit();
  void rollback() => _transaction.rollback();
  void dispose() {
    final access = _access;
    if (access is _Transaction) {
      access._close();
    } else {
      _document.dispose();
    }
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
      cursor._access._get(cursor, kind: _ModelRead.keys)?.asArray?.length ??
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
  Iterable<String> get keys {
    final dict = cursor._access._get(cursor, kind: _ModelRead.keys)?.asDict;
    if (dict == null) throw const FormatException('Missing Fleece dictionary');
    return dict.entries.map((entry) => entry.key);
  }

  @override
  T? operator [](Object? key) {
    if (key is! String) return null;
    final dict = cursor._access._get(cursor, kind: _ModelRead.type)?.asDict;
    if (dict == null) throw const FormatException('Missing Fleece dictionary');
    if (dict[key] == null) {
      cursor._access._get(cursor, kind: _ModelRead.keys);
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
  _ModelDocument._(this._doc, this._tracking, this._compacted);
  factory _ModelDocument.open(Uint8List bytes, Uint8List? base,
      SharedKeys? keys, FleeceTracking Function()? tracking) {
    final table = keys == null ? null : SharedKeys.fromState(keys.toState());
    var doc = Doc(Uint8List.fromList(bytes),
        sharedKeys: table,
        base: base == null ? null : Uint8List.fromList(base));
    FleeceCodecs.dictionary(doc.root);
    if (base != null) doc = Doc(compact(doc), sharedKeys: table);
    return _ModelDocument._(doc, tracking?.call(), base != null);
  }

  Doc _doc;
  final FleeceTracking? _tracking;
  // Cache offsets only within the current committed buffer.
  final _locations = <FleeceCursor, ValueRef?>{};
  bool _compacted;
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
    });
    return _locate(cursor);
  }

  ValueRef? _locate(FleeceCursor cursor) => _locations.putIfAbsent(cursor, () {
        final parent = cursor._parent;
        if (parent == null) return _doc.root;
        return cursor._memberOf(_locate(parent), strict: true);
      });

  @override
  void _set<T>(FleeceCursor cursor, FleeceCodec<T> codec, T value) {
    final tx = _begin();
    try {
      tx._set(cursor, codec, value);
      tx.commit();
    } finally {
      tx._close();
    }
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
    _locations.clear();
    _tracking?.dispose();
  }
}

final class _Transaction implements _ModelAccess {
  _Transaction(this._owner);
  final _ModelDocument _owner;
  final _patch = Patch();
  bool get isActive => identical(_owner._active, this);

  void _checkActive() {
    if (!isActive) throw StateError('Fleece transaction is closed');
  }

  (ValueRef?, _PatchNode?) _resolve(
    FleeceCursor cursor, {
    List<(KeyPath, ValueRef)>? defaults,
    bool strict = true,
  }) {
    final parent = cursor._parent;
    if (parent == null) return (_owner._doc.root, _patch._root);
    final (at, patch) = _resolve(parent, defaults: defaults, strict: strict);
    final node = patch?.children?[cursor._path._steps.last];
    return (
      node?.source ?? cursor._memberOf(at, strict: strict, defaults: defaults),
      node
    );
  }

  @override
  ValueRef? _get(FleeceCursor cursor, {_ModelRead kind = _ModelRead.value}) {
    _checkActive();
    final (at, node) = _resolve(cursor);
    if (kind != _ModelRead.value ||
        at == null ||
        node?.children?.isNotEmpty != true) return at;
    // A getter for an entire parent includes pending edits to its children.
    // Reading a leaf never constructs the parent or its siblings.
    final encoder = Encoder()..writeUpdated(at, Patch().._root = node!);
    return Doc(encoder.finish()).root;
  }

  @override
  void _set<T>(FleeceCursor cursor, FleeceCodec<T> codec, T value) {
    _checkActive();
    // Capture the value now so a caller cannot mutate a list or binary field
    // after its setter has returned. A failed encoder leaves the patch intact.
    final source = Doc(codec.encode(value)).root;
    _checkActive();
    final parent = cursor._parent!;
    if (parent._parent != null) {
      final defaults = <(KeyPath, ValueRef)>[];
      if (_resolve(parent, defaults: defaults, strict: false).$1?.asDict ==
          null) {
        throw StateError('Assign the parent model before editing its fields');
      }
      for (final (path, value) in defaults) {
        _patch._put(path, _PatchNode.inside(value));
      }
    }
    _patch._put(cursor._path, _PatchNode.inside(source));
  }

  bool _touches(KeyPath path) {
    _PatchNode? node = _patch._root;
    for (final step in path._steps) {
      if (node?.source != null) return true;
      node = node?.children?[step];
    }
    return node?.source != null || node?.children?.isNotEmpty == true;
  }

  void commit() {
    _checkActive();
    final old = _owner._doc;
    final tracking = _owner._tracking;
    final changed = <FleeceDependency>[];
    try {
      if (!_patch.isEmpty || !_owner._compacted) {
        // update writes only the reachable tree into a fresh standalone buffer.
        final next = Doc(update(old, _patch), sharedKeys: old.sharedKeys);
        if (tracking != null) {
          for (final field in tracking.fields) {
            if (!_touches(field.path)) continue;
            final a = field._cursor._resolve(old.root),
                b = field._cursor._resolve(next.root);
            final differs = switch (field._kind) {
              _ModelRead.value => !_sameModelValue(a, b),
              _ModelRead.type => (a?.type ?? ValueType.nullValue) !=
                  (b?.type ?? ValueType.nullValue),
              _ModelRead.keys => !_sameKeys(a, b),
            };
            if (differs) changed.add(field);
          }
        }
        _owner._doc = next;
        _owner._locations.clear();
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
      _patch._root.children?.clear();
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
