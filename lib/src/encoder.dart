part of '../fleece.dart';

// Inline slots contain a big-endian wire word. Negative slots refer to an
// absolute byte position, including position zero in an external base.
int _pointer(int target) => -1 - target;

final class _Output {
  _Output() : this._(Uint8List(64));
  _Output._(this.bytes) : data = ByteData.sublistView(bytes);
  Uint8List bytes;
  ByteData data;
  int length = 0;

  @pragma('vm:prefer-inline')
  int reserve(int count) {
    final start = length, end = start + count;
    if (end > bytes.length) _grow(end);
    length = end;
    return start;
  }

  void _grow(int end) {
    final next = Uint8List(math.max(end, bytes.length * 2));
    next.setRange(0, length, bytes);
    bytes = next;
    data = ByteData.sublistView(next);
  }

  int putVarint(int at, int n) {
    while (n >= 128) {
      bytes[at++] = 128 | (n & 127);
      n ~/= 128;
    }
    bytes[at] = n;
    return at + 1;
  }

  int blob(int tag, int size, [ExtKind? ext]) {
    final header = size < 15 ? 1 : 1 + _varintSize(size);
    var at = reserve((ext == null ? 0 : 2) + _even(header + size));
    if (ext != null) {
      data.setUint16(at, 0x3100 + ext.index);
      at += 2;
    }
    bytes[at] = tag + math.min(size, 15);
    if (size >= 15) putVarint(at + 1, size);
    return at + header;
  }

  // Return the UTF-8 length for the short-string interner. The common ASCII
  // case copies and checks each code unit together.
  int text(String s, [ExtKind? ext]) {
    final size = s.length;
    if (size <= 64 && (size == 0 || s.codeUnitAt(0) < 128)) {
      final start = length, at = blob(0x40, size, ext);
      final out = bytes;
      var i = 0;
      for (; i < size; i++) {
        final c = s.codeUnitAt(i);
        if (c >= 128) break;
        out[at + i] = c;
      }
      if (i == size) return size;
      // Restore the append-only buffer, even if UTF-16 validation throws.
      out.fillRange(start, at + i, 0);
      length = start;
    }
    final utf = _utf8(s);
    final at = blob(0x40, utf.length, ext);
    bytes.setRange(at, at + utf.length, utf);
    return utf.length;
  }
}

final class _Frame {
  _Frame(this.outer, this.depth);
  final _Frame? outer;
  final int depth;
  _Frame? inner;
  int first = 0;
  bool dict = false;
  bool expectsKey = false;
  ExtKind? ext;
  bool inherited = false;
  List<Object>? keys;
  _MapFields? fields;
}

// A recurring map shape needs sorting only when its insertion-order keys
// change. Values always come from the current map, including identity maps.
final class _MapFields {
  _MapFields(int count)
      : names = List<String>.filled(count, ''),
        values = List<Object?>.filled(count, null),
        order = List<int>.generate(count, (i) => i, growable: false),
        keySlots = List<int?>.filled(count, null);
  final List<String> names;
  final List<Object?> values;
  final List<int> order;
  final List<int?> keySlots;
  int _index = 0;
  bool _changed = true;
  late final _visit = _field;

  void _field(dynamic key, dynamic value) {
    final i = _index++;
    final old = names[i];
    if (!identical(old, key) && old != key) {
      names[i] = key as String;
      _changed = true;
    }
    values[i] = value;
  }

  void load(Map map) {
    _index = 0;
    map.forEach(_visit);
    if (!_changed) return;
    order.sort((a, b) => _compareNames(names[a], names[b]));
    for (var i = 1; i < order.length; i++) {
      final key = names[order[i]];
      if (names[order[i - 1]] == key) {
        throw _EncoderState(EncodeErrorCode.duplicateKey,
            'Duplicate dictionary key ' + key, key);
      }
    }
    keySlots.fillRange(0, keySlots.length, null);
    _changed = false;
  }
}

bool _keysInOrder(List<Object> keys) {
  for (var i = 1; i < keys.length; i++) {
    if (_compareKeys(keys[i - 1], keys[i]) >= 0) return false;
  }
  return true;
}

