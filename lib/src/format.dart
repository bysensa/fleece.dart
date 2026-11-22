part of '../fleece.dart';

const formatVersion = 1;
const maxDepth = 128;
const maxInherited = 16;
const _longCount = 2047;
const _maxNarrow = 0x3fff * 2;
const _maxWide = 0x3fffffff * 2;
const _parentKey = -2048;
const _le = Endian.little;

/// The byte after 0x31, in wire order.
enum ExtKind {
  none,
  i8,
  u8,
  i16,
  u16,
  i32,
  u32,
  u64,
  f16,
  decimal,
  bigDecimal,
  duration,
  datetime,
  uuid,
  date,
  time,
  timestamp,
  interval,
  table,
  recordId,
  file,
  range,
  regex,
  set,
  geometry,
  vector,
  text
}

int _even(int n) => n + (n & 1);

int _varintSize(int n) => n < 128 ? 1 : (n.bitLength + 6) ~/ 7;

List<int> _varint(int n) => n < 128 ? [n] : varint.encodeVarint(BigInt.from(n));

(int, int) _readVarint(Uint8List bytes, int start, int limit,
    {bool minimal = false}) {
  // Lengths in real documents usually fit in one to four bytes. Keep u64
  // truncation semantics in the slow path for noncanonical wire headers.
  var value = 0, shift = 1;
  for (var i = start; i < bytes.length && i < start + 4; i++) {
    final b = bytes[i];
    value += (b & 127) * shift;
    if (b < 128) {
      if (value > limit || minimal && i != start && b == 0) {
        throw FormatException('Invalid Fleece varint', null, start);
      }
      return (value, i - start + 1);
    }
    shift *= 128;
  }
  final (n, used) = varint.decodeVarint(bytes, start, minimal: minimal);
  if (n > BigInt.from(limit))
    throw FormatException('Fleece varint exceeds available space', null, start);
  return (n.toInt(), used);
}

// JavaScript represents integral doubles (including signed zero and infinity)
// with the same number class as Dart int. Only the i64 range is a native
// Fleece integer; explicit FleeceFloat64 preserves the other integral doubles.
bool _wireInt(Object? value) =>
    value is int &&
    (!identical(1, 1.0) ||
        value.isFinite &&
            value >= -9223372036854775808.0 &&
            value < 9223372036854775808.0 &&
            !(value == 0 && value.toDouble().isNegative));

BigInt _integer(Object value) => switch (value) {
      int n => BigInt.from(n),
      BigInt n => n,
      _ =>
        throw ArgumentError.value(value, 'value', 'Expected an int or BigInt'),
    };

BigInt _bounded(BigInt n, int bits, {required bool signed}) {
  final fits =
      signed ? n.bitLength < bits : !n.isNegative && n.bitLength <= bits;
  if (!fits)
    throw ArgumentError.value(n, 'value', 'Outside the $bits-bit range');
  return n;
}

// BigInt.toInt clamps on the VM and can round on JavaScript.
Object _nativeInteger(BigInt n) {
  final fits = identical(1, 1.0) ? n.abs().bitLength <= 53 : n.bitLength < 64;
  return fits ? n.toInt() : n;
}

