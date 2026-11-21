import 'dart:typed_data';
import 'package:fleece/fleece.dart';
import 'package:test/test.dart';

enum Coat { White }

/// The application controls field order, variant tags and borrowed views.
final class Dog {
  Dog(this.name, this.chip, this.age, this.owner, this.coats);
  final String name;
  final Uint8List chip;
  final int age;
  final String? owner;
  final List<FleeceVariant> coats;
}

final dog = Dog('Milou', Uint8List.fromList([0xde, 0xad]), 9, 'Tintin', [
  const FleeceVariant('Spotted', 3),
  const FleeceVariant('Dyed', {'colour': 'blue', 'washable': true}),
  const FleeceVariant('Mixed', [1, 2])
]);
final maxUint = (BigInt.one << 64) - BigInt.one;
Map<Object, Object?> dogFields(Dog d) => {
      'name': d.name,
      'chip': d.chip,
      'age': d.age,
      'weight': FleeceFloat32(7.5),
      'height': 0.1,
      'owner': d.owner,
      'vet': null,
      'coat': Coat.White,
      'coats': d.coats,
      'scores': {'fetch': 10, 'sit': -2},
      'by_year': {2025: true},
      'pair': [-7, 'é'],
      'unit': null,
      'id': FleeceUuid(Uint8List.fromList(List.filled(16, 7))),
      'born': FleeceSeconds.datetime(1500000000, 5),
      'price': FleeceDecimal.parse('12.50'),
      'record': FleeceRecordId('dog', 'milou'),
      'anything': FleeceSet([1, const FleeceNone()]),
      'big': maxUint
    };