int _compareKeys(Object a, Object b) {
  if (a is int) return b is int ? a.compareTo(b) : -1;
  if (b is int) return 1;
  if (a is String) return _compareNames(a, b as String);
  return _compareBytes(a as Uint8List, b as Uint8List);
}

/// Bottom-up writer for a single Fleece root. Calls to [writeKey] may be
/// made in any order. [writeValue] visits Dart maps in UTF-8 key order.
final class Encoder {
  Encoder(
      {this.sharedKeys,
      this.fixedSharedKeys = false,
      Uint8List? base,
      this.external = false})
      : _base = base {
    if (base != null && base.length.isOdd) {
      throw _EncoderArgument(EncodeErrorCode.badBase,
          'A Fleece base must have an even length', base.length);
    }
  }

  final SharedKeys? sharedKeys;
  final bool fixedSharedKeys;
  final Uint8List? _base;
  final bool external;
  final _out = _Output();
  _Frame? _frame, _firstFrame;
  // All open collections share this stack. Closing a collection replaces its
  // slice with one slot in the parent, retaining the capacity for siblings.
  SlotBuffer _slots = allocateSlots(0);
  int _slotCount = 0;
  final _strings = HashMap<String, int>();
  int? _root;
  ExtKind? _pending;
  bool _finished = false;

  int get _baseLength => _base?.length ?? 0;
  int get _position => _baseLength + _out.length;

  @pragma('vm:prefer-inline')
  void _checkValue() {
    final frame = _frame;
    if (_finished || (frame == null ? _root != null : frame.expectsKey))
      _invalidValue();
  }

  Never _invalidValue() {
    if (_finished)
      throw _EncoderState(
          EncodeErrorCode.incomplete, 'The encoder has been finished');
    if (_frame == null)
      throw _EncoderState(EncodeErrorCode.multipleRoots, 'Multiple roots');
    throw _EncoderState(EncodeErrorCode.expectedKey, 'Expected a key');
  }

  void _growSlots(int end) {
    final next = allocateSlots(math.max(end, math.max(8, _slots.length * 2)));
    next.setRange(0, _slotCount, _slots);
    _slots = next;
  }

  @pragma('vm:prefer-inline')
  void _addSlot(int slot) {
    final at = _slotCount;
    if (at == _slots.length) _growSlots(at + 1);
    _slots[at] = slot;
    _slotCount = at + 1;
  }

  @pragma('vm:prefer-inline')
  void _push(int slot) {
    final frame = _frame;
    if (frame == null) {
      _root = slot;
    } else {
      _addSlot(slot);
      frame.expectsKey = frame.dict;
    }
  }

  int _scalarSpace(int size) {
    _checkValue();
    final ext = _pending;
    final at = _out.reserve(size + (ext == null ? 0 : 2));
    _push(_pointer(_baseLength + at));
    if (ext == null) return at;
    _pending = null;
    _out.data.setUint16(at, 0x3100 + ext.index);
    return at + 2;
  }

  void _word(int word) {
    if (_pending == null) {
      _checkValue();
      _push(word);
    } else {
      final at = _scalarSpace(2);
      _out.data.setUint16(at, word);
    }
  }

  void _scalar(Uint8List bytes) {
    if (bytes.length == 2) {
      _word(bytes[0] * 256 + bytes[1]);
    } else {
      final at = _scalarSpace(_even(bytes.length));
      _out.bytes.setRange(at, at + bytes.length, bytes);
    }
  }

  void writeNull() => _word(0x3000);
  void writeBool(bool value) => _word(value ? 0x3800 : 0x3400);

  /// A standard signed i64. BigInt can represent exact i64s on every backend.
  void writeInt(Object value) {
    if (value is int && (!identical(1, 1.0) || value.bitLength < 32)) {
      _nativeInt(value, false);
    } else {
      _writeInteger(_integer(value), false);
    }
  }

  /// The standard unsigned wire encoding, without an extension tag.
  void writeUint(Object value) {
    if (value is int &&
        value >= 0 &&
        (!identical(1, 1.0) || value.bitLength < 32)) {
      _nativeInt(value, true);
    } else {
      _writeInteger(_integer(value), true);
    }
  }

