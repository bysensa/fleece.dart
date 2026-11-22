import 'dart:math';
import 'dart:typed_data';

import 'package:fleece/fleece.dart';
import 'package:fleece_model_example/note.dart';
import 'package:fleece_signals/fleece_signals.dart';
import 'package:signals_core/signals_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test(
    'dynamic collections write through, follow the path and track individual edits',
    () {
      final doc = PacketRecord(
        encode({
          'attributes': {
            'flags': {'enabled': false, 'events': []},
            'keep': FleeceInt.u32(32),
          },
        }),
        tracking: FleeceSignals.new,
      );
      addTearDown(doc.dispose);
      final flags = doc.attributes['flags'] as Map;
      final seen = <bool>[];
      final stop = effect(() => seen.add(flags['enabled'] as bool));
      final draft = doc.beginTransaction();
      draft.attributes['flags']['enabled'] = true;
      (draft.attributes['flags']['events'] as List).add('new');
      expect(draft.attributes['flags']['events'], ['new']);
      expect(flags['events'], isEmpty);
      draft.rollback();
      expect(seen, [false]);
      doc.transaction<void>((edit) {
        edit.attributes['flags']['enabled'] = true;
        edit.attributes['flags']['events'].add('new');
      });
      expect(seen, [false, true]);
      stop();
      // Reference bytes from crates/fleece/examples/fleece encode.
      expect(
        doc.toFleece().map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        '4a617474726962757465730045666c61677347656e61626c6564466576656e747300'
        '436e6577600180037002800d3800800b8006446b65657000310600207002801a800c'
        '800880067001802580078003',
      );
      doc.attributes['flags'] = [1];
      final list = doc.attributes['flags'] as List;
      list.add(2);
      expect(() => flags['stale'] = 1, throwsStateError);
      expect(doc.attributes['flags'], [1, 2]);
      doc.attributes['flags'] = {'enabled': false};
      expect(() => list.add(3), throwsFormatException);
      flags['enabled'] = true;
      expect(doc.attributes['flags']['enabled'], isTrue);
    },
  );

  test(
    'Object and Object? codecs bind nested containers and detach decoded values',
    () {
      final bytes = encode({
        'value': [
          {'tag': 'old'},
        ],
      });
      final doc = EnvelopeRecord<Object>(bytes, codecT: FleeceCodecs.object);
      addTearDown(doc.dispose);
      final detached = doc.toModel().value as List;
      ((doc.value as List).single as Map)['tag'] = 'new';
      expect((doc.value as List).single, {'tag': 'new'});
      expect(detached.single, {'tag': 'old'});
      final empty = EnvelopeRecord<Object?>(
        encode({'value': null}),
        codecT: FleeceCodecs.value,
      );
      addTearDown(empty.dispose);
      expect(empty.value, isNull);
      empty.value = [1];
      (empty.value as List).add(2);
      expect(empty.toModel().value, [1, 2]);
      final invalid = EnvelopeRecord<Object>(
        encode({'value': null}),
        codecT: FleeceCodecs.object,
      );
      addTearDown(invalid.dispose);
      expect(() => invalid.value, throwsFormatException);
    },
  );

  test(
    'saved map keys enumerate the current document and expire with the draft',
    () {
      final doc = PacketRecord(
        encode({
          'attributes': {'a': 1},
        }),
        tracking: FleeceSignals.new,
      );
      addTearDown(doc.dispose);
      final keys = doc.attributes.keys;
      final seen = <List<String>>[];
      addTearDown(effect(() => seen.add(keys.toList())));
      final draft = doc.beginTransaction();
      final draftKeys = draft.attributes.keys;
      draft.attributes['b'] = 2;
      expect(draftKeys, ['a', 'b']);
      expect(keys, ['a']);
      draft.commit();
      expect(keys, ['a', 'b']);
      expect(seen, [
        ['a'],
        ['a', 'b'],
      ]);
      expect(() => draftKeys.toList(), throwsStateError);
    },
  );

  test(
    'map operations return the installed value across synchronous effects',
    () {
      final doc = EnvelopeRecord<Map<String, int>>(
        encode({'value': {}}),
        codecT: FleeceCodecs.map(FleeceCodecs.integer),
        tracking: FleeceSignals.new,
      );
      addTearDown(doc.dispose);
      final map = doc.value;
      addTearDown(
        effect(() {
          if (map['x'] == 1) map.remove('x');
        }),
      );
      expect(map.putIfAbsent('x', () => 1), 1);
      expect(map.containsKey('x'), isFalse);
      map['x'] = 2;
      expect(map.update('x', (_) => 1), 1);
      expect(map.containsKey('x'), isFalse);
    },
  );

  test(
    'mixed edits agree with plain Dart and canonical bytes at every commit',
    () {
      final random = Random(13579);
      final model = const Note(title: 'test', address: Address('A'));
      final doc = NoteRecord(model.toFleece());
      addTearDown(doc.dispose);
      var committed = <String>[];
      for (var round = 0; round < 40; round++) {
        final draft = doc.beginTransaction(), list = draft.tags;
        final plain = [...committed];
        for (var i = 0; i < 18; i++) {
          final value = 'tag-${random.nextInt(20)}';
          final index = random.nextInt(plain.length + 1);
          switch (random.nextInt(7)) {
            case 0:
              list.add(value);
              plain.add(value);
            case 1:
              list.insert(index, value);
              plain.insert(index, value);
            case 2:
              list.addAll([value, value]);
              plain.addAll([value, value]);
            case 3 when index < plain.length:
              list[index] = value;
              plain[index] = value;
            case 4 when index < plain.length:
              expect(list.removeAt(index), plain.removeAt(index));
            case 5:
              list.length = index;
              plain.length = index;
            default:
              list.sort();
              plain.sort();
          }
          expect(list, plain);
          expect(doc.tags, committed);
        }
        if (round % 3 == 0) {
          draft.rollback();
        } else {
          draft.commit();
          committed = plain;
        }
        expect(
          doc.toFleece(),
          Note(
            title: model.title,
            address: model.address,
            tags: committed,
          ).toFleece(),
        );
      }
    },
  );

  test(
    'appended slots support nested edits, replacements and independent removal',
    () {
      final record = PacketRecord(
        Packet(
          Uint8List(0),
          FleeceUuid.parse('00112233-4455-6677-8899-aabbccddeeff'),
          DateTime.utc(2020),
          sequence: BigInt.zero,
        ).toFleece(),
      );
      addTearDown(record.dispose);
      record.transaction<void>((draft) {
        final list = draft.destinations.putIfAbsent('N', () => []);
        for (var i = 0; i < 400; i++) {
          list.add(Address('city-$i'));
          expect(list.length, i + 1);
        }
        list[0]!.city = 'first';
        list[399] = const Address('last');
        list[399]!.postcode = '123';
        expect(list.first!.city, 'first');
        expect(draft.toModel().destinations['N']!.last!.postcode, '123');
        expect(record.destinations.containsKey('N'), isFalse);
      });
      expect(record.destinations['N']!.last!.city, 'last');
      final detached = record.destinations.remove('N')!;
      detached.clear();
      detached.add(const Address('a'));
      detached.add(const Address('b'));
      expect(detached.map((item) => item!.city), ['a', 'b']);
      expect(record.destinations, isEmpty);
    },
  );

  test(
    'list edits are isolated, accept domain objects and preserve unknown fields',
    () {
      final original = encode({
        'destinations': {
          'N': [
            {'city': 'Riga', 'future': FleeceInt.u32(91)},
            {'city': 'Oslo'},
          ],
        },
      });
      final record = PacketRecord(original, tracking: FleeceSignals.new);
      addTearDown(record.dispose);
      final cities = <List<String?>>[];
      final list = record.destinations['N']!;
      addTearDown(
        effect(() => cities.add([for (final item in list) item?.city])),
      );
      final draft = record.beginTransaction();
      final items = draft.destinations['N']!;
      final List<Address?> asDomain = items;
      asDomain.add(const Address('Bern'));
      items.insertAll(0, [null, const Address('Rome')]);
      items[1] = const Address('Paris');
      items.removeAt(0);
      items.sort((a, b) => a!.city.compareTo(b!.city));
      expect(items.map((a) => a!.city), ['Bern', 'Oslo', 'Paris', 'Riga']);
      expect(list.length, 2);
      draft.commit();
      expect(cities, [
        ['Riga', 'Oslo'],
        ['Bern', 'Oslo', 'Paris', 'Riga'],
      ]);
      final removed = list.removeLast()!;
      expect(removed.city, 'Riga');
      expect((decode(removed.toFleece()) as Map)['future'], FleeceInt.u32(91));
      removed.city = 'Tallinn';
      expect(list.last!.city, 'Paris');
      expect(() => items.add(null), throwsStateError);
      expect(cities.length, 3);
      record.destinations['N'] = [removed];
      expect(list.single!.city, 'Tallinn');
      expect(
        record.toFleece(),
        encode({
          'destinations': {
            'N': [
              {'city': 'Tallinn', 'future': FleeceInt.u32(91)},
            ],
          },
        }),
      );
      final selected = list.single;
      list.removeWhere((address) => identical(address, selected));
      expect(list, isEmpty);
    },
  );

  test(
    'map additions, deletions and explicit null track just the selected key',
    () {
      final record = PacketRecord(
        encode({
          'attributes': {'keep': 'old'},
        }),
        tracking: FleeceSignals.new,
      );
      addTearDown(record.dispose);
      final map = record.attributes;
      final seen = <Object?>[], present = <bool>[], keySets = <List<String>>[];
      addTearDown(effect(() => seen.add(map['selected'])));
      addTearDown(effect(() => present.add(map.containsKey('selected'))));
      addTearDown(effect(() => keySets.add(map.keys.toList())));
      map.addEntries([
        const MapEntry('other', 3),
        const MapEntry('a.b[0]', 'punctuation'),
      ]);
      expect(seen, [null]);
      map['selected'] = null;
      expect(present, [false, true]);
      expect(
        map.putIfAbsent('selected', () => throw StateError('already present')),
        isNull,
      );
      record.transaction<void>((draft) {
        final attrs = draft.attributes;
        expect(attrs.remove('other'), 3);
        expect(attrs.containsKey('other'), isFalse);
        attrs.update('selected', (_) => 4);
        attrs.update('new', (_) => 0, ifAbsent: () => 12);
        attrs.updateAll((k, v) => k == 'keep' ? 'new' : v);
        attrs.removeWhere((k, _) => k.startsWith('a.'));
        expect(attrs.keys, ['keep', 'new', 'selected']);
        expect(map['selected'], isNull);
      });
      expect(seen.last, 4);
      expect(keySets.length, 4);
      expect(map.remove('missing'), isNull);
      map.clear();
      expect(map, isEmpty);
      expect(present, [false, true, false]);
    },
  );

  test(
    'range operations and bulk callbacks leave the draft intact on failure',
    () {
      final record = NoteRecord(
        encode({
          'tags': ['a', 'b', 'c'],
        }),
      );
      addTearDown(record.dispose);
      final draft = record.beginTransaction();
      final tags = draft.tags;
      tags.setRange(1, 3, ['skip', 'd', 'e'], 1);
      tags.replaceRange(0, 2, ['f', 'g', 'h']);
      tags.setAll(0, ['i', 'j']);
      tags.fillRange(1, 3, 'k');
      tags.removeRange(2, 3);
      tags.first = 'm';
      tags.last = 'n';
      expect(tags, ['m', 'k', 'n']);
      expect(() => tags[3] = 'bad', throwsRangeError);
      expect(() => tags.length = 4, throwsA(isA<TypeError>()));
      expect(
        () => tags.removeWhere((v) {
          if (v == 'k') throw StateError('stop');
          return true;
        }),
        throwsStateError,
      );
      Iterable<String> invalid() sync* {
        yield 'valid';
        yield String.fromCharCode(0xd800);
      }

      expect(() => tags.addAll(invalid()), throwsArgumentError);
      expect(tags, ['m', 'k', 'n']);
      tags.retainWhere((v) => v != 'k');
      expect(tags.remove('absent'), isFalse);
      expect(tags.remove('n'), isTrue);
      draft.commit();
      expect(record.tags, ['m']);
      final packet = PacketRecord(
        encode({
          'attributes': {'a': 1, 'b': 2},
        }),
      );
      addTearDown(packet.dispose);
      final tx = packet.beginTransaction();
      tx.attributes['first'] = 10;
      expect(
        () => tx.attributes.updateAll((k, v) {
          if (k == 'b') throw StateError('stop');
          return 100;
        }),
        throwsStateError,
      );
      expect(
        () => tx.attributes.update('a', (v) {
          tx.attributes.clear();
          return 3;
        }),
        throwsStateError,
      );
      expect(tx.attributes, {'first': 10, 'a': 1, 'b': 2});
      tx.commit();
      expect(packet.attributes, {'first': 10, 'a': 1, 'b': 2});
    },
  );

  test(
    'shared-key commits keep canonical bytes with mixed old and new fields',
    () {
      final keys = SharedKeys();
      for (final key in ['z', 'y', 'attributes', 'name', 'a', 'b']) {
        keys.add(key);
      }
      final initial = {
        'z': {'z': 'last original', 'a': 'first original'},
        'attributes': {'z': 'last', 'y': 'middle'},
      };
      final doc = PacketRecord(
        encode(initial, sharedKeys: keys),
        sharedKeys: keys,
      );
      addTearDown(doc.dispose);
      doc.transaction<void>((draft) {
        draft.attributes['a'] = 'first';
        draft.attributes['b'] = 'second';
      });
      final expected = encode({
        ...initial,
        'attributes': {'z': 'last', 'y': 'middle', 'a': 'first', 'b': 'second'},
      }, sharedKeys: keys);
      expect(doc.toFleece(), expected);
      expect(doc.toFleece(sharedKeys: keys), expected);
      expect(doc.sharedKeyState, keys.toState());
    },
  );
}
