part of '../fleece.dart';

enum ValueType {
  integer,
  float32,
  float64,
  nullValue,
  boolean,
  undefined,
  extended,
  string,
  data,
  array,
  dict
}

final class _Header {
  const _Header(this.type, this.size,
      [this.arg = 0, this.start = 0, this.width = 0]);
  final ValueType type;
  final int size;
  // Extension ID, collection count, byte length, boolean, or numeric tag.
  final int arg;
  final int start, width;
}

Never _malformed(String message, int position,
        [DecodeErrorCode code = DecodeErrorCode.malformed,
        int? kind,
        Object? key]) =>
    throw DecodeError(code, message, position: position, kind: kind, key: key);

/// A document over the supplied byte buffers. Keep the buffers and shared
/// key numbers stable for the lifetime of references into this document.
final class Doc {
  Doc(this.bytes, {this.base, this.sharedKeys}) {
    validate();
  }

  Doc.trusted(this.bytes, {this.base, this.sharedKeys});
  final Uint8List bytes;
  final Uint8List? base;
  final SharedKeys? sharedKeys;
  int get _baseLength => base?.length ?? 0;
  int get _end => _baseLength + bytes.length;

  (Uint8List, int) _locate(int position) {
    final baseLength = _baseLength;
    if (position < 0) _malformed('Position outside document', position);
    if (position < baseLength) return (base!, position);
    final offset = position - baseLength;
    if (offset >= bytes.length)
      _malformed('Position outside document', position);
    return (bytes, offset);
  }

  Uint8List _tail(int position) {
    final (buffer, offset) = _locate(position);
    return Uint8List.sublistView(buffer, offset);
  }

  bool _isPointer(int pos) {
    final (buffer, offset) = _locate(pos);
    return buffer[offset] >= 128;
  }

  int _pointerTarget(int pos, int width,
      {bool checkExternal = false, bool allowPointer = true}) {
    final (buffer, offset) = _locate(pos);
    if (buffer.length - offset < width)
      _malformed('Truncated pointer', pos, DecodeErrorCode.badPointer);
    return _pointerAt(pos, width, buffer, offset, checkExternal, allowPointer);
  }

  int _pointerAt(int pos, int width, Uint8List buffer, int offset,
      bool checkExternal, bool allowPointer) {
    final first = buffer[offset];
    var units = (first & 63) * 256 + buffer[offset + 1];
    if (width == 4)
      units = units * 65536 + buffer[offset + 2] * 256 + buffer[offset + 3];
    final target = pos - units * 2;
    if (units == 0 ||
        target < 0 ||
        checkExternal && first & 64 != 0 && target >= _baseLength ||
        !allowPointer && _isPointer(target)) {
      _malformed('Invalid Fleece pointer', pos, DecodeErrorCode.badPointer);
    }
    return target;
  }

  int _slotPosition(int pos, int width) {
    final (buffer, offset) = _locate(pos);
    if (buffer[offset] < 128) return pos;
    if (offset + width > buffer.length) {
      _malformed('Truncated pointer', pos, DecodeErrorCode.badPointer);
    }
    return _pointerAt(pos, width, buffer, offset, false, true);
  }

  ValueRef _slot(int pos, int width) => valueAt(_slotPosition(pos, width));
  ValueRef get root {
    try {
      return _root();
    } on FormatException {
      return valueAt(-1);
    }
  }

  ValueRef _root({bool checked = false}) {
    if (bytes.length < 2 ||
        checked && (bytes.length.isOdd || _baseLength.isOdd)) {
      throw const DecodeError(
          DecodeErrorCode.truncated, 'Truncated Fleece document');
    }
    var pos = _end - 2;
    if (_isPointer(pos)) {
      pos = _pointerTarget(pos, 2, checkExternal: checked);
      if (_isPointer(pos))
        pos = _pointerTarget(pos, 4,
            checkExternal: checked, allowPointer: !checked);
    }
    return valueAt(pos);
  }

  ValueRef valueAt(int position) => ValueRef._(this, position);