  void _nativeInt(int n, bool unsigned) {
    if (n >= -2048 && n < 2048) {
      _word(n & 0xfff);
      return;
    }
    final length = (n.bitLength + (unsigned ? 0 : 1) + 7) ~/ 8;
    final offset = _integerStorage(length, unsigned);
    switch (length) {
      case 2:
        _out.data.setUint16(offset, n, _le);
      case 4:
        _out.data.setUint32(offset, n, _le);
      case 8:
        _out.data.setInt64(offset, n, _le);
      default:
        for (var i = 0; i < length; i++) {
          _out.bytes[offset + i] = n & 255;
          n >>= 8;
        }
    }
  }

  int _integerStorage(int length, bool unsigned) {
    final at = _scalarSpace(_even(1 + length));
    _out.bytes[at] = 0x10 + (unsigned ? 8 : 0) + length - 1;
    return at + 1;
  }

  void _writeInteger(BigInt n, bool unsigned) {
    _bounded(n, 64, signed: !unsigned);
    _boundedInteger(n, unsigned);
  }

  void _boundedInteger(BigInt n, bool unsigned) {
    if (n.bitLength < (identical(1, 1.0) ? 32 : 64)) {
      _nativeInt(n.toInt(), unsigned);
      return;
    }
    final length = (n.bitLength + (unsigned ? 0 : 1) + 7) ~/ 8;
    final at = _integerStorage(length, unsigned);
    _putLittle(_out.data, at, n, length);
  }

  void writeF32(double value) {
    final at = _floatStorage(0x20, 6);
    _out.data.setFloat32(at, value, _le);
  }

  int _floatStorage(int tag, int size) {
    final at = _scalarSpace(size);
    _out.bytes[at] = tag;
    return at + 2;
  }

  void _float32Bits(int bits, [int tag = 0x20]) {
    final at = _floatStorage(tag, 6);
    _out.data.setUint32(at, bits, _le);
  }

  void writeF64(double value) {
    if (value.isNaN) {
      _writeDouble(ByteData(8)..setFloat64(0, value, _le));
    } else {
      _finiteDouble(value);
    }
  }

  void _finiteDouble(double value) {
    if (_asF32(value) == value) {
      final at = _floatStorage(0x24, 6);
      _out.data.setFloat32(at, value, _le);
    } else {
      final at = _floatStorage(0x28, 10);
      _out.data.setFloat64(at, value, _le);
    }
  }

  void _writeDouble(ByteData full) {
    final value = full.getFloat64(0, _le);
    if (!value.isNaN) {
      _finiteDouble(value);
      return;
    }
    // Only narrow a NaN that reconstructs the same payload and sign.
    final high = full.getUint32(4, _le), low = full.getUint32(0, _le);
    if (high & 0x80000 != 0 && low & 0x1fffffff == 0) {
      final sign = high >= 0x80000000 ? 0x80000000 : 0;
      _float32Bits(
          sign + 0x7f800000 + (high & 0xfffff) * 8 + (low >>> 29), 0x24);
    } else {
      final at = _floatStorage(0x28, 10);
      _out.data.setUint32(at, low, _le);
      _out.data.setUint32(at + 4, high, _le);
    }
  }

  void _blob(int tag, Uint8List bytes) {
    if (bytes.length <= 1) {
      _word((tag + bytes.length) * 256 + (bytes.isEmpty ? 0 : bytes[0]));
    } else {
      final at = _blobSpace(tag, bytes.length);
      _out.bytes.setRange(at, at + bytes.length, bytes);
    }
  }

  void writeData(Uint8List bytes) => _blob(0x50, bytes);

  // For data of at least two bytes, whose body cannot be an inline word.
  int _dataSpace(int length) {
    assert(length >= 2);
    return _blobSpace(0x50, length);
  }

  int _blobSpace(int tag, int length) {
    _checkValue();
    final pos = _position;
    final at = _out.blob(tag, length, _pending);
    _pending = null;
    _push(_pointer(pos));
    return at;
  }

