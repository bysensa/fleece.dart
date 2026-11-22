part of '../fleece.dart';

// Reordering a collection copies wire values, including fields unknown to the
// schema. Only new elements go through the user's codec. A value returned by
// removeAt/remove owns its old location even if another element takes its slot.
mixin _ModelElements<T, V extends T> {
  FleeceCodec<T> get _codec;
  V Function(FleeceCursor)? get _bind;

  V _item(FleeceCursor at) {
    final bind = _bind;
    return bind == null ? _codec.bindValue(at) as V : bind(at);
  }

  V _detached(ValueRef ref) {
    final bind = _bind;
    return bind == null
        ? _codec.read(ref) as V
        : bind(FleeceCursor._snapshot(ref));
  }

  ValueRef _encode(T value) => _modelRoot(_codec.encode(value));
}

/// A document-backed Dart list. Reads expose the bound subtype [V] and
/// writes accept the original field type [T].
final class FleeceList<T, V extends T> extends ListBase<V>
    with _ModelElements<T, V> {
  FleeceList._(this._cursor, this._codec, this._bind);
  final FleeceCursor _cursor;
  @override
  final FleeceCodec<T> _codec;
  @override
  final V Function(FleeceCursor)? _bind;

  @override
  int get length {
    final access = _cursor._bindingOwner?._initializing ?? _cursor._access;
    if (access is _Transaction) return access._arrayLength(_cursor);
    return _cursor._get(kind: _ModelRead.keys)?.asArray?.length ??
        (throw const FormatException('Expected Fleece array'));
  }

  @override
  V operator [](int index) {
    final at = _cursor._at(BigInt.from(index));
    // Reading an existing index subscribes to that element, independently of
    // appends and removals at the end of the array.
    if (at._get(kind: _ModelRead.presence) == null) {
      throw RangeError.index(index, this, 'index', null, length);
    }
    return _item(at);
  }

  @override
  void operator []=(int index, T value) =>
      _cursor._at(BigInt.from(index))._write(_codec, value);

  // Keep the complete operation private until iteration, callbacks, bounds
  // checks and encoding have succeeded, including inside an existing draft.
  R _edit<R>(R Function(List<ValueRef>) change) => _cursor._edit((tx) {
        final array = tx._get(_cursor)?.asArray;
        if (array == null) throw const FormatException('Expected Fleece array');
        final slots = array.toList();
        final result = change(slots);
        final encoder = Encoder()..beginArray();
        for (final ref in slots) {
          encoder._copyWithRoom(ref, _ReadRoom(ref.doc), canonical: true);
        }
        encoder.endArray();
        tx._stage(_cursor, _PatchNode.inside(_modelRoot(encoder.finish())));
        return result;
      });

  @override
  set length(int size) => _edit<void>((slots) {
        RangeError.checkNotNegative(size, 'length');
        if (size <= slots.length) {
          slots.removeRange(size, slots.length);
        } else {
          slots.addAll(List.filled(size - slots.length, _encode(null as T)));
        }
      });
  @override
  set first(T value) {
    if (isEmpty) throw StateError('No element');
    this[0] = value;
  }

  @override
  set last(T value) {
    if (isEmpty) throw StateError('No element');
    this[length - 1] = value;
  }

  @override
  void add(T value) =>
      _cursor._edit((tx) => tx._append(_cursor, [_encode(value)]));
  @override
  void addAll(Iterable<T> values) =>
      _cursor._edit((tx) => tx._append(_cursor, values.map(_encode).toList()));
  @override
  void insert(int index, T value) =>
      _edit<void>((slots) => slots.insert(index, _encode(value)));
  @override
  void insertAll(int index, Iterable<T> values) =>
      _edit<void>((slots) => slots.insertAll(index, values.map(_encode)));
  @override
  void setAll(int index, Iterable<T> values) =>
      _edit<void>((slots) => slots.setAll(index, values.map(_encode)));
  @override
  void setRange(int start, int end, Iterable<T> values, [int skipCount = 0]) =>
      _edit<void>((slots) =>
          slots.setRange(start, end, values.map(_encode), skipCount));
  @override
  void replaceRange(int start, int end, Iterable<T> values) => _edit<void>(
      (slots) => slots.replaceRange(start, end, values.map(_encode)));
  @override
  void fillRange(int start, int end, [T? value]) => _edit<void>((slots) {
        RangeError.checkValidRange(start, end, slots.length);
        if (start != end) slots.fillRange(start, end, _encode(value as T));
      });
  @override
  void removeRange(int start, int end) =>
      _edit<void>((slots) => slots.removeRange(start, end));
  @override
  V removeAt(int index) => _edit((slots) => _detached(slots.removeAt(index)));
  @override
  V removeLast() => _edit((slots) => _detached(slots.removeLast()));
  @override
  bool remove(Object? value) => _edit((slots) {
        for (var i = 0; i < slots.length; i++) {
          if (this[i] == value) {
            slots.removeAt(i);
            return true;
          }
        }
        return false;
      });
  @override
  void removeWhere(bool Function(V) test) => _edit<void>((slots) {
        var index = 0;
        slots.removeWhere((_) => test(this[index++]));
      });
  @override
  void retainWhere(bool Function(V) test) => removeWhere((item) => !test(item));
  @override
  void sort([int Function(V, V)? compare]) => _edit<void>((slots) {
        final values = {
          for (var i = 0; i < slots.length; i++) slots[i]: this[i]
        };
        slots.sort((a, b) {
          final left = values[a] as V, right = values[b] as V;
          return compare != null
              ? compare(left, right)
              : (left as Comparable).compareTo(right);
        });
      });
  @override
  void shuffle([math.Random? random]) =>
      _edit<void>((slots) => slots.shuffle(random));
  @override
  void clear() => _edit<void>((slots) => slots.clear());
}