  /// Checks all reachable values, including type-specific payloads and the
  /// expanded size of repeated references.
  void validate() {
    final ref = _root(checked: true);
    _Validator(this).value(ref, 0, _isPointer(_end - 2) ? null : 2);
  }

  _Header _header(int pos) {
    final (buffer, offset) = _locate(pos);
    return _headerAt(pos, buffer, offset);
  }

  _Header _headerAt(int pos, Uint8List buffer, int offset) {
    final available = buffer.length - offset;
    if (available < 2) _malformed('Truncated Fleece value', pos);
    (int, int) lengthAt(int start) {
      try {
        return _readVarint(buffer, offset + start, available);
      } on FormatException {
        _malformed('Invalid Fleece length', pos);
      }
    }

    final tag = buffer[offset];
    _Header header;
    switch (tag >> 4) {
      case 0:
        return _Header(ValueType.integer, 2, tag);
      case 1:
        if (available < 2 + (tag & 7)) _malformed("Truncated integer", pos);
        header = _Header(ValueType.integer, _even(2 + (tag & 7)), tag);
      case 2:
        header = switch (tag) {
          0x20 => const _Header(ValueType.float32, 6),
          0x24 => const _Header(ValueType.float64, 6),
          0x28 => const _Header(ValueType.float64, 10),
          _ => _malformed('Invalid floating point tag', pos),
        };
        if (header.size > available)
          _malformed('Truncated floating point value', pos);
      case 3:
        return switch (tag) {
          0x30 => const _Header(ValueType.nullValue, 2),
          0x31 => _Header(ValueType.extended, 2, buffer[offset + 1]),
          0x34 || 0x38 => _Header(ValueType.boolean, 2, tag == 0x38 ? 1 : 0),
          0x3c => const _Header(ValueType.undefined, 2),
          _ => _malformed('Invalid special value', pos),
        };
      case 4 || 5:
        var n = tag & 15, start = 1;
        if (n == 15) {
          final (length, used) = lengthAt(1);
          n = length;
          start += used;
        }
        if (start + n > available) _malformed("Truncated data", pos);
        header = _Header(tag < 0x50 ? ValueType.string : ValueType.data,
            _even(start + n), n, start);
      case 6 || 7:
        final dict = tag >= 0x70;
        var n = (tag & 7) * 256 + buffer[offset + 1], start = 2;
        if (n == _longCount) {
          final (extra, used) = lengthAt(2);
          n += extra;
          start += _even(used);
        }
        final width = tag & 8 == 0 ? 2 : 4;
        header = _Header(dict ? ValueType.dict : ValueType.array,
            start + (dict ? 2 : 1) * n * width, n, start, width);
      default:
        _malformed('Unexpected pointer in place of a value', pos);
    }
    if (header.size > _even(available))
      _malformed('Truncated Fleece value', pos);
    return header;
  }
}

/// A position in a [Doc]. Accessors read only this value. [read] materializes
/// the subtree and also checks it when the document is trusted.
final class ValueRef {
  const ValueRef._(this.doc, this.position);
  final Doc doc;
  final int position;
  _Header get _header => doc._header(position);
  _Header? get _available {
    try {
      return _header;
    } on FormatException {
      return null;
    }
  }

  ValueType get type => _header.type;
  int get _size {
    final h = _header;
    if (h.type != ValueType.extended || h.arg == 0) return h.size;
    final payload = doc._header(position + 2);
    if (payload.type == ValueType.extended)
      _malformed('Nested extension payload', position);
    return 2 + payload.size;
  }

  ExtKind? get extKind {
    final h = _available;
    if (h == null) return null;
    if (h.type != ValueType.extended) return null;
    if (h.arg >= ExtKind.values.length) return null;
    return ExtKind.values[h.arg];
  }

  ValueRef? get payload {
    final kind = extKind;
    return kind == null || kind == ExtKind.none
        ? null
        : doc.valueAt(position + 2);
  }

  bool get isNull => _available?.type == ValueType.nullValue;
  bool? get asBool {
    final h = _available;
    if (h == null) return null;
    return h.type == ValueType.boolean ? h.arg != 0 : null;
  }

  BigInt? get asInteger {
    final h = _available;
    return h?.type == ValueType.integer ? _integerAt(h!) : null;
  }

