import 'dart:typed_data';

import 'package:fleece/fleece.dart';
import 'package:fleece_model_example/note.dart';
import 'package:fleece_signals/fleece_signals.dart';
import 'package:signals_core/signals_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test(
    'configured class names preserve nominal types, methods and setters',
    () {
      final base = encode({'count': 1, 'old': 'x' * 512});
      final history = Uint8List.fromList([
        ...base,
        ...appendDelta(base, {'count': 2}),
      ]);
      final counter = CounterRecord(history, tracking: FleeceSignals.new);
      addTearDown(counter.dispose);
      expect(counter.toFleece(), history);
      final CounterModel asModel = counter;
      final seen = <int>[];
      addTearDown(effect(() => seen.add(asModel.count)));
      expect(asModel.isEven, isTrue);
      asModel.increment();
      expect(asModel.isEven, isFalse);
      counter.transaction<void>((draft) {
        final CounterModel model = draft;
        model.increment(2);
        model.count++;
        expect(model.isEven, isTrue);
        expect(asModel.count, 3);
      });
      expect(seen, [2, 3, 6]);
      final detached = counter.toModel();
      detached.increment();
      expect(counter.count, 6);
      expect(CounterRecord(asModel.toFleece()).count, 6);

      final meter = MeterRecord(encode({'tick': 3}));
      addTearDown(meter.dispose);
      expect(meter.odd, isTrue);
      meter.tick = 4;
      expect(meter.odd, isFalse);

      final shipment = Shipment(const Delivery().toFleece());
      addTearDown(shipment.dispose);
      final Delivery originalInterface = shipment;
      final AddressRecord address = shipment.address;
      address.city = 'Riga';
      expect(originalInterface.address.city, 'Riga');
      expect(shipment.address, same(address));
      expect(AddressRecord(address.toFleece()).city, 'Riga');
    },
  );

  test('an effect can start a new transaction on the committed version', () {
    final doc = AddressRecord(
      const Address('Lyon').toFleece(),
      tracking: FleeceSignals.new,
    );
    addTearDown(doc.dispose);
    final seen = <String>[];
    addTearDown(
      effect(() {
        final city = doc.city;
        seen.add(city);
        if (city == 'Paris') {
          doc.transaction<void>((draft) => draft.postcode = '75001');
        }
      }),
    );
    doc.transaction<void>((draft) => draft.city = 'Paris');
    expect(doc.postcode, '75001');
    expect(seen, ['Lyon', 'Paris']);
  });

  test(
    'models reached through a map and a list edit and track the selected field',
    () {
      final packet = Packet(
        Uint8List(0),
        FleeceUuid.parse('00112233-4455-6677-8899-aabbccddeeff'),
        DateTime.utc(2020),
        sequence: BigInt.one,
        destinations: {
          'N': [const Address('Lyon'), null],
        },
      );
      final record = PacketRecord(
        packet.toFleece(),
        tracking: FleeceSignals.new,
      );
      addTearDown(record.dispose);
      final cities = <String?>[], keys = <List<String>>[];
      addTearDown(
        effect(() => cities.add(record.destinations['N']?.first?.city)),
      );
      addTearDown(effect(() => keys.add(record.destinations.keys.toList())));
      final AddressRecord address = record.destinations['N']!.first!;
      record.transaction<void>((draft) {
        draft.destinations['N']![0]!.city = 'Paris';
        expect(draft.toModel().destinations['N']!.first!.city, 'Paris');
        expect(address.city, 'Lyon');
      });
      address.postcode = '75001';
      expect(cities, ['Lyon', 'Paris']);
      expect(keys, [
        ['N'],
      ]);
      expect(record.destinations['N']!.last, isNull);
      record.destinations = {
        'S': [address],
      };
      expect(cities, ['Lyon', 'Paris', null]);
      expect(keys, [
        ['N'],
        ['S'],
      ]);
      expect(() => address.city = 'lost', throwsStateError);
      expect(
        PacketRecord(record.toFleece()).destinations['S']!.first!.postcode,
        '75001',
      );
    },
  );

  test(
    'generated serializers preserve native Fleece types and nested collections',
    () {
      final id = FleeceUuid.parse('00112233-4455-6677-8899-aabbccddeeff');
      final when = DateTime.fromMicrosecondsSinceEpoch(-1234567, isUtc: true);
      final sequence = BigInt.parse('18446744073709551615');
      final precise = FleeceFloat64.fromBits(
        BigInt.parse('7ff0000000000001', radix: 16),
      );
      final small = FleeceFloat32.fromBits(0xffc01234);
      final packet = Packet(
        Uint8List.fromList([0, 128, 255]),
        id,
        when,
        sequence: sequence,
        weight: -0.0,
        enabled: false,
        precise: precise,
        small: small,
        cost: 4.25,
        attributes: {'extra': id, 'empty': null},
        destinations: {
          '😀': [null, const Address('Oslo')],
          '\ue000': [const Address('Kyiv')],
        },
      );
      final bytes = packet.toFleece();
      final dict = Doc(bytes).root.asDict!;
      expect(dict[r'$bytes[0]']!.type, ValueType.data);
      expect(dict['id']!.extKind, ExtKind.uuid);
      expect(dict['timestamp']!.extKind, ExtKind.datetime);
      expect(dict['timestamp']!.read(), FleeceDatetime(-2, 765433000));
      expect(dict['sequence']!.asInteger, sequence);
      expect(dict['small']!.type, ValueType.float32);
      expect(dict['precise']!.type, ValueType.float64);
      final value = PacketRecord(bytes).toModel();
      expect(value.bytes, packet.bytes);
      expect(value.id, id);
      expect(value.timestamp, when);
      expect(value.timestamp.isUtc, isTrue);
      expect(value.sequence, sequence);
      expect(value.weight.isNegative, isTrue);
      expect(value.enabled, isFalse);
      expect(value.small!.bits, small.bits);
      expect(value.precise!.bits, precise.bits);
      expect(value.cost, 4.25);
      expect(value.attributes, {'extra': id, 'empty': null});
      expect(value.destinations['😀']!.first, isNull);
      expect(value.destinations['😀']!.last!.city, 'Oslo');
      expect(value.destinations['\ue000']!.single!.city, 'Kyiv');
      expect(value.toFleece(), bytes);

      final doc = PacketRecord(bytes);
      addTearDown(doc.dispose);
      final blob = Uint8List.fromList([42, 7]);
      doc.transaction<void>((draft) {
        draft.bytes = blob;
        blob[0] = 1;
        draft.home = const Address('Brno');
        draft.home!.postcode = '60200';
        draft.destinations = {
          'N': [draft.home],
        };
      });
      doc.bytes[0] = 99;
      expect(doc.bytes, [42, 7]);
      expect(doc.destinations['N']!.single!.postcode, '60200');
      expect(
        PacketRecord(doc.toFleece()).toModel().precise!.bits,
        precise.bits,
      );
      expect(() => doc.destinations.clear(), throwsUnsupportedError);
      expect(() => doc.destinations['N']!.clear(), throwsUnsupportedError);
      expect(
        () => FleeceCodecs.dateTime.decode(encode(FleeceDatetime(1, 1))),
        throwsFormatException,
      );
    },
  );

  test(
    'effects and computed see one atomic change to their actual dependencies',
    () {
      final bytes = const Note(
        title: 'Draft',
        address: Address('Lyon'),
      ).toFleece();
      final doc = NoteRecord(bytes, tracking: FleeceSignals.new);
      addTearDown(doc.dispose);
      final summary = computed(() => '${doc.title} / ${doc.address.city}');
      addTearDown(summary.dispose);
      final summaries = <String>[], counts = <int>[], tags = <List<String>>[];
      addTearDown(effect(() => summaries.add(summary.value)));
      addTearDown(effect(() => counts.add(doc.visits)));
      addTearDown(effect(() => tags.add(doc.tags)));
      final tx = doc.beginTransaction();
      tx.title = 'Published';
      tx.address.city = 'Paris';
      tx.visits++;
      tx.visits++;
      expect(summaries, ['Draft / Lyon']);
      expect(counts, [0]);
      tx.commit();
      expect(summaries, ['Draft / Lyon', 'Published / Paris']);
      expect(counts, [0, 2]);
      doc.transaction<void>((d) {
        d.address = const Address('Paris', postcode: 'new');
        d.title = 'temporary';
        d.title = 'Published';
        d.tags = ['guide'];
      });
      doc.transaction<void>((d) => d.tags = ['guide']);
      final rollback = doc.beginTransaction();
      rollback.visits = 3;
      rollback.rollback();
      expect(summaries.length, 2);
      expect(counts, [0, 2]);
      expect(tags, [
        <String>[],
        ['guide'],
      ]);
    },
  );

  test('nullable nested models track presence and leaf independently', () {
    final doc = NoteRecord(
      const Note(title: 'N', address: Address('Lyon')).toFleece(),
      tracking: FleeceSignals.new,
    );
    addTearDown(doc.dispose);
    final cities = <String?>[];
    final presence = <bool>[];
    addTearDown(effect(() => cities.add(doc.secondary?.city)));
    addTearDown(effect(() => presence.add(doc.secondary != null)));
    doc.transaction<void>((d) => d.secondary = const Address('Riga'));
    doc.transaction<void>((d) => d.secondary!.postcode = 'LV-1001');
    doc.transaction<void>((d) => d.secondary!.city = 'Tallinn');
    doc.transaction<void>((d) => d.secondary = null);
    expect(cities, [null, 'Riga', 'Tallinn', null]);
    expect(presence, [false, true, false]);
  });

  test(
    'missing defaults compare as typed values and nested default edits preserve siblings',
    () {
      final old = NoteRecord(
        encode({
          'display.title': 'old',
          'address': {'city': 'Paris'},
        }),
        tracking: FleeceSignals.new,
      );
      addTearDown(old.dispose);
      final visits = <int>[];
      addTearDown(effect(() => visits.add(old.visits)));
      old.transaction<void>((d) => d.visits = 0);
      expect(visits, [0]);
      old.transaction<void>((d) => d.visits = 1);
      expect(visits, [0, 1]);
      final empty = encode(<String, Object?>{});
      final doc = Shipment(empty, tracking: FleeceSignals.new);
      addTearDown(doc.dispose);
      final seen = <String>[];
      addTearDown(effect(() => seen.add(doc.address.city)));
      expect(Shipment(empty).toModel().address.city, 'Lyon');
      doc.transaction<void>((draft) {
        draft.address.city = 'Dijon';
        expect(draft.address.postcode, '69000');
      });
      expect(seen, ['Lyon', 'Dijon']);
      final saved = Shipment(doc.toFleece()).toModel();
      expect((saved.address.city, saved.address.postcode), ('Dijon', '69000'));
    },
  );

  test(
    'failed depth check leaves bytes and observers unchanged and releases the writer',
    () {
      final bytes = const Branch('root').toFleece();
      final doc = BranchRecord(bytes, tracking: FleeceSignals.new);
      addTearDown(doc.dispose);
      final seen = <String?>[];
      addTearDown(effect(() => seen.add(doc.child?.name)));
      var deep = const Branch('leaf');
      for (var i = 1; i < maxDepth; i++) {
        deep = Branch('n', child: deep);
      }
      final tx = doc.beginTransaction();
      tx.child = deep; // Fits on its own but is one level too deep at commit.
      expect(tx.commit, throwsA(isA<DeltaError>()));
      expect(tx.isActive, isFalse);
      expect(doc.toFleece(), bytes);
      expect(seen, [null]);
      doc.transaction<void>((draft) => draft.child = const Branch('new'));
      expect(seen, [null, 'new']);
    },
  );
}