  void _coefficient(BigInt value) {
    final length = (value.bitLength + 8) ~/ 8;
    if (length == 1) {
      _word(0x5100 + value.toUnsigned(8).toInt());
    } else {
      final at = _dataSpace(length);
      _putLittle(_out.data, at, value, length);
    }
  }

  void _line(FleeceLine points) {
    if (points.isEmpty) {
      _word(0x5000);
    } else if (points is _PackedPoints && Endian.host == _le) {
      writeData(Uint8List.sublistView(points.xy));
    } else {
      final at = _dataSpace(16 * points.length);
      final data = _out.data;
      for (var i = 0; i < points.length; i++) {
        final (x, y) = points[i];
        data.setFloat64(at + 16 * i, x, _le);
        data.setFloat64(at + 16 * i + 8, y, _le);
      }
    }
  }

  void _rings(FleecePolygon rings) {
    beginArray();
    for (final ring in rings) {
      _line(ring);
    }
    endArray();
  }

  int _stringSlot(String value, {int? inBase}) {
    final baseTarget = inBase != null && inBase < _baseLength ? inBase : null;
    final length = value.length;
    if (length == 0) return 0x4000;
    if (length == 1 && value.codeUnitAt(0) < 128)
      return 0x4100 + value.codeUnitAt(0);
    if (length <= 15) {
      final cached = _strings[value];
      if (cached != null) return _pointer(baseTarget ?? cached);
    }
    if (baseTarget != null) {
      _validateUtf16(value);
      return _pointer(baseTarget);
    }
    final position = _position;
    if (_out.text(value) <= 15) _strings[value] = position;
    return _pointer(position);
  }

  void writeString(String value) {
    _checkValue();
    final ext = _pending;
    if (ext == null) {
      _push(_stringSlot(value));
    } else {
      final position = _position;
      _out.text(value, ext);
      _pending = null;
      _push(_pointer(position));
    }
  }

  void writeNone() {
    if (_pending != null)
      throw _EncoderState(
          EncodeErrorCode.extPayload, 'An extension cannot be its own payload');
    _word(0x3100);
  }

  /// Accepts an ExtKind or its byte ID.
  void beginExt(Object kind) {
    final id = kind is ExtKind ? kind.index : kind;
    if (id is! int || id <= 0 || id >= ExtKind.values.length)
      throw _EncoderState(
          EncodeErrorCode.badExtKind, 'Unknown or payload-free extension', id);
    if (_pending != null)
      throw _EncoderState(EncodeErrorCode.extPayload, 'A payload is pending');
    _checkValue();
    _pending = ExtKind.values[id];
  }

  void writeKey(String key) => _writeKey(key, null);
  void _writeKey(String key, int? inBase) {
    final frame = _frame;
    if (frame == null || !frame.expectsKey || _pending != null) {
      throw _EncoderState(
          EncodeErrorCode.unexpectedKey, 'Unexpected dictionary key');
    }
    final number =
        fixedSharedKeys ? sharedKeys?.number(key) : sharedKeys?.add(key);
    if (number != null) {
      (frame.keys ??= []).add(number);
      _addSlot(number);
    } else {
      final slot = _stringSlot(key, inBase: inBase);
      (frame.keys ??= []).add(key);
      _addSlot(slot);
    }
    frame.expectsKey = false;
  }

  void beginArray() => _begin(false);
  void beginDict() => _begin(true);
  void _begin(bool dict, [int? parent]) {
    _checkValue();
    final outer = _frame;
    if (outer != null && outer.depth >= maxDepth) {
      throw _EncoderState(
          EncodeErrorCode.tooDeep, 'Fleece nesting exceeds $maxDepth');
    }
    final frame = outer == null
        ? (_firstFrame ??= _Frame(null, 1))
        : (outer.inner ??= _Frame(outer, outer.depth + 1));
    frame.first = _slotCount;
    frame.dict = dict;
    frame.expectsKey = dict;
    frame.ext = _pending;
    frame.inherited = parent != null;
    if (parent != null) {
      // The parent reference precedes all user keys, including shared keys.
      _addSlot(0x0800);
      _addSlot(_pointer(parent));
    }
    _frame = frame;
    _pending = null;
  }

