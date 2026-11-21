import 'dart:math';
import 'dart:typed_data';
import 'package:fleece/fleece.dart';
import 'package:fleece/src/varint.dart';
import 'package:test/test.dart';

void main() {
  test('the format has a version and numeric extension identifiers', () {
    expect(formatVersion, 1);
    expect(
        ExtKind.values.map((k) => k.wireName),
        'none i8 u8 i16 u16 i32 u32 u64 f16 decimal bigdecimal duration datetime uuid date time timestamp interval table record file range regex set geometry vector text'
            .split(' '));
  });
  test('u64 varints take the fewest bytes and round trip', () {
    for (final n in [0, 1, 127, 128, 300, 16383, 16384, 4294967295]
        .map(BigInt.from)
        .followedBy([(BigInt.one << 64) - BigInt.one])) {
      final b = Uint8List.fromList(encodeVarint(n));
      expect(b.length, max(1, (n.bitLength + 6) ~/ 7));
      expect(decodeVarint(b, 0), (n, b.length));
    }
    expect(() => decodeVarint(Uint8List.fromList(List.filled(11, 128)), 0),
        throwsFormatException);
  });
  test('signed and unsigned integers use the fewest wire bytes', () {
    for (final (n, b) in [
      (123, [0, 123]),
      (-1, [15, 255]),
      (-2048, [8, 0]),
      (2048, [17, 0, 8, 0]),
      (-2049, [17, 255, 247, 0])
    ]) {
      final data = encode(n);
      expect(data.take(b.length), b);
    }
    expect(encode(-(BigInt.one << 63)).length, 12);
    expect((Encoder()..writeUint(1234567890)).finish().take(6),
        [27, 210, 2, 150, 73, 0]);
  });
  test('decimal text and byte scale are exact', () {
    for (final s in [
      '0',
      '-0.00',
      '-1.50',
      '0.001',
      '79228162514264337593543950335',
      '12.3400'
    ]) {
      final n = FleeceDecimal.parse(s);
      expect(n.toString(), s);
      expect(FleeceDecimal.fromBytes(n.toBytes()), n);
    }
    for (final s in [
      '',
      '-',
      '1.',
      '.5',
      '1e3',
      '79228162514264337593543950336'
    ]) expect(() => FleeceDecimal.parse(s), throwsFormatException);
  });
  test('big decimal text and minimal signed coefficient bytes', () {
    for (final s in [
      '0',
      '0.00',
      '-1.50',
      '127',
      '128',
      '-128',
      '-129',
      '4294967296',
      '123456789012345678901234567890.000001',
      '-0.000000000000000000000000000000001',
      '1000000000000000000'
    ]) expect(FleeceBigDecimal.parse(s).toString(), s);
    for (final e in {
      '0': [0],
      '127': [127],
      '128': [128, 0],
      '-128': [128],
      '-129': [127, 255],
      '-1.50': [106, 255],
      '-0': [0]
    }.entries) expect(FleeceBigDecimal.parse(e.key).coefficientBytes, e.value);
    expect(
        FleeceBigDecimal.parse('1.50'), isNot(FleeceBigDecimal.parse('1.5')));
    expect(
        FleeceBigDecimal.fromBytes(Uint8List.fromList([127, 0, 0]), 2)
            .coefficientBytes,
        [127]);
    expect(FleeceBigDecimal.fromBytes(Uint8List(0), 0).toString(), '0');
    expect(
        () => FleeceBigDecimal.fromBytes(
            Uint8List(1), FleeceBigDecimal.maxScale + 1),
        throwsRangeError);
    expect(() => FleeceBigDecimal.parse('1e3'), throwsFormatException);
  });
  test('UUID text uses fixed hexadecimal groups', () {
    const s = '018f4a2b-7c3d-7e1f-9a0b-1c2d3e4f5a6b';
    expect(FleeceUuid.parse(s.toUpperCase()).toString(), s);
    for (final x in [s.replaceAll('-', ''), s.replaceRange(34, 35, '+')])
      expect(() => FleeceUuid.parse(x), throwsFormatException);
  });
  test('f16 converts exactly and rejects inexact doubles', () {
    for (var i = 0; i <= 65535; i++) {
      final d = FleeceFloat16.fromBits(i).value;
      if (!d.isNaN && FleeceFloat16.fromF64(d)?.bits != i) fail('half $i');
    }
    expect(FleeceFloat16.fromBits(1).value, pow(2, -24));
    expect(FleeceFloat16.fromBits(0x3e00).value, 1.5);
    expect(FleeceFloat16.fromF64(0.1), isNull);
    expect(FleeceFloat16.fromF64(65536), isNull);
  });
  test('standard base64 padding and invalid encodings', () {
    for (final (b, s) in [
      ([], ''),
      ([102], 'Zg=='),
      ([102, 111], 'Zm8='),
      ([102, 111, 111], 'Zm9v'),
      ([102, 111, 111, 98], 'Zm9vYg=='),
      ([222, 173, 190, 239], '3q2+7w==')
    ]) {
      final bytes = Uint8List.fromList(b.cast<int>());
      expect(toJson(bytes), {r'$bytes': s});
      expect(fromJson({r'$bytes': s}), bytes);
    }
    for (final s in ['Zg=', 'Zg==Zg==', 'Z===', 'Zm9*'])
      expect(() => fromJson({r'$bytes': s}), throwsFormatException);
  });
  test('proleptic Gregorian dates include year zero, signed and extended years',
      () {
    for (final e in {
      0: '1970-01-01',
      -1: '1969-12-31',
      20772: '2026-11-15',
      11016: '2000-02-29',
      -719528: '0000-01-01',
      -719529: '-0001-12-31',
      2932897: '+10000-01-01'
    }.entries) {
      final v = FleeceDate(e.key);
      expect(toJson(v), {r'$date': e.value});
      expect(fromJson(toJson(v)), v);
    }
    for (final s in [
      '2026-02-30',
      '2026-13-01',
      '2026-1-01',
      '26-01-01',
      '2026-01-01-',
      ''
    ]) expect(() => fromJson({r'$date': s}), throwsFormatException);
  });
  test('instants and clocks preserve nanoseconds on both sides of epoch', () {
    expect(toJson(FleeceSeconds.datetime(1794765600, 0)),
        {r'$datetime': '2026-11-15T18:00:00Z'});
    final v = FleeceSeconds.timestamp(-1, 500000000);
    expect(toJson(v), {r'$timestamp': '1969-12-31T23:59:59.5'});
    expect(fromJson(toJson(v)), v);
    expect(fromJson({r'$time': '24:00:00'}), FleeceTime(FleeceTime.maxNanos));
    expect(fromJson({r'$time': '00:00:00.000000001'}), FleeceTime(1));
    expect(() => fromJson({r'$timestamp': '2026-11-15T24:00:00'}),
        throwsFormatException);
    for (final s in [
      '24:00:01',
      '12:60:00',
      '12:00',
      '12:00:00.',
      '12:00:00.0000000001'
    ]) expect(() => fromJson({r'$time': s}), throwsFormatException);
  });
  test('typed values read back with escaped dollar keys and exact JSON numbers',
      () {
    final input = {
      'name': 'Milou',
      'id': {r'$uuid': '018f4a2b-7c3d-7e1f-9a0b-1c2d3e4f5a6b'},
      'created': {r'$datetime': '2026-11-15T18:00:00Z'},
      'avatar': {r'$bytes': '3q2+7w=='},
      'small': {r'$u8': 7},
      r'$$price': 1.5
    };
    final v = fromJson(input) as Map;
    expect(v['small'], FleeceInt.u8(7));
    expect(v[r'$price'], 1.5);
    expect(toJson(v), input);
    for (final (name, val, code) in [
      ('nope', 1, JsonErrorCode.unknownType),
      ('u8', 256, JsonErrorCode.badValue),
      ('f16', 0.1, JsonErrorCode.badValue),
      ('f32', 0.1, JsonErrorCode.badValue)
    ]) {
      expect(() => fromJson({r'$' + name: val}),
          throwsA(isA<JsonError>().having((e) => e.code, 'code', code)));
    }
    const s =
        r'[-9223372036854775808,9007199254740993,{"$u64":18446744073709551615},1.0,-0.0]';
    expect(fleeceToJson(jsonToFleece(s)), s);
    expect(jsonToFleece('-0'), encode(const FleeceFloat64(-0.0)));
    for (final bad in [
      '{1:0}',
      '[01]',
      '[1,]',
      '{"a":}',
      r'"\uD800"',
      '1e9999'
    ])
      expect(
          () => jsonToFleece(bad),
          throwsA(isA<JsonError>()
              .having((e) => e.code, 'code', JsonErrorCode.syntax)));
  });
  test('Couchbase string delta applies byte operations and checks UTF-8', () {
    const old = 'The fog comes in on little cat feet';
    expect(apply(old, ['4=1-1+d|30=', 0, 2]),
        'The dog comes in on little cat feet');
    expect(() => apply(old, ['4=', 0, 2]), throwsA(isA<DeltaError>()));
    expect(apply('é', ['2-4+🐶|', 0, 2]), '🐶');
    expect(() => apply('é', ['1=1-', 0, 2]), throwsA(isA<DeltaError>()));
    expect(diff('a', null), isNotNull);
    expect(apply('a', diff('a', null)), isNull);
    expect(diff(null, null), isNull);
    expect(
        apply([
          1,
          2,
          3
        ], {
          '1-': ['tail']
        }),
        [1, 'tail']);
    expect(diff({}, [])!.value, [[]]);
  });
}