  int _smallInt(_Header h) {
    final (buffer, offset) = doc._locate(position);
    return ((h.arg << 8) | buffer[offset + 1]).toSigned(12);
  }

  BigInt _integerAt(_Header h) {
    if (h.arg < 16) return BigInt.from(_smallInt(h));
    final (buffer, offset) = doc._locate(position);
    return _fromLittle(
        Uint8List.sublistView(buffer, offset + 1, offset + 2 + (h.arg & 7)),
        signed: h.arg & 8 == 0);
  }

  Object _number(_Header h) {
    if (h.arg < 16) return _smallInt(h);
    final (buffer, off) = doc._locate(position);
    final last = off + 1 + (h.arg & 7);
    final signed = h.arg & 8 == 0;
    if (last - off > 6 &&
        (identical(1, 1.0) ||
            !signed && last - off == 8 && buffer[last] >= 128)) {
      return _nativeInteger(_integerAt(h));
    }
    var n = signed ? buffer[last].toSigned(8) : buffer[last];
    for (var i = last - 1; i > off; i--) {
      n = 256 * n + buffer[i];
    }
    return n;
  }

  int? get asInt {
    final h = _available;
    if (h == null || h.type != ValueType.integer) return null;
    final n = _number(h);
    return n is int ? n : null;
  }

  double? get asDouble {
    final h = _available;
    if (h == null) return null;
    if (h.type != ValueType.float32 && h.type != ValueType.float64) return null;
    final data = ByteData.sublistView(doc._tail(position));
    return h.size == 6 ? data.getFloat32(2, _le) : data.getFloat64(2, _le);
  }

  Uint8List _contents(_Header h) {
    final (buffer, offset) = doc._locate(position);
    final start = offset + h.start;
    return Uint8List.sublistView(buffer, start, start + h.arg);
  }

  String _keyName(_Header h, int slot, Map<int, String> names) {
    if (position != slot && h.arg <= 15) {
      return names[position] ??= _checkedString(this, h);
    }
    return _checkedString(this, h);
  }

  String? get asString {
    final h = _available;
    if (h == null) return null;
    if (h.type != ValueType.string) return null;
    try {
      return _string(_contents(h));
    } on FormatException {
      return null;
    }
  }

  Uint8List? get asData {
    final h = _available;
    if (h == null) return null;
    return h.type == ValueType.data ? _contents(h).asUnmodifiableView() : null;
  }

  /// The packed elements of a vector, read directly from this document.
  FleeceVector? get asVector {
    if (extKind != ExtKind.vector) return null;
    final bytes = payload!.asData;
    return bytes != null && FleeceVector._fits(bytes)
        ? FleeceVector._fromBytes(bytes)
        : null;
  }

  ArrayRef? get asArray {
    final h = _available;
    if (h == null) return null;
    return h.type == ValueType.array
        ? ArrayRef._(doc, position + h.start, h.width, h.arg)
        : null;
  }

  DictRef? get asDict {
    final h = _available;
    if (h == null) return null;
    return h.type == ValueType.dict
        ? DictRef._(doc, position + h.start, h.width, h.arg)
        : null;
  }

  Object? read() => _OwnedReader(doc).read(position, 0);

  Object _readDouble(_Header h) {
    final bytes = doc._tail(position);
    final data = ByteData.sublistView(bytes);
    final d = h.size == 6 ? data.getFloat32(2, _le) : data.getFloat64(2, _le);
    if (d.isNaN) {
      final BigInt bits;
      if (h.size == 10) {
        bits = _fromLittle(Uint8List.sublistView(bytes, 2, 10));
      } else {
        final f = data.getUint32(2, _le);
        final sign = f >= 0x80000000 ? BigInt.one << 63 : BigInt.zero;
        bits = sign |
            (BigInt.from(0x7ff) << 52) |
            (BigInt.from(f & 0x7fffff) << 29) |
            (BigInt.one << 51);
      }
      return _doubleBits(d) == bits ? d : FleeceFloat64.fromBits(bits);
    }
    return identical(1, 1.0) && d is int ? FleeceFloat64(d) : d;
  }
}