  void endArray() => _end(false);
  void endDict() => _end(true);
  void _end(bool dict) {
    final frame = _frame;
    if (frame == null ||
        frame.dict != dict ||
        frame.expectsKey != dict ||
        _pending != null) {
      throw _EncoderState(
          EncodeErrorCode.unbalanced, 'Unbalanced Fleece collection');
    }
    final first = frame.first, keys = frame.keys;
    final int slot;
    if (dict && keys != null && !_keysInOrder(keys)) {
      final ordered = _orderEntries(first, keys, frame.inherited);
      slot = _collectionSlot(frame, ordered, 0, ordered.length);
    } else {
      slot = _collectionSlot(frame, _slots, first, _slotCount - first);
    }
    keys?.clear();
    _slotCount = first;
    _frame = frame.outer;
    _push(slot);
  }

  SlotBuffer _orderEntries(int first, List<Object> keys, bool inherited) {
    final order = List.generate(keys.length, (i) => i)
      ..sort((a, b) => _compareKeys(keys[a], keys[b]));
    final slots = allocateSlots(2 * (keys.length + (inherited ? 1 : 0)));
    var out = 0;
    if (inherited) {
      slots[out++] = _slots[first];
      slots[out++] = _slots[first + 1];
      first += 2;
    }
    int? previous;
    for (final i in order) {
      if (previous != null && _compareKeys(keys[i], keys[previous]) == 0) {
        final key = keys[i];
        final name = key is int ? sharedKeys!.key(key)! : key as String;
        throw _EncoderState(EncodeErrorCode.duplicateKey,
            'Duplicate dictionary key ' + name, name);
      }
      slots[out++] = _slots[first + 2 * i];
      slots[out++] = _slots[first + 2 * i + 1];
      previous = i;
    }
    return slots;
  }

  int _collectionSlot(_Frame frame, SlotBuffer slots, int first, int length) {
    final tag = frame.dict ? 0x70 : 0x60;
    if (length == 0 && frame.ext == null) return tag * 256;
    final count = frame.dict ? length ~/ 2 : length;
    final short = math.min(count, _longCount);
    final extra = count - _longCount;
    final varBytes = extra < 0 ? 0 : _even(_varintSize(extra));
    final ext = frame.ext, extBytes = ext == null ? 0 : 2;
    final start = _out.length;
    final header = start + extBytes, body = header + 2 + varBytes;
    final base = _baseLength, position = base + body;
    // A pointer slot is -1 - target, so external targets have slots >= -base.
    final externalFloor = external ? -base : 0;
    final end = first + length;
    var wide = false;
    // A distant first entry fixes the width before reserving the body. Later
    // entries can still promote a partially written narrow collection.
    if (position > _maxNarrow && length != 0) {
      final head = slots[first];
      wide = head < 0 && position + head + 1 > _maxNarrow;
    }
    _out.reserve(body - start + length * (wide ? 4 : 2));
    if (!wide) {
      final data = _out.data;
      var at = body;
      for (var i = first; i < end; i++, at += 2) {
        var slot = slots[i];
        if (slot < 0) {
          final distance = base + at + 1 + slot;
          if (distance > _maxNarrow) {
            _out.reserve(length * 2);
            wide = true;
            break;
          }
          if (distance <= 0 || distance.isOdd) _invalidPointer();
          slot = (slot >= externalFloor ? 0xc000 : 0x8000) + (distance >> 1);
        }
        data.setUint16(at, slot);
      }
    }
    if (wide) _wideSlots(slots, first, end, body, base, externalFloor);
    final data = _out.data;
    if (ext != null) data.setUint16(start, 0x3100 + ext.index);
    data.setUint16(header, tag * 256 + short + (wide ? 0x0800 : 0));
    if (extra >= 0) _out.putVarint(header + 2, extra);
    return _pointer(base + start);
  }

