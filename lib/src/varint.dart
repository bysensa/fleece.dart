import 'dart:typed_data';

/// An unsigned 64-bit Fleece varint. Header varints follow Rust's u64
/// shift semantics for the final digit. Text mark varints must be minimal.
List<int> encodeVarint(BigInt n) {
  if (n.isNegative || n.bitLength > 64) throw RangeError('Varint exceeds u64');
  final bytes = <int>[];
  while (n >= BigInt.from(128)) {
    bytes.add(n.toUnsigned(7).toInt() | 128);
    n >>= 7;
  }
  return bytes..add(n.toInt());
}

(BigInt, int) decodeVarint(Uint8List bytes, int start, {bool minimal = false}) {
  var n = BigInt.zero;
  for (var i = 0; i < 10 && start + i < bytes.length; i++) {
    final b = bytes[start + i], digit = b & 127;
    if (i == 9 && minimal && digit > 1) break;
    n |= BigInt.from(i == 9 ? digit & 1 : digit) << (7 * i);
    if (b < 128) {
      if (minimal && i > 0 && digit == 0) break;
      return (n, i + 1);
    }
  }
  throw FormatException('Invalid Fleece varint', null, start);
}