final class ArrayRef extends IterableBase<ValueRef> {
  const ArrayRef._(this._doc, this._first, this._width, this.length);
  final Doc _doc;
  final int _first, _width;
  @override
  final int length;
  ValueRef? get(int index) {
    if (index < 0 || index >= length) return null;
    try {
      return _doc._slot(_first + index * _width, _width);
    } on FormatException {
      return null;
    }
  }

  ValueRef operator [](int index) {
    RangeError.checkValidIndex(index, this, 'index', length);
    return get(index) ?? _doc.valueAt(-1);
  }

  @override
  Iterator<ValueRef> get iterator =>
      Iterable.generate(length, (i) => get(i) ?? _doc.valueAt(-1)).iterator;
}

typedef DictIter = Iterator<MapEntry<String, ValueRef>>;

final class DictRef extends IterableBase<MapEntry<String, ValueRef>> {
  const DictRef._(this._doc, this._first, this._width, this._count);
  final Doc _doc;
  final int _first, _width, _count;
  ValueRef _slot(int i) => _doc._slot(_first + i * _width, _width);
  Object _keyAt(int i) {
    final v = _slot(i * 2);
    final h = v._header;
    if (h.type == ValueType.string) return v._contents(h);
    return v.asInt ?? _malformed('Invalid dictionary key', v.position);
  }

  String _name(Object key) => key is int
      ? _doc.sharedKeys?.key(key) ??
          _malformed('Missing shared key $key', _first)
      : _string(key as Uint8List);
  bool get _inherits {
    try {
      if (_count == 0) return false;
      final key = _slot(0);
      final (buffer, at) = _doc._locate(key.position);
      final tag = buffer[at];
      if (tag == 8) return at + 1 < buffer.length && buffer[at + 1] == 0;
      return tag >> 4 == 1 && key.asInt == _parentKey;
    } on FormatException {
      return false;
    }
  }

  DictRef? get _parent {
    if (!_inherits) return null;
    try {
      final parent = _slot(1).asDict;
      return parent != null && parent._first < _first ? parent : null;
    } on FormatException {
      return null;
    }
  }

