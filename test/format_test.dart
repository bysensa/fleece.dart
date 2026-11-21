import 'dart:typed_data';

import 'package:fleece/fleece.dart';
import 'package:test/test.dart';

Uint8List hex(String s) => Uint8List.fromList(s
    .trim()
    .split(RegExp(r'\s+'))
    .map((v) => int.parse(v, radix: 16))
    .toList());

void main() {
  // Frozen in the Rust crate's tests/golden.rs at format version 1.
  final frozen = <(Object?, String)>[
    (null, '30 00'),
    (false, '34 00'),
    (true, '38 00'),
    (0, '00 00'),
    (-1, '0f ff'),
    (2047, '07 ff'),
    (2048, '11 00 08 00 80 02'),
    (-(BigInt.one << 63), '17 00 00 00 00 00 00 00 80 00 80 05'),
    (1.5, '24 00 00 00 c0 3f 80 03'),
    (0.1, '28 00 9a 99 99 99 99 99 b9 3f 80 05'),
    (FleeceFloat32(1.5), '20 00 00 00 c0 3f 80 03'),
    ('', '40 00'),
    ('a', '41 61'),
    ('abc', '43 61 62 63 80 02'),
    (
      'abcdefghijklmno',
      '4f 0f 61 62 63 64 65 66 67 68 69 6a 6b 6c 6d 6e 6f 00 80 09'
    ),
    (hex('01 02 03'), '53 01 02 03 80 02'),
    (<Object?>[], '60 00'),
    ([1, 'abc'], '43 61 62 63 60 02 00 01 80 04 80 03'),
    (<String, Object?>{}, '70 00'),
    ({'a': 1}, '70 01 41 61 00 01 80 03'),
    (const FleeceNone(), '31 00'),
    (FleeceInt.i8(-1), '31 01 0f ff 80 02'),
    (FleeceInt.u8(7), '31 02 00 07 80 02'),
    (FleeceInt.i16(-300), '31 03 0e d4 80 02'),
    (FleeceInt.u16(65535), '31 04 12 ff ff 00 80 03'),
    (FleeceInt.i32(-2147483648), '31 05 13 00 00 00 80 00 80 04'),
    (FleeceInt.u32(4294967295), '31 06 14 ff ff ff ff 00 80 04'),
    (
      FleeceInt.u64((BigInt.one << 64) - BigInt.one),
      '31 07 1f ff ff ff ff ff ff ff ff 00 80 06'
    ),
    (FleeceFloat16.fromBits(0x3e00), '31 08 11 00 3e 00 80 03'),
    (
      FleeceDecimal(BigInt.from(150), 2),
      '31 09 5f 10 00 00 02 00 96 00 00 00 00 00 00 00 00 00 00 00 80 0a'
    ),
    (
      FleeceBigDecimal(BigInt.from(-150), 2),
      '52 6a ff 00 31 0a 60 02 00 02 80 05 80 04'
    ),
    (
      FleeceSeconds.duration(1, 500000000),
      '31 0b 5c 01 00 00 00 00 00 00 00 00 65 cd 1d 00 80 08'
    ),
    (
      FleeceSeconds.datetime(-1, 0),
      '31 0c 5c ff ff ff ff ff ff ff ff 00 00 00 00 00 80 08'
    ),
    (FleeceDate(20772), '31 0e 11 24 51 00 80 03'),
    (FleeceTime(1), '31 0f 00 01 80 02'),
    (
      FleeceSeconds.timestamp(0, 1),
      '31 10 5c 00 00 00 00 00 00 00 00 01 00 00 00 00 80 08'
    ),
    (
      FleeceInterval(1, -1, 2),
      '31 11 5f 10 01 00 00 00 ff ff ff ff 02 00 00 00 00 00 00 00 80 0a'
    ),
    (
      FleeceUuid(Uint8List.fromList(List.generate(16, (i) => i + 1))),
      '31 0d 5f 10 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f 10 80 0a'
    ),
    (const FleeceTable('t'), '31 12 41 74 80 02'),
    (
      FleeceRecordId('user', 7),
      '44 75 73 65 72 00 31 13 60 02 80 05 00 07 80 04'
    ),
    (const FleeceFile('b', '/k'), '42 2f 6b 00 31 14 60 02 41 62 80 05 80 04'),
    (
      const FleeceRange(FleeceBound.included(1), FleeceBound.unbounded()),
      '31 15 60 03 00 01 00 01 30 00 80 05'
    ),
    (const FleeceRegex('a+'), '31 16 42 61 2b 00 80 03'),
    (FleeceSet([1]), '31 17 60 01 00 01 80 03'),
    (
      FleeceGeometry.point(1, 2),
      '5f 10 00 00 00 00 00 00 f0 3f 00 00 00 00 00 00 00 40 31 18 60 02 00 00 80 0c 80 04'
    ),
    (FleeceVector.f32([1, -2]), '31 19 59 00 00 00 80 3f 00 00 00 c0 80 06'),
    (FleeceVector.f64([1]), '31 19 59 01 00 00 00 00 00 00 f0 3f 80 06'),
    (FleeceVector.f16Bits([0x3e00]), '31 19 53 02 00 3e 80 03'),
    (FleeceVector.i8([-1, 127]), '31 19 53 03 ff 7f 80 03'),
    (FleeceVector.bits(hex('a1'), 8), '31 19 53 04 00 a1 80 03'),
    (FleeceVector.bits(hex('a1 03'), 10), '31 19 54 04 06 a1 03 00 80 04'),
    (FleeceVector.f32([]), '31 19 51 00 80 02'),
    (FleeceText.plain(''), '31 1a 60 01 40 00 80 03'),
    (FleeceText.plain('Milou'), '45 4d 69 6c 6f 75 31 1a 60 01 80 05 80 03'),
    (
      FleeceText.fromRuns([
        ('Hello ', null),
        ('world', {'bold': true})
      ]),
      '4b 48 65 6c 6c 6f 20 77 6f 72 6c 64 53 06 05 00 44 62 6f 6c 64 00 70 01 80 04 38 00 31 1a 60 03 80 10 80 0b 80 07 80 05'
    ),
    (
      FleeceText.fromRuns([
        ('a', {'bold': true}),
        ('b', null),
        ('c', {'bold': true}),
        ('d', {'link': 'x'})
      ]),
      '44 61 62 63 64 00 59 00 01 00 01 01 00 00 01 01 44 62 6f 6c 64 00 70 01 80 04 38 00 44 6c 69 6e 6b 00 70 01 80 04 41 78 31 1a 60 04 80 16 80 14 80 0d 80 08 80 06'
    ),
  ];

  for (final (value, bytes) in frozen) {
    test('v1 $bytes', () {
      final expected = hex(bytes);
      expect(encode(value), expected);
      final read = decode(expected);
      if (value is BigInt) {
        expect(read is int ? BigInt.from(read) : read, value);
      } else if (value is double && read is FleeceFloat64) {
        expect(read.value, value);
      } else {
        expect(read, value);
      }
      expect(encode(read), expected);
    });
  }

  test('Couchbase example written in streaming order', () {
    final e = Encoder()
      ..beginDict()
      ..writeKey('hello')
      ..writeString('world!')
      ..writeKey('time')
      ..writeUint(1234567890)
      ..writeKey('float')
      ..writeF64(0.01234)
      ..writeKey('boolean')
      ..writeBool(true)
      ..writeKey('otherbool')
      ..writeBool(false)
      ..writeKey('null')
      ..writeNull()
      ..writeKey('obj')
      ..writeValue({'what': 'that'})
      ..writeKey('arr')
      ..writeValue([1, 2, 3])
      ..endDict();
    final expected = hex('45 68 65 6c 6c 6f 46 77 6f 72 6c 64 21 00 44 74 '
        '69 6d 65 00 1b d2 02 96 49 00 45 66 6c 6f 61 74 '
        '28 00 f6 0b 76 c3 b6 45 89 3f 47 62 6f 6f 6c 65 '
        '61 6e 49 6f 74 68 65 72 62 6f 6f 6c 44 6e 75 6c '
        '6c 00 43 6f 62 6a 44 77 68 61 74 00 44 74 68 61 '
        '74 00 70 01 80 07 80 05 43 61 72 72 60 03 00 01 '
        '00 02 00 03 70 08 80 07 80 06 80 20 38 00 80 2a '
        '80 28 80 39 80 37 80 1d 30 00 80 1c 80 15 80 26 '
        '34 00 80 3a 80 38 80 11');
    expect(e.finish(), expected);
    final root = Doc(expected).root;
    expect(root.position, 0x64);
    expect(root.asDict!.length, 8);
    expect(root.asDict!['hello']!.asString, 'world!');
    expect(root.asDict!['boolean']!.asBool, isTrue);
    expect(root.asDict!['null']!.isNull, isTrue);
    expect(root.asDict!['obj']!.asDict!['what']!.asString, 'that');
    expect(KeyPath.parse(r'$.arr[-1]').eval(root)?.asInt, 3);
    expect(KeyPath.parse('arr[3]').eval(root), isNull);
    expect(KeyPath.parse('hello.x').eval(root), isNull);
    final listing = dump(Doc(expected));
    expect(listing,
        contains('0064: Dict[8]\n0066:   &0058\n'.replaceAll('\n', '\n')));
    expect(listing, contains('0014: 1234567890\n'));
    expect(listing, endsWith('0086: &0064\n'));
    expect(encode({'foo': 123}), hex('43 66 6f 6f 70 01 80 03 00 7b 80 03'));
    expect(root.asDict!['arr']!.asArray![2].asInt, 3);
    expect(root.asDict!['time']!.asInt, 1234567890);
    expect(decode(hex('78 01 43 66 6f 6f 00 7b 00 00 80 05')), {'foo': 123});
  });

  test('shared key state, rollback and fixed tables', () {
    final keys = SharedKeys()
      ..add('last')
      ..add('first');
    final values = {'\ufeffx': 1, 'first': 2, 'last': 3};
    final bytes = encode(values, sharedKeys: keys);
    expect(() => decode(bytes), throwsFormatException);
    expect(decode(bytes, sharedKeys: SharedKeys.fromState(keys.toState())),
        values);
    expect(compact(Doc(bytes, sharedKeys: keys)), bytes);
    keys.add('later');
    keys.truncate(2);
    final fixed = Encoder(sharedKeys: keys, fixedSharedKeys: true)
      ..writeValue({'later': 4});
    expect(decode(fixed.finish()), {'later': 4});
    expect(keys.number('later'), isNull);
  });

  test('appended and external deltas, deletion and compaction', () {
    final old = {for (var i = 0; i < 24; i++) 'field-$i': 'value number $i'};
    final base = encode(old);
    final next = {...old, 'field-1': 'new'}..remove('field-2');
    final appended = appendDelta(base, next);
    final together = Doc(Uint8List.fromList([...base, ...appended]));
    final delta = appendDelta(base, next, external: true);
    final external = Doc(delta, base: base);
    expect(appended.length, lessThan(base.length));
    expect(() => Doc(delta), throwsFormatException);
    for (final doc in [together, external]) {
      expect(doc.root.read(), next);
      expect(doc.root.asDict!['field-2'], isNull);
      expect(compact(doc), encode(next));
    }
  });

  test('invalid documents fail before a read', () {
    for (final bytes in [
      '00',
      '80 05',
      '80 00',
      '45 68 80 01',
      '42 ff fe 00 80 02',
      '70 02 41 62 00 01 41 61 00 02 80 05',
      '70 01 30 00 00 01 80 03',
      '31 c8 00 01 80 02',
      '31 0d',
      '31 0d 00 01 80 02',
      '3c 00',
      '00 01 60 01 c0 02 80 02',
      '60 01 80 01 80 02'
    ]) {
      expect(() => Doc(hex(bytes)), throwsFormatException, reason: bytes);
    }
    expect(() => Doc(Uint8List(0)), throwsFormatException);
  });

  test('IEEE 754 widths, signed zero and NaN payloads', () {
    final cases = [
      (FleeceFloat64(-0.0), '24 00 00 00 00 80 80 03'),
      (FleeceFloat32.fromBits(0xffa12345), '20 00 45 23 a1 ff 80 03'),
      (
        FleeceFloat64.fromBits(BigInt.parse('7ff8000000000000', radix: 16)),
        '24 00 00 00 c0 7f 80 03'
      ),
      (
        FleeceFloat64.fromBits(BigInt.parse('7ff0000000000001', radix: 16)),
        '28 00 01 00 00 00 00 00 f0 7f 80 05'
      ),
      (
        FleeceFloat64.fromBits(BigInt.parse('fff8000000000001', radix: 16)),
        '28 00 01 00 00 00 00 00 f8 ff 80 05'
      ),
    ];
    for (final (value, text) in cases) {
      final bytes = hex(text);
      expect(encode(value), bytes);
      expect(encode(decode(bytes)), bytes);
    }
    final coords = hex('01 00 00 00 00 00 f0 7f 01 00 00 00 00 00 f8 ff');
    final point = (Encoder()
          ..beginExt(ExtKind.geometry)
          ..writeValue([0, coords]))
        .finish();
    expect(encode(decode(point)), point);
  });

  test('typed reads, including unaligned views and UTF-8 mark ranges', () {
    final text = FleeceText.fromRuns([
      ('\ufeff', null),
      ('🙂', {'bold': true}),
      ('é', {'bold': true}),
      ('!', null)
    ]);
    final bytes = encode({
      'text': text,
      'geom': FleeceGeometry.point(1.25, -2.5),
      'half': FleeceVector.f16Bits([0x3e00, 1, 0x8000]),
    });
    final backing = Uint8List(bytes.length + 3)..setAll(1, bytes);
    final root =
        Doc(Uint8List.sublistView(backing, 1, 1 + bytes.length)).root.asDict!;
    final read = root['text']!.read() as FleeceText;
    expect(read.text, '\ufeff🙂é!');
    expect(read.marks.single.start, 3);
    expect(read.marks.single.end, 9);
    expect(read.runs.map((r) => r.$1), ['\ufeff', '🙂é', '!']);
    final point = root['geom']!.read() as FleeceGeometry<FleecePoint>;
    expect(point.coordinates, (1.25, -2.5));
    final vector = root['half']!.asVector!;
    expect(vector[0], 1.5);
    expect(vector[1], 1.0 / 16777216);
    expect(vector[2].isNegative, isTrue);
  });

  test('repeated deltas flatten inheritance and preserve shared keys', () {
    final keys = SharedKeys();
    final fields = <String, Object?>{
      for (var i = 0; i < 32; i++) 'field$i': 'value-$i'
    };
    var bytes = encode(fields, sharedKeys: keys);
    for (var round = 0; round < 12; round++) {
      fields['field3'] = round;
      fields['added later'] = [round];
      final delta = appendDelta(bytes, fields, sharedKeys: keys);
      bytes = Uint8List.fromList([...bytes, ...delta]);
      final doc = Doc(bytes, sharedKeys: keys);
      expect(doc.root.asDict!['field3']!.asInt, round);
      expect(decode(compact(doc), sharedKeys: keys), fields);
    }
  });

  test('numbered and literal keys resolve through the same growing table', () {
    final keys = SharedKeys();
    final old = {for (var i = 0; i < 20; i++) 'field$i': i};
    final base = encode(old);
    keys.add('field0');
    final next = {...old, 'field0': -1};
    final delta = appendDelta(base, next, external: true, sharedKeys: keys);
    final doc = Doc(delta, base: base, sharedKeys: keys);
    expect(doc.root.asDict!.length, old.length);
    expect(doc.root.asDict!['field0']!.asInt, -1);
    expect(decode(compact(doc), sharedKeys: keys), next);
  });

  test('encoder state and bounds', () {
    final e = Encoder()..beginDict();
    expect(() => e.writeInt(2), throwsStateError);
    e.writeKey('k');
    expect(e.endDict, throwsStateError);
    e.writeValue(2);
    e.endDict();
    expect(() => e.writeInt(1), throwsStateError);
    expect(decode(e.finish()), {'k': 2});
    expect(Encoder().finish, throwsStateError);
    expect(() => encode(String.fromCharCode(0xd800)), throwsArgumentError);
    expect(() => encode(BigInt.one << 63), throwsArgumentError);
    expect(() => FleeceInt.u64(BigInt.one << 64), throwsArgumentError);
    Object? v = 1;
    for (var i = 0; i < maxDepth; i++) {
      v = [v];
    }
    expect(encode(decode(encode(v))), encode(v));
    expect(() => encode([v]), throwsStateError);
    expect(
        () => FleeceText.withMarks('é', [
              TextMark(1, 2, {'a': 1})
            ]),
        throwsArgumentError);
  });
}
