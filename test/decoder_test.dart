import 'dart:typed_data';

import 'package:fleece/fleece.dart';
import 'package:test/test.dart';

import 'limits_test.dart' show pointer, refused;

// Several array slots reference the same physical root in the original body.
Uint8List aliases(Object value, int count) {
  final bytes = encode(value);
  final target = Doc(bytes).root.position;
  final body = bytes.toList();
  final start = body.length;
  body.addAll([0x68 | (count >> 8), count & 255]);
  for (var i = 0; i < count; i++) {
    pointer(body, target, true);
  }
  pointer(body, start, true);
  body.addAll([0x80, 2]);
  return Uint8List.fromList(body);
}

void main() {
  test('repeated references produce independent owned lists, maps and data',
      () {
    final bytes = aliases({
      'a': [Uint8List.fromList(List.generate(32, (i) => i))]
    }, 2);
    final values = Doc(bytes).root.read() as List;
    final a = values[0] as Map, b = values[1] as Map;
    (a['a'][0] as Uint8List)[0] = 255;
    (a['a'] as List).add(3);
    a['extra'] = true;
    bytes.fillRange(0, bytes.length, 0);
    expect(b.keys, ['a']);
    expect(b['a'], [List.generate(32, (i) => i)]);
  });

  test('a collection pointing to itself reports a cycle within a tiny budget',
      () {
    final root =
        Doc.trusted(Uint8List.fromList([0x60, 1, 0x80, 1, 0x80, 2])).root;
    expect(root.read, refused(DecodeErrorCode.tooDeep));
  });

  test(
      'strict decoding checks shadowed parent fields when materializing a delta',
      () {
    // The child replaces 'a'. The base illegally stores an undefined value.
    final base = Uint8List.fromList([0x70, 1, 0x41, 97, 0x3c, 0]);
    final delta =
        Uint8List.fromList([0x70, 2, 8, 0, 0xc0, 5, 0x41, 97, 0, 7, 0x80, 5]);
    expect(Doc.trusted(delta, base: base).root.read(), {'a': 7});
    expect(() => decode(delta, base: base), refused(DecodeErrorCode.undefined));
    base[4] = 0x30;
    expect(decode(delta, base: base), {'a': 7});
  });

  test('a root extension may use the entire collection budget', () {
    // Ten physical words. The set payload expands to exactly ten values.
    // The root marker is added only when a parent counts that collection.
    final bytes = Uint8List.fromList([
      0,
      0,
      0x60,
      2,
      0,
      0,
      0,
      0,
      0x31,
      ExtKind.set.index,
      0x60,
      3,
      0x80,
      5,
      0x80,
      6,
      0x80,
      7,
      0x80,
      5,
    ]);
    final expected = FleeceSet([
      [0, 0],
      [0, 0],
      [0, 0]
    ]);
    expect(Doc(bytes).root.read(), expected);
    expect(decode(bytes), expected);
  });

  test('extension aliases spend both the node and byte budgets on every use',
      () {
    for (final (bytes, error) in [
      (aliases(FleeceSet([1, 2, 3]), 256), DecodeErrorCode.tooManyValues),
      (
        aliases(FleeceVector.i8(List.filled(2048, 1)), 256),
        DecodeErrorCode.tooManyBytes
      ),
    ]) {
      expect(Doc.trusted(bytes).root.read, refused(error));
      expect(() => decode(bytes), refused(error));
    }
  });

  test('extension collections at the exact depth limit can be materialized',
      () {
    Object value = FleeceText.plain('x');
    for (var i = 1; i < maxDepth; i++) {
      value = FleeceSet([value]);
    }
    final bytes = encode(value);
    expect(encode(Doc(bytes).root.read()), bytes);
    // Add another collection around that value without using the depth-limited encoder.
    final tooDeep = aliases(value, 1);
    expect(Doc.trusted(tooDeep).root.read, refused(DecodeErrorCode.tooDeep));
    expect(() => decode(tooDeep), refused(DecodeErrorCode.tooDeep));
  });

  test(
      'a root or arbitrary reference reads the current bytes with its own budget',
      () {
    final bytes = encode([
      [true],
      'other'
    ]);
    final doc = Doc(bytes);
    final child = doc.root.asArray![0];
    bytes[child.position] = 0x31;
    bytes[child.position + 1] = 255;
    expect(child.read, refused(DecodeErrorCode.unknownExt));
    expect(doc.root.read, refused(DecodeErrorCode.unknownExt));
  });

  test(
      'strict decode agrees with validation and logical read after byte mutations',
      () {
    final keys = SharedKeys()
      ..add('id')
      ..add('mark');
    final first = encode({
      'id': FleeceRecordId(
          'row',
          FleeceRange(
              const FleeceBound.included(3), const FleeceBound.unbounded())),
      'with spaces': [
        FleeceGeometry.collection([
          FleeceGeometry.point(-0.0, 5),
          FleeceGeometry.line([(1, 2), (3, 4)])
        ]),
        FleeceVector.bits(Uint8List.fromList([0xed]), 5),
        FleeceText.fromRuns([
          ('é', {'mark': 1}),
          (' more', null)
        ]),
        FleeceInt.u64((BigInt.one << 64) - BigInt.one),
      ]
    }, sharedKeys: keys);
    final second = encode([
      Uint8List.fromList([1]),
      const FleeceNone(),
      false,
      'a'
    ]);
    for (final source in [first, second]) {
      for (var i = 0; i < source.length; i++) {
        for (final mask in [1, 8, 64, 128]) {
          final bytes = Uint8List.fromList(source)..[i] ^= mask;
          Object outcome(Object? Function() read) {
            try {
              return encode(read());
            } on DecodeError catch (e) {
              return (e.code, e.position, e.kind, e.key);
            }
          }

          expect(outcome(() => decode(bytes, sharedKeys: keys)),
              outcome(() => Doc(bytes, sharedKeys: keys).root.read()),
              reason: 'byte $i xor $mask');
        }
      }
    }
  });

  test('dictionary key ordering can be reused across changing map shapes', () {
    final values = [
      {'z': 1, 'x': 2},
      {'A': 3, 'b': 4},
      {'b': 5, 'A': 6},
      {'a': 7, 'b': 8},
    ];
    final encoded = encode(values);
    final e = Encoder()..beginArray();
    for (final fields in values) {
      e.beginDict();
      for (final key in fields.keys.toList()..sort()) {
        e.writeKey(key);
        e.writeInt(fields[key]!);
      }
      e.endDict();
    }
    expect(encoded, (e..endArray()).finish());
  });
}