BigInt _fromLittle(Uint8List bytes, {bool signed = false}) {
  if (bytes.isEmpty) return BigInt.zero;
  if (bytes.length == 8 && !identical(1, 1.0)) {
    final n = ByteData.sublistView(bytes).getInt64(0, _le);
    final value = BigInt.from(n);
    return !signed && n < 0 ? value.toUnsigned(64) : value;
  }
  if (bytes.length > 8 && bytes.length <= 64) {
    final data = ByteData.sublistView(bytes);
    var i = bytes.length;
    var n = signed && bytes.last >= 128 ? -BigInt.one : BigInt.zero;
    while (i >= 4) {
      i -= 4;
      n = (n << 32) | BigInt.from(data.getUint32(i, _le));
    }
    while (i > 0) {
      n = (n << 8) | BigInt.from(bytes[--i]);
    }
    return n;
  }
  if (bytes.length <= 8) {
    // Each native word is exact on JavaScript as well as the VM.
    final split = bytes.length > 4 ? 4 : 0;
    var word = signed ? bytes.last.toSigned(8) : bytes.last;
    for (var i = bytes.length - 2; i >= split; i--) {
      word = word * 256 + bytes[i];
    }
    if (split == 0) return BigInt.from(word);
    final low = BigInt.from(ByteData.sublistView(bytes).getUint32(0, _le));
    return word == 0 ? low : (BigInt.from(word) << 32) | low;
  }
  // Long coefficients occur in bigdecimal. Parsing hex avoids repeatedly
  // shifting an ever-growing BigInt.
  final digits = StringBuffer();
  for (var i = bytes.length - 1; i >= 0; i--) {
    digits.write(bytes[i].toRadixString(16).padLeft(2, '0'));
  }
  final value = BigInt.parse(digits.toString(), radix: 16);
  return signed ? value.toSigned(8 * bytes.length) : value;
}

Uint8List _little(BigInt n, int length) {
  final bytes = Uint8List(length);
  _putLittle(ByteData.sublistView(bytes), 0, n, length);
  return bytes;
}

void _putLittle(ByteData data, int at, BigInt n, int length) {
  if (!identical(1, 1.0) && length == 8) {
    data.setInt64(at, (n.bitLength < 64 ? n : n.toSigned(64)).toInt(), _le);
    return;
  }
  if (length <= 64) {
    var i = 0;
    for (; i + 4 <= length; i += 4) {
      data.setUint32(at + i, n.toUnsigned(32).toInt(), _le);
      n >>= 32;
    }
    if (i < length) {
      var tail = n.toUnsigned((length - i) * 8).toInt();
      for (; i < length; i++) {
        data.setUint8(at + i, tail & 255);
        tail >>= 8;
      }
    }
    return;
  }
  final hex =
      n.toUnsigned(length * 8).toRadixString(16).padLeft(length * 2, '0');
  for (var i = 0; i < length; i++) {
    final end = hex.length - 2 * i;
    data.setUint8(at + i, int.parse(hex.substring(end - 2, end), radix: 16));
  }
}

Uint8List _utf8(String s) {
  _validateUtf16(s);
  return utf8.encode(s);
}

void _validateUtf16(String s) {
  // Rust strings contain only Unicode scalar values. Dart's UTF-8 encoder
  // would silently replace an unpaired UTF-16 surrogate.
  for (var i = 0; i < s.length; i++) {
    final unit = s.codeUnitAt(i);
    if (unit < 0xd800 || unit > 0xdfff) continue;
    if (unit >= 0xdc00 ||
        ++i == s.length ||
        (s.codeUnitAt(i) & 0xfc00) != 0xdc00) {
      throw ArgumentError.value(s, 'string', 'Unpaired UTF-16 surrogate');
    }
  }
}

// Utf8Decoder normally discards a leading BOM. In a Fleece string U+FEFF
// is content, including when it is the first character of a dictionary key.
String _string(Uint8List bytes) {
  final decoded = utf8.decode(bytes);
  return bytes.length >= 3 &&
          bytes[0] == 0xef &&
          bytes[1] == 0xbb &&
          bytes[2] == 0xbf
      ? '\ufeff$decoded'
      : decoded;
}

int _compareBytes(List<int> a, List<int> b) {
  final length = math.min(a.length, b.length);
  for (var i = 0; i < length; i++) {
    if (a[i] != b[i]) return a[i] - b[i];
  }
  return a.length.compareTo(b.length);
}

// UTF-8 sorts by Unicode scalar value. Comparing UTF-16 code units would
// put supplementary characters before U+E000..U+FFFF.
int _compareNames(String a, String b, [int start = 0]) {
  final length = math.min(a.length, b.length);
  for (var i = start; i < length; i++) {
    final x = a.codeUnitAt(i), y = b.codeUnitAt(i);
    if (x == y) continue;
    if (x < 0xd800 && y < 0xd800) return x - y;
    return _compareRunes(a, b);
  }
  return a.length.compareTo(b.length);
}