  void _wideSlots(SlotBuffer slots, int first, int end, int at, int base,
      int externalFloor) {
    final bytes = _out.bytes;
    for (var i = first; i < end; i++, at += 4) {
      final slot = slots[i];
      if (slot < 0) {
        final distance = base + at + 1 + slot;
        // A valid byte distance uses bits 1..30 and is nonzero. Comparing
        // the full value also catches offsets beyond 32 bits on JavaScript.
        if (distance == 0 || distance != (distance & _maxWide))
          _invalidPointer();
        bytes[at] = (slot >= externalFloor ? 0xc0 : 0x80) | (distance >> 25);
        bytes[at + 1] = distance >> 17;
        bytes[at + 2] = distance >> 9;
        bytes[at + 3] = distance >> 1;
      } else {
        // Overwrite any narrow prefix, including both bytes of padding.
        bytes[at] = slot >> 8;
        bytes[at + 1] = slot;
        bytes[at + 2] = 0;
        bytes[at + 3] = 0;
      }
    }
  }

  Never _invalidPointer() => throw _EncoderState(
      EncodeErrorCode.tooLarge, 'Fleece pointer is out of range');

  int _pointerBits(int target, int position, int width) {
    final distance = position - target;
    if (distance <= 0 ||
        distance.isOdd ||
        distance > (width == 2 ? _maxNarrow : _maxWide)) {
      _invalidPointer();
    }
    final flag = external && target < _baseLength ? 0xc0 : 0x80;
    return flag * (width == 2 ? 0x100 : 0x1000000) + distance ~/ 2;
  }

  /// Writes a Dart value or one of the explicitly typed Fleece values.
  void writeValue(Object? value) {
    switch (value) {
      case null:
        writeNull();
      case bool b:
        writeBool(b);
      case int n when _wireInt(n):
        writeInt(n);
      case BigInt n:
        writeInt(n);
      case double d:
        writeF64(d);
      case FleeceFloat32 f:
        _float32Bits(f.bits);
      case FleeceFloat64 f:
        if (f._bits case final bits?) {
          _writeDouble(ByteData.sublistView(_little(bits, 8)));
        } else {
          writeF64(f.value);
        }
      case String s:
        writeString(s);
      case FleeceNone():
        writeNone();
      case FleeceValue v:
        if (_pending != null)
          throw _EncoderState(
              EncodeErrorCode.extPayload, 'A payload is pending');
        _checkValue();
        _pending = v.kind;
        v._writePayload(this);
      case Uint8List b:
        writeData(b);
      case List items:
        beginArray();
        final frame = _frame!;
        for (final item in items) {
          _child(item, frame);
        }
        endArray();
      case Map fields:
        _map(fields);
      default:
        throw ArgumentError.value(value, 'value', 'Unsupported Fleece value');
    }
  }

  // The enclosing owned collection has already established its writer state.
  // These common children go straight into its slot slice.
  void _child(Object? value, _Frame frame) {
    final int slot;
    if (value is String) {
      slot = _stringSlot(value);
    } else if (value is int &&
        value >= -2048 &&
        value < 2048 &&
        _wireInt(value)) {
      slot = value & 0xfff;
    } else if (value is bool) {
      slot = value ? 0x3800 : 0x3400;
    } else if (value == null) {
      slot = 0x3000;
    } else {
      writeValue(value);
      return;
    }
    _addSlot(slot);
    frame.expectsKey = frame.dict;
  }