  int? _find(Object key) {
    var low = _inherits ? 1 : 0, high = _count;
    while (low < high) {
      final mid = low + (high - low) ~/ 2;
      final cmp = _compareKeys(_keyAt(mid), key);
      if (cmp == 0) return mid;
      if (cmp < 0) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return null;
  }

  int? _keyPosition(String key) {
    final entry = _find(_utf8(key));
    return entry == null ? null : _slot(2 * entry).position;
  }

  Iterable<DictRef> get _chain sync* {
    DictRef? dict = this;
    while (dict != null) {
      yield dict;
      dict = dict._parent;
    }
  }

  ValueRef? _lookup(String name) {
    final text = _utf8(name);
    final number = _doc.sharedKeys?.number(name);
    for (final d in _chain) {
      final index = (number == null ? null : d._find(number)) ?? d._find(text);
      if (index != null) return d._slot(2 * index + 1);
    }
    return null;
  }

  /// Binary search in the stored key order, including any parent dictionaries.
  ValueRef? operator [](String key) {
    try {
      final value = _lookup(key);
      return value?.type == ValueType.undefined ? null : value;
    } on FormatException {
      return null;
    }
  }

  bool get isEmpty => length == 0;

  @override
  DictIter get iterator => entries.iterator;

  bool get _gaveAll {
    for (final d in _chain) {
      for (var i = d._inherits ? 1 : 0; i < d._count; i++) {
        try {
          d._name(d._keyAt(i));
          d._slot(2 * i + 1);
        } on FormatException {
          return false;
        }
      }
    }
    return true;
  }

  int get length => _inherits ? entries.length : _count;
  Iterable<MapEntry<String, ValueRef>> get _own => _ownFrom(_inherits ? 1 : 0);
  Iterable<MapEntry<String, ValueRef>> _ownFrom(int start) sync* {
    for (var i = start; i < _count; i++) {
      try {
        yield MapEntry(_name(_keyAt(i)), _slot(2 * i + 1));
      } on FormatException {
        continue;
      }
    }
  }

  Iterable<MapEntry<String, ValueRef>> get entries sync* {
    if (!_inherits) {
      yield* _ownFrom(0);
      return;
    }
    for (final (key, position, _) in _visibleSlots({})) {
      yield MapEntry(key, _doc.valueAt(position));
    }
  }

  Iterable<MapEntry<String, ValueRef>> _orderedEntries(bool canonical) =>
      canonical && _doc.sharedKeys != null && !_inherits
          ? (entries.toList()..sort((a, b) => _compareNames(a.key, b.key)))
          : entries;

  Iterable<(String, int, int)> _visibleSlots(Map<int, String> names) sync* {
    // Resolve shadows before reading values. Keep the wire byte length with
    // the winning slot so key accounting never needs to re-encode UTF-8.
    final visible = <String, (int, int)>{};
    for (final layer in _chain.toList().reversed) {
      final inherits = layer._inherits;
      final width = layer._width;
      for (var i = inherits ? 1 : 0; i < layer._count; i++) {
        try {
          final slot = layer._first + 2 * i * width;
          final ref = _doc._slot(slot, width), h = ref._header;
          final String key;
          final int size;
          if (h.type == ValueType.string) {
            key = ref._keyName(h, slot, names);
            size = h.arg;
          } else {
            final n = h.type == ValueType.integer ? ref._number(h) : null;
            final name = n is int ? _doc.sharedKeys?.key(n) : null;
            if (name == null) continue;
            key = name;
            size = key.length;
          }
          final position = _doc._slotPosition(slot + width, width);
          if (inherits) {
            final (buf, off) = _doc._locate(position);
            if (off + 1 < buf.length && buf[off] == 0x3c) {
              visible.remove(key);
              continue;
            }
          }
          visible[key] = (position, size);
        } on FormatException {
          continue;
        }
      }
    }
    final keys = visible.keys.toList()..sort(_compareNames);
    for (final key in keys) {
      final (position, size) = visible[key]!;
      yield (key, position, size);
    }
  }
}

/// The shallow contents of a slot, including reserved or unreadable slots.
enum ItemType {
  invalid,
  nullValue,
  undefined,
  boolean,
  integer,
  unsigned,
  float32,
  float64,
  string,
  data,
  array,
  dict,
  extended
}

final class Item {
  const Item(this.type, [this.value, this.extensionId]);
  final ItemType type;

  /// Scalar value, collection view, or the ValueRef of an extension payload.
  final Object? value;
  final int? extensionId;
}

extension ItemReader on ValueRef {
  BigInt? get asI64 {
    final n = asInteger;
    return n != null && n.bitLength < 64 ? n : null;
  }

  BigInt? get asU64 {
    final n = asInteger;
    return n != null && !n.isNegative ? n : null;
  }

  Uint8List? get asUtf8 {
    final h = _available;
    if (h == null) return null;
    if (h.type != ValueType.string) return null;
    final bytes = _contents(h);
    try {
      _string(bytes);
    } on FormatException {
      return null;
    }
    return bytes.asUnmodifiableView();
  }

  Item get item {
    try {
      final h = _header;
      return switch (h.type) {
        ValueType.integer =>
          Item(asI64 == null ? ItemType.unsigned : ItemType.integer, asInteger),
        ValueType.float32 => Item(ItemType.float32, asDouble),
        ValueType.float64 => Item(ItemType.float64, asDouble),
        ValueType.boolean => Item(ItemType.boolean, asBool),
        ValueType.nullValue => const Item(ItemType.nullValue),
        ValueType.undefined => const Item(ItemType.undefined),
        ValueType.string => asString == null
            ? const Item(ItemType.invalid)
            : Item(ItemType.string, asString),
        ValueType.data => Item(ItemType.data, asData),
        ValueType.array => Item(ItemType.array, asArray),
        ValueType.dict => Item(ItemType.dict, asDict),
        ValueType.extended => Item(ItemType.extended,
            h.arg == 0 ? null : doc.valueAt(position + 2), h.arg),
      };
    } on FormatException {
      return const Item(ItemType.invalid);
    }
  }
}