final dogAdapter = FleeceAdapter<Dog>(dogFields, (r) {
  expect(r['vet'].isAbsent, isTrue);
  expect(r['unit'].isAbsent, isTrue);
  expect(r['coat'].variant, ('White', null));
  expect(r['weight'].floating, 7.5);
  expect(r['height'].floating, 0.1);
  expect(r['scores']['sit'].integer(), BigInt.from(-2));
  expect(r['by_year']['2025'].boolean, isTrue);
  expect(r['pair'].sequence.last.string, 'é');
  expect(r['id'].typed<FleeceUuid>().bytes, List.filled(16, 7));
  expect(
      r['born'].typed<FleeceSeconds>(), FleeceSeconds.datetime(1500000000, 5));
  expect(r['price'].typed<FleeceDecimal>(), FleeceDecimal.parse('12.50'));
  expect(r['record'].typed<FleeceRecordId>(), FleeceRecordId('dog', 'milou'));
  expect(r['anything'].value, FleeceSet([1, const FleeceNone()]));
  expect(r['big'].integer(signed: false), maxUint);
  final coats = [
    for (final v in r['coats'].sequence)
      FleeceVariant(v.variant.$1, v.variant.$2!.value)
  ];
  return Dog(
      r['name'].string,
      r['chip'].bytes,
      r['age'].integer(bits: 8, signed: false).toInt(),
      r['owner'].isAbsent ? null : r['owner'].string,
      coats);
});
void main() {
  test('application visitors unwrap text, table, regex, sets and UUIDs', () {
    final id = Uint8List.fromList(List.generate(16, (i) => i));
    final b = encode([
      const FleeceTable('dog'),
      const FleeceRegex('d+'),
      FleeceUuid(id),
      FleeceSet([FleeceInt.i8(-3), const FleeceNone()])
    ]);
    expect(fromSlice(b, FleeceAdapter<Object?>((v) => v, (r) => r.any)), [
      'dog',
      'd+',
      id,
      [-3, null]
    ]);
    final unchecked = Doc.trusted(Uint8List.fromList([0x3c, 0])).root;
    expect(fromRef(unchecked, FleeceAdapter<bool>((v) => v, (r) => r.isAbsent)),
        isTrue);
  });
  test('typed time fields distinguish duration, datetime and timestamp', () {
    final timestamp = FleeceTimestamp(-1, 250000000);
    final a = FleeceAdapter<FleeceTimestamp>(
        (v) => v, (r) => r.typed<FleeceTimestamp>());
    expect(fromSlice(toVec(timestamp, adapter: a), a), timestamp);
    for (final other in [FleeceDatetime(-1, 250000000), FleeceDuration(1, 0)]) {
      expect(() => fromSlice(encode(other), a), throwsA(isA<SerdeError>()));
    }
  });
  test('an application struct reads back as written', () {
    final d = fromSlice(toVec(dog, adapter: dogAdapter), dogAdapter);
    expect([d.name, d.chip, d.age, d.owner], [dog.name, dog.chip, 9, 'Tintin']);
    expect(d.coats.map((c) => c.name), ['Spotted', 'Dyed', 'Mixed']);
    expect(d.coats.map((c) => c.value), [
      3,
      {'colour': 'blue', 'washable': true},
      [1, 2]
    ]);
  });
  test(
      'struct fields, integer map keys and variants have their hand-written values',
      () {
    final v = decode(toVec(dog, adapter: dogAdapter)) as Map;
    expect(v['age'], 9);
    expect(v['weight'], FleeceFloat32(7.5));
    expect(v['height'], 0.1);
    expect(v['big'], FleeceInt.u64(maxUint));
    expect(v['chip'], [222, 173]);
    expect(v['vet'], isNull);
    expect(v['unit'], isNull);
    expect(v['pair'], [-7, 'é']);
    expect(v['coat'], 'White');
    expect((v['coats'] as List).first, {'Spotted': 3});
    expect(v['by_year'], {'2025': true});
    expect(v['anything'], FleeceSet([1, const FleeceNone()]));
  });
  test('strings as UTF-8 and bytes are lent out of the document', () {
    final bytes = toVec(dog, adapter: dogAdapter);
    final slices = fromSlice(
            bytes,
            FleeceAdapter<Object?>(
                (_) => null, (r) => [r['name'].utf8Bytes, r['chip'].bytes]))
        as List<Uint8List>;
    for (final s in slices) {
      final start = s.offsetInBytes - bytes.offsetInBytes;
      expect(start, greaterThanOrEqualTo(0));
      expect(s, bytes.sublist(start, start + s.length));
      final old = bytes[start];
      bytes[start] = old ^ 1;
      expect(s[0], old ^ 1);
      bytes[start] = old;
    }
  });
  test('a typed application reads hand-written fields and individual refs', () {
    final bytes = encode({
      'name': 'Milou',
      'age': FleeceInt.u8(9),
      'tall': FleeceFloat16.fromBits(0x3e00),
      'tags': FleeceSet(['dog']),
      'nick': const FleeceNone(),
      'more': FleeceUuid(Uint8List(16))
    });
    final small = FleeceAdapter<Object?>(
        (_) => null,
        (r) => [
              r['name'].string,
              r['age'].integer(bits: 8, signed: false).toInt(),
              r['tall'].floating,
              r['tags'].sequence.single.string,
              r['nick'].isAbsent
            ]);
    expect(fromSlice(bytes, small), ['Milou', 9, 1.5, 'dog', true]);
    expect(
        fromRef(Doc(bytes).root.asDict!['name']!,
            FleeceAdapter<String>((s) => s, (r) => r.string)),
        'Milou');
  });
  test('a text with marks is read as its own type or a string', () {
    final t = FleeceText.fromRuns([
          ('Mil', {'bold': true}),
          ('ou', null)
        ]),
        b = toVec({'title': t});
    expect(decode(b), {'title': t});
    expect(
        fromSlice(
            b,
            FleeceAdapter<Object?>((v) => v,
                (r) => [r['title'].typed<FleeceText>(), r['title'].string])),
        [t, 'Milou']);
  });
  test('type mismatches report the reason, malformed bytes report decoding',
      () {
    final small = FleeceAdapter<Object?>(
        (v) => v, (r) => r['age'].integer(bits: 8, signed: false));
    for (final v in [300, 'nine', FleeceSeconds.datetime(0, 0)]) {
      expect(
          () => fromSlice(encode({'age': v}), small),
          throwsA(isA<SerdeError>().having((e) => e.message, 'reason',
              contains(v is FleeceSeconds ? 'datetime' : 'u8'))));
    }
    expect(
        () => fromSlice(Uint8List.fromList([128]), small),
        throwsA(isA<SerdeError>()
            .having((e) => e.code, 'code', SerdeErrorCode.decode)));
    expect(
        () => fromSlice(encode(1),
            FleeceAdapter<Object?>((v) => v, (r) => r.typed<FleeceUuid>())),
        throwsFormatException);
    expect(() => toVec({true: 1}), throwsFormatException);
    expect(() => toVec(BigInt.one << 128), throwsFormatException);
  });
  test('shared keys in structs and nested owned values', () {
    final keys = SharedKeys(), e = Encoder(sharedKeys: keys);
    toEncoder(dog, e, adapter: dogAdapter);
    final b = e.finish();
    expect(b.length, lessThan(toVec(dog, adapter: dogAdapter).length));
    expect(keys.number('name'), isNotNull);
    expect(fromSlice(b, dogAdapter, sharedKeys: keys).name, 'Milou');
    final v = {
          'name': 'Milou',
          'home': {'city': 'Brussels'}
        },
        r = Doc(encode(v, sharedKeys: keys), sharedKeys: keys).root;
    expect(fromRef(r, FleeceAdapter<Object?>((v) => v, (r) => r.value)), v);
    expect(
        fromRef(
            r,
            FleeceAdapter<Object?>(
                (v) => v, (r) => [r['name'].string, r['home'].value])),
        ['Milou', v['home']]);
    expect(keys.number('city'), isNotNull);
  });
}