  void _map(Map fields) {
    beginDict();
    if (fields.length <= 1) {
      fields.forEach((key, value) {
        writeKey(key as String);
        writeValue(value);
      });
      endDict();
      return;
    }
    final frame = _frame!;
    final size = fields.length;
    // Keep a bounded layout at each nesting level. A large or changing map
    // still visits every value in canonical key order.
    if (size > 32) {
      String? previous;
      for (final key in _names(fields)) {
        if (sharedKeys == null) {
          if (key == previous)
            throw _EncoderState(EncodeErrorCode.duplicateKey,
                'Duplicate dictionary key ' + key, key);
          _addSlot(_stringSlot(key));
          frame.expectsKey = false;
          previous = key;
        } else {
          writeKey(key);
        }
        _child(fields[key], frame);
      }
    } else {
      var layout = frame.fields;
      if (layout == null || layout.names.length != size) {
        frame.fields = layout = _MapFields(size);
      }
      layout.load(fields);
      for (var i = 0; i < size; i++) {
        final index = layout.order[i];
        if (sharedKeys == null) {
          var slot = layout.keySlots[index];
          if (slot == null) {
            final key = layout.names[index];
            slot = _stringSlot(key);
            // Longer UTF-8 names must be emitted at each occurrence.
            if (slot >= 0 || key.length <= 15 && _strings.containsKey(key)) {
              layout.keySlots[index] = slot;
            }
          }
          _addSlot(slot);
          frame.expectsKey = false;
        } else {
          writeKey(layout.names[index]);
        }
        final value = layout.values[index];
        layout.values[index] = null;
        _child(value, frame);
      }
    }
    endDict();
  }

  /// Refers to an already written value in the encoder's base.
  void writeRef(ValueRef value) {
    if (_pending != null)
      throw _EncoderState(EncodeErrorCode.extPayload,
          'A reference cannot be an extension payload');
    _checkValue();
    final pos = value.position;
    int size;
    try {
      size = value._size;
    } on FormatException {
      throw _EncoderArgument(
          EncodeErrorCode.notInBase, 'Invalid reference', pos);
    }
    if (pos.isOdd || pos + size > _baseLength) {
      throw _EncoderArgument(
          EncodeErrorCode.notInBase, 'Reference is outside the encoder base');
    }
    final bytes = value.doc._tail(pos);
    _push(size == 2 ? bytes[0] * 256 + bytes[1] : _pointer(pos));
  }

  /// Copies a value from any document, preserving the encoding of scalars.
  void writeCopy(ValueRef value) => _copyWithRoom(value, _ReadRoom(value.doc));

  void _copyWithRoom(ValueRef value, _ReadRoom room) {
    try {
      _copy(value, room);
    } on FormatException catch (e) {
      throw _EncoderState(
          EncodeErrorCode.invalidValue, 'Invalid value to copy', e);
    }
  }

  void _copy(ValueRef value, _ReadRoom room) {
    room.takeValue();
    final h = value._header;
    switch (h.type) {
      case ValueType.string:
        room.takeBytes(h.arg);
        writeString(_string(value._contents(h)));
      case ValueType.array:
        beginArray();
        for (final child in value.asArray!) {
          _copy(child, room);
        }
        endArray();
      case ValueType.dict:
        beginDict();
        final dict = value.asDict!;
        if (!dict._gaveAll)
          throw _EncoderState(
              EncodeErrorCode.invalidValue, 'Invalid dictionary entry');
        for (final entry in dict.entries) {
          room.takeBytes(_utf8(entry.key).length);
          writeKey(entry.key);
          _copy(entry.value, room);
        }
        endDict();
      case ValueType.extended when h.arg != 0:
        beginExt(h.arg);
        _copy(value.doc.valueAt(value.position + 2), room);
      default:
        if (h.type == ValueType.data) room.takeBytes(h.arg);
        final bytes = value.doc._tail(value.position);
        if (h.size > bytes.length)
          _malformed('Truncated value', value.position);
        _scalar(Uint8List.sublistView(bytes, 0, h.size));
    }
  }

  Uint8List finish() {
    final root = _root;
    if (_finished || _frame != null || _pending != null || root == null) {
      throw _EncoderState(
          EncodeErrorCode.incomplete, 'Incomplete or finished Fleece encoder');
    }
    var word = root;
    if (root < 0) {
      final target = -1 - root;
      if (_position - target > _maxNarrow) {
        final bits = _pointerBits(target, _position, 4);
        final at = _out.reserve(4);
        _out.data.setUint32(at, bits);
        word = 0x8002;
      } else {
        word = _pointerBits(target, _position, 2);
      }
    }
    final at = _out.reserve(2);
    _out.data.setUint16(at, word);
    _finished = true;
    return Uint8List.sublistView(_out.bytes, 0, _out.length);
  }
}