/// A document-backed dictionary with individually observable keys.
final class FleeceMap<T, V extends T> extends MapBase<String, V>
    with _ModelElements<T, V> {
  FleeceMap._(this._cursor, this._codec, this._bind);
  final FleeceCursor _cursor;
  @override
  final FleeceCodec<T> _codec;
  @override
  final V Function(FleeceCursor)? _bind;

  @override
  Iterable<String> get keys => _cursor._dictionaryKeys;

  @override
  bool containsKey(Object? key) =>
      key is String && _cursor._at(key)._get(kind: _ModelRead.presence) != null;
  @override
  V? operator [](Object? key) =>
      key is String && containsKey(key) ? _item(_cursor._at(key)) : null;
  @override
  void operator []=(String key, T value) =>
      _cursor._at(key)._write(_codec, value);

  @override
  V? remove(Object? key) {
    if (key is! String) return null;
    return _cursor._edit((tx) {
      final at = _cursor._at(key);
      final old = tx._get(at);
      if (old == null) return null;
      final result = _detached(old);
      tx._stage(at, _remove);
      return result;
    });
  }

  // Finish user code and encode every replacement before changing the patch.
  // Keys are literal Fleece keys and may contain path punctuation.
  void _apply(_Transaction tx, Map<String, _PatchNode> changes) {
    for (final entry in changes.entries) {
      _utf8(entry.key);
    }
    for (final entry in changes.entries) {
      tx._stage(_cursor._at(entry.key), entry.value);
    }
  }

  @override
  void addAll(Map<String, T> other) => addEntries(other.entries);
  @override
  void addEntries(Iterable<MapEntry<String, T>> entries) =>
      _cursor._edit((tx) => _apply(tx, {
            for (final e in entries) e.key: _PatchNode.inside(_encode(e.value))
          }));
  @override
  V putIfAbsent(String key, T Function() ifAbsent) {
    final at = _cursor._at(key);
    if (at._get(kind: _ModelRead.presence) != null) return _item(at);
    return _replace(at, (_) => ifAbsent());
  }

  @override
  V update(String key, T Function(V) update, {T Function()? ifAbsent}) {
    final at = _cursor._at(key);
    return _replace(at, (tx) {
      final ref = tx._get(at);
      if (ref == null && ifAbsent == null)
        throw ArgumentError.value(key, 'key', 'Key is absent');
      return ref == null ? ifAbsent!() : update(_detached(ref));
    });
  }

  V _replace(FleeceCursor at, T Function(_Transaction) makeValue) {
    final owner = _cursor._document, revision = owner._revision;
    final written = _cursor._edit((tx) {
      final ref = _encode(makeValue(tx));
      tx._stage(at, _PatchNode.inside(ref));
      return ref;
    });
    // An effect can synchronously replace the value again during publication.
    // Return what this operation wrote even if its path has since disappeared.
    if (owner._disposed ||
        owner._revision > revision + 1 &&
            !_sameModelValue(written, at._resolve(owner._root))) {
      return _detached(written);
    }
    return _item(at);
  }

  @override
  void updateAll(T Function(String, V) update) => _cursor._edit((tx) {
        final entries = FleeceCodecs.dictionary(tx._get(_cursor)!).entries;
        _apply(tx, {
          for (final e in entries)
            e.key: _PatchNode.inside(_encode(update(e.key, _detached(e.value))))
        });
      });
  @override
  void removeWhere(bool Function(String, V) test) => _cursor._edit((tx) {
        final entries = FleeceCodecs.dictionary(tx._get(_cursor)!).entries;
        _apply(tx, {
          for (final e in entries)
            if (test(e.key, this[e.key] as V)) e.key: _remove
        });
      });
  @override
  void clear() => _cursor._edit((tx) {
        final dict = FleeceCodecs.dictionary(tx._get(_cursor)!);
        _apply(tx, {for (final e in dict.entries) e.key: _remove});
      });
}
