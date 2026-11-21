import 'dart:typed_data';
import 'package:fleece/fleece.dart';
import 'package:test/test.dart';

final user = <String, Object?>{
  'name': 'Milou',
  'age': FleeceInt.u8(9),
  'id': FleeceUuid(Uint8List(16)..fillRange(0, 16, 7)),
  'tags': ['dog', 'white'],
  'address': {'city': 'Brussels', 'zip': '1000'}
};
final path = KeyPath.parse;
void main() {
  test('kind limits cover u64 and repeated named checks share results', () {
    final k = Kind.array(Kind.integer, (BigInt.one << 64) - BigInt.one);
    expect(k.maxItems, (BigInt.one << 64) - BigInt.one);
    expect(k.conforms(Doc(encode([1, 2])).root), isTrue);
    expect(
        Kind.array(Kind.literal(const KindLiteral.string('x')), 8),
        Kind.array(
            Kind.literal(const KindLiteral.string('x')), BigInt.from(8)));
  });
  test(
      'key paths parse and evaluate escapes, root, signed indices and dollar names',
      () {
    final root = Doc(encode({
      r'$dollar': 1,
      'a.b': {r'[c\': 2},
      'foo': {
        'bar': [
          [1],
          [2],
          [
            3,
            4,
            {'baz': 7}
          ]
        ]
      }
    })).root;
    for (final s in ['', r'$', r'$.'])
      expect(path(s).eval(root)?.position, root.position);
    expect(path(r'a\.b.\[c\\').eval(root)?.asInt, 2);
    expect(path(r'$dollar').eval(root)?.asInt, 1);
    expect(path(r'$.foo.bar[2][-1].baz').eval(root)?.asInt, 7);
    expect(
        path(r'$[0].a')
            .eval(Doc(encode([
              {'a': 1}
            ])).root)
            ?.asInt,
        1);
    for (final p in ['foo[-1]', 'foo.bar[3]', 'foo.bar[-9223372036854775808]'])
      expect(path(p).eval(root), isNull);
  });
  test('malformed key paths report UTF-8 byte offsets', () {
    for (final e in {
      '.a': 0,
      'a..b': 2,
      'a.': 2,
      'a[1': 1,
      'a[x]': 1,
      'a[1]b': 4,
      'a[1].': 5,
      'a\\': 1,
      'é[1x]': 2,
      'a.[0]': 2,
      'a[9223372036854775808]': 1
    }.entries) {
      expect(() => path(e.key),
          throwsA(isA<KeyPathError>().having((e) => e.at, 'at', e.value)));
    }
  });
  test('a document is changed by paths', () {
    final d = Doc(encode(user)), patch = Patch();
    expect(patch.isEmpty, isTrue);
    patch
      ..set(path('age'), FleeceInt.u8(10))
      ..set(path('address.city'), 'Moulinsart')
      ..remove(path('address.zip'))
      ..remove(path('tags[0]'))
      ..set(path('tags[2]'), 'small')
      ..set(path('owner.name'), 'Tintin')
      ..remove(path('missing'));
    expect(decode(update(d, patch)), {
      ...user,
      'age': FleeceInt.u8(10),
      'address': {'city': 'Moulinsart'},
      'tags': ['white', 'small'],
      'owner': {'name': 'Tintin'}
    });
    expect(update(d, Patch()), d.bytes);
    expect(decode(update(d, Patch()..set(path(''), null))), isNull);
    expect(
        decode(update(
            d,
            Patch()
              ..remove(path('age'))
              ..set(path('age'), 1))),
        {...user, 'age': 1});
    expect(
        decode(update(
            d,
            Patch()
              ..set(path('tags'), 0)
              ..set(path('tags[-1]'), 'black'))),
        {
          ...user,
          'tags': ['dog', 'black']
        });
    expect(update(d, Patch()..set(path('age'), FleeceInt.u8(10))).length,
        encode({...user, 'age': FleeceInt.u8(10)}).length);
  });
  test('a path that does not fit is refused', () {
    final doc = Doc(encode(user));
    for (final p in [
      'name.first',
      'tags.first',
      'tags[3]',
      'tags[-3]',
      'address[0]',
      'age[0]'
    ]) {
      expect(() => update(doc, Patch()..set(path(p), 1)),
          throwsA(isA<DeltaError>()));
    }
    expect(() => update(doc, Patch()..remove(path(''))),
        throwsA(isA<DeltaError>()));
  });
  test('extract makes an independent document', () {
    final d = Doc(encode(user));
    expect(extract(d, path('address')), encode(user['address']));
    expect(decode(extract(d, path('tags[1]'))!), 'white');
    expect(extract(d, path('address.country')), isNull);
  });
  test(
      'updates and extraction keep shared keys and a failed write can roll them back',
      () {
    final keys = SharedKeys()..add('name'), before = keys.length;
    final doc = Doc(encode(user, sharedKeys: keys), sharedKeys: keys);
    expect(keys.length, 7);
    final bytes = update(
        doc,
        Patch()
          ..set(path('address.city'), 'Moulinsart')
          ..set(path('newkey'), 1));
    expect(
        path('address.city').eval(Doc(bytes, sharedKeys: keys).root)?.asString,
        'Moulinsart');
    expect(keys.number('newkey'), isNull);
    expect(String.fromCharCodes(bytes), isNot(contains('name')));
    expect(decode(extract(doc, path('address'))!, sharedKeys: keys),
        user['address']);
    keys.truncate(before);
    expect(keys.keys, ['name']);
    expect(keys.add('other'), 1);
    keys.truncate(100);
    expect(keys.length, 2);
  });
  test('each value conforms only to its own concrete kind', () {
    final cases = <Kind, Object?>{
      Kind.none: const FleeceNone(),
      Kind.nullValue: null,
      Kind.boolean: true,
      Kind.integer: 1,
      Kind.float: 1.5,
      Kind.f32: FleeceFloat32(1.5),
      Kind.f16: FleeceFloat16.fromBits(0x3e00),
      Kind.u8: FleeceInt.u8(1),
      Kind.i8: FleeceInt.i8(-1),
      Kind.i16: FleeceInt.i16(-2),
      Kind.u16: FleeceInt.u16(2),
      Kind.i32: FleeceInt.i32(1),
      Kind.u32: FleeceInt.u32(1),
      Kind.u64: FleeceInt.u64((BigInt.one << 64) - BigInt.one),
      Kind.decimal: FleeceDecimal.parse('1.5'),
      Kind.bigDecimal: FleeceBigDecimal.parse('1.5'),
      Kind.string: 'text',
      Kind.bytes: Uint8List(1),
      Kind.uuid: FleeceUuid(Uint8List(16)),
      Kind.object: user,
      Kind.regex: const FleeceRegex('a+'),
      Kind.range: const FleeceRange(
          FleeceBound.unbounded(), FleeceBound.included(null)),
      const Kind.table(): const FleeceTable('user'),
      const Kind.record(['user']): FleeceRecordId('user', 1),
      const Kind.file(['b']): const FleeceFile('b', 'k'),
      Kind.date: FleeceDate(0),
      Kind.time: FleeceTime(1),
      Kind.datetime: FleeceSeconds.datetime(0, 0),
      Kind.timestamp: FleeceSeconds.timestamp(-1, 0),
      Kind.duration: FleeceSeconds.duration(1, 0),
      Kind.interval: FleeceInterval(1, 2, 3),
      const Kind.geometry([GeometryType.point]): FleeceGeometry.point(1, 2),
      const Kind.array(Kind.any): [1],
      const Kind.set(Kind.any): FleeceSet([1])
    };
    for (final e in cases.entries) {
      final root = Doc(encode(e.value)).root;
      expect(Kind.any.conforms(root), isTrue);
      for (final k in cases.keys) {
        expect(k.conforms(root), k == e.key,
            reason: e.value.runtimeType.toString());
      }
    }
    final raw =
        (Encoder()..writeUint((BigInt.one << 64) - BigInt.one)).finish();
    expect(Kind.u64.conforms(Doc(raw).root), isTrue);
  });
  test('kinds with conditions, structural literals and recursive names', () {
    bool fits(Kind k, Object? v) => k.conforms(Doc(encode(v)).root);
    expect(fits(const Kind.array(Kind.number, 3), [1, 1.5, FleeceInt.i8(3)]),
        isTrue);
    expect(fits(const Kind.array(Kind.number, 2), [1, 2, 3]), isFalse);
    expect(fits(const Kind.array(Kind.string), [1]), isFalse);
    expect(
        fits(const Kind.either([Kind.none, Kind.string]), const FleeceNone()),
        isTrue);
    expect(fits(const Kind.either([Kind.none, Kind.string]), 1), isFalse);
    expect(fits(const Kind.enumeration(['white', 'black']), 'red'), isFalse);
    final obj = const Kind.literal(
        KindLiteral.object({'city': Kind.string, 'zip': Kind.string}));
    expect(fits(obj, user['address']), isTrue);
    expect(fits(obj, {'city': 'b', 'zip': '1', 'a': 1}), isFalse);
    const pair = Kind.literal(KindLiteral.array([Kind.integer, Kind.string]));
    expect(fits(pair, [1, 'a']), isTrue);
    expect(fits(pair, [1]), isFalse);
    for (final (l, v) in <(KindLiteral, Object)>[
      (const KindLiteral.string('a'), 'a'),
      (const KindLiteral.boolean(true), true),
      (const KindLiteral.integer(7), 7),
      (const KindLiteral.float(2.0), const FleeceFloat64(2.0)),
      (
        KindLiteral.decimal(FleeceDecimal.parse('1.0')),
        FleeceDecimal.parse('1.0')
      ),
      (
        KindLiteral.duration(FleeceSeconds.duration(1, 2)),
        FleeceSeconds.duration(1, 2)
      )
    ]) {
      expect(fits(Kind.literal(l), v), isTrue);
      expect(fits(Kind.literal(l), null), isFalse);
    }
    final age = Doc(encode(FleeceInt.u8(9))).root;
    const named = {'Age': Kind.u8, 'Loop': Kind.named('Loop')};
    expect(const Kind.named('Age').conformsWith(age, named), isTrue);
    expect(const Kind.named('Age').conforms(age), isFalse);
    expect(const Kind.named('Loop').conformsWith(age, named), isFalse);
    expect(const Kind.function().conforms(age), isFalse);
  });
}