int _compareRunes(String a, String b) {
  final left = a.runes.iterator;
  final right = b.runes.iterator;
  while (left.moveNext()) {
    if (!right.moveNext()) return 1;
    if (left.current != right.current) return left.current - right.current;
  }
  return right.moveNext() ? -1 : 0;
}

List<String> _names(Map map) {
  final keys = [for (final key in map.keys) key as String];
  for (var i = 1; i < keys.length; i++) {
    if (_compareNames(keys[i - 1], keys[i]) > 0) {
      final prefix = keys.length > 32 ? _commonPrefix(keys) : 0;
      if (prefix == 0) {
        keys.sort(_compareNames);
      } else {
        keys.sort((a, b) => _compareNames(a, b, prefix));
      }
      break;
    }
  }
  return keys;
}

// Field names in large dictionaries may share a namespace. Skip the common
// UTF-16 prefix in every comparison after checking it once per name.
int _commonPrefix(List<String> names) {
  final first = names.first;
  var length = first.length;
  for (var k = 1; k < names.length && length > 0; k++) {
    final name = names[k], end = math.min(length, name.length);
    var i = 0;
    while (i < end && first.codeUnitAt(i) == name.codeUnitAt(i)) {
      i++;
    }
    length = i;
  }
  return length;
}

/// Dictionary keys shared across documents, numbered in insertion order.
final class SharedKeys {
  static const maxKeys = 2048;
  static const maxKeyLength = 16;
  final List<String> _keys;
  final Map<String, int> _numbers;

  int get length => _keys.length;
  bool get isEmpty => _keys.isEmpty;
  Iterable<String> get keys => UnmodifiableListView(_keys);
  static final _ineligible = RegExp(r'[^a-zA-Z0-9_-]');
  static bool isEligible(String key) =>
      key.isNotEmpty &&
      key.length <= maxKeyLength &&
      !_ineligible.hasMatch(key);
  int? number(String key) => _numbers[key];
  String? key(int number) =>
      number >= 0 && number < length ? _keys[number] : null;

  int? add(String key) {
    final existing = _numbers[key];
    if (existing != null) return existing;
    if (length == maxKeys || !isEligible(key)) return null;
    final number = length;
    _keys.add(key);
    return _numbers[key] = number;
  }

  void truncate(int length) {
    RangeError.checkNotNegative(length, 'length');
    while (_keys.length > length) {
      _numbers.remove(_keys.removeLast());
    }
  }

  Uint8List toState() => encode(_keys);
  SharedKeys()
      : _keys = [],
        _numbers = {};
  SharedKeys._snapshot(SharedKeys source)
      : _keys = List.unmodifiable(source._keys),
        _numbers = Map.unmodifiable(source._numbers);
  factory SharedKeys.fromState(Uint8List state) {
    final root = Doc(state).root;
    final values = root.asArray;
    if (values == null)
      _malformed('Expected a shared key array', root.position);
    final table = SharedKeys();
    for (final item in values) {
      final name = item.asString;
      if (name == null ||
          table.number(name) != null ||
          table.add(name) == null) {
        _malformed('Invalid shared key table', root.position);
      }
    }
    return table;
  }
  @override
  bool operator ==(Object other) =>
      other is SharedKeys && _equal(_keys, other._keys);
  @override
  int get hashCode => Object.hashAll(_keys);
}

extension ExtensionName on ExtKind {
  String get wireName => switch (this) {
        ExtKind.bigDecimal => 'bigdecimal',
        ExtKind.recordId => 'record',
        _ => name
      };
}

/// The wire name of an extension number, or null for an unknown number.
String? extensionName(int id) =>
    id >= 0 && id < ExtKind.values.length ? ExtKind.values[id].wireName : null;
