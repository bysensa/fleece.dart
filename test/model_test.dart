import 'dart:async';
import 'dart:typed_data';

import 'package:fleece/fleece.dart';
import 'package:test/test.dart';

import '../example/models/lib/note.dart';

Uint8List _hex(String text) => Uint8List.fromList([
      for (var i = 0; i < text.length; i += 2)
        int.parse(text.substring(i, i + 2), radix: 16),
    ]);

const _note = Note(title: 'Field notes', address: Address('Lyon'));

void main() {
  test('DateTime preserves microseconds across the full UTC calendar range',
      () {
    for (final time in [
      DateTime.utc(1500, 2, 3, 4, 5, 6, 7, 891),
      DateTime.utc(2400, 2, 3, 4, 5, 6, 7, 891),
      DateTime.utc(-271821, 4, 20, 0, 0, 0, 0, 1),
      DateTime.utc(275760, 9, 12, 23, 59, 59, 999, 999),
      DateTime.utc(275760, 9, 13),
    ]) {
      final millis = time.millisecondsSinceEpoch;
      final seconds = (millis - millis % 1000) ~/ 1000;
      final expected = encode(FleeceDatetime(
          seconds, time.millisecond * 1000000 + time.microsecond * 1000));
      expect(FleeceCodecs.dateTime.encode(time), expected,
          reason: time.toString());
      expect(FleeceCodecs.dateTime.decode(expected), time);
    }
    final beyond = encode(FleeceDatetime(BigInt.from(8640000000000), 1000));
    expect(() => FleeceCodecs.dateTime.decode(beyond), throwsFormatException);
  });

  test(
      'direct setters and nested transactions operate on the original field names',
      () {
    final raw = encode({
      'display.title': 'N',
      'address': {'city': 'Lyon', 'future-key': 'preserved'},
    });
    final note = NoteRecord(raw);
    addTearDown(note.dispose);
    final Note interface = note;
    final AddressRecord address = note.address;
    expect(interface.address, same(address));
    note.title = 'Trip';
    address.city = 'Paris';
    expect(interface.title, 'Trip');
    expect(note.toModel().address.city, 'Paris');
    final draft = address.beginTransaction();
    draft.city = 'Lille';
    expect(address.city, 'Paris');
    expect(AddressRecord(draft.toFleece()).city, 'Lille');
    draft.commit();
    expect(address.city, 'Lille');
    note.secondary = address;
    expect(
        (decode(note.secondary!.toFleece()) as Map)['future-key'], 'preserved');
    note.secondary!.city = 'Brno';
    expect(address.city, 'Lille');
    final saved = note.toFleece();
    expect(
        () => address.city = String.fromCharCode(0xd800), throwsArgumentError);
    expect(note.toFleece(), saved);
    expect(NoteRecord(saved).secondary!.city, 'Brno');
  });

  test('generated codec and committed edits match independent Rust bytes', () {
    // Produced with crates/fleece/examples/fleece encode at 1be207f.
    final lyon = _hex('446369747900444c796f6e0048706f7374636f646500453639303030'
        '7002800f800d800b80078005');
    final paris =
        _hex('44636974790045506172697348706f7374636f646500453735303031'
            '7002800f800d800b80078005');
    final original = AddressRecord(lyon).toModel();
    expect((original.city, original.postcode), ('Lyon', '69000'));
    expect(original.toFleece(), lyon);
    final document = AddressRecord(lyon);
    addTearDown(document.dispose);
    document.transaction<void>((draft) {
      draft.postcode = '75001';
      draft.city = 'Paris';
    });
    expect(document.toFleece(), paris);

    final bytes = _hex(
        '4761646472657373446369747900444c796f6e0048706f7374636f646500'
        '7002800c800a800830004d646973706c61792e7469746c654b4669656c64206e6f746573'
        '487072696f7269747900466e6f726d616c00497365636f6e646172794474616773004444'
        '6172740046466c65656365006002800880064676697369747300700680418033802f8029'
        '80248020801d3000801a8011800f0003800d');
    final note = NoteRecord(bytes).toModel();
    expect(note.tags, ['Dart', 'Fleece']);
    expect(note.address.city, 'Lyon');
    expect(note.visits, 3);
    expect(note.toFleece(), bytes);
  });

  test('missing fields use constructor defaults and explicit null is checked',
      () {
    final fields = {
      'display.title': 'old',
      'address': {'city': 'Minsk'}
    };
    final old = encode(fields);
    final note = NoteRecord(old).toModel();
    expect(note.visits, 0);
    expect(note.secondary, isNull);
    expect(note.priority, Priority.normal);
    expect(note.tags, isEmpty);
    final doc = NoteRecord(old);
    addTearDown(doc.dispose);
    expect(doc.address.postcode, isNull);
    expect(doc.tags, isEmpty);
    doc.transaction<void>((d) => d.visits++);
    expect(doc.visits, 1);
    expect(
        () => NoteRecord(encode({...fields, 'visits': null})).toModel(),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'field', contains('visits'))));
    expect(() => NoteRecord(encode({'address': {}})).toModel(),
        throwsFormatException);
    final invalidChild = encode({
      ...fields,
      'address': {'city': 7}
    });
    final at =
        Doc(invalidChild).root.asDict!['address']!.asDict!['city']!.position;
    expect(
        () => NoteRecord.codec.decode(invalidChild),
        throwsA(
            isA<FormatException>().having((e) => e.offset, 'city offset', at)));
    expect(
        () => NoteRecord(encode({...fields, 'priority': 'unknown'})).toModel(),
        throwsFormatException);
    expect(() => NoteRecord(encode([1])), throwsFormatException);
    expect(() => NoteRecord(Uint8List(1)), throwsFormatException);
    // Independent getters can read a well-typed field of a newer schema.
    final other = NoteRecord(encode({...fields, 'visits': 'bad'}));
    addTearDown(other.dispose);
    expect(other.title, 'old');
    expect(() => other.visits, throwsFormatException);
  });

  test(
      'overlapping nested edits see staged values and isolate committed readers',
      () {
    final document = NoteRecord(_note.toFleece());
    addTearDown(document.dispose);
    final live = document.address;
    final draft = document.beginTransaction();
    final address = draft.address;
    address.city = 'Berlin';
    expect(draft.address.city, 'Berlin');
    draft.address = const Address('Paris', postcode: '75001');
    expect(address.city, 'Paris');
    address.city = 'Tours';
    expect((draft.address.city, draft.address.postcode), ('Tours', '75001'));
    expect(live.city, 'Lyon');
    expect(() => live.city = 'London', throwsStateError);
    expect(() => document.beginTransaction(), throwsStateError);
    expect(draft.secondary, isNull);
    draft.secondary = const Address('Brno');
    final secondary = draft.secondary!;
    secondary.city = 'Prague';
    expect(draft.secondary!.city, 'Prague');
    draft.secondary = null;
    expect(draft.secondary, isNull);
    expect(() => secondary.city = 'Brno', throwsStateError);
    draft.commit();
    expect(draft.isActive, isFalse);
    expect(live.city, 'Tours');
    expect(document.secondary, isNull);
    expect(() => address.city, throwsStateError);
    expect(() => draft.commit(), throwsStateError);
    expect(() => draft.rollback(), throwsStateError);
  });

  test('setters own their input and snapshots survive commits and disposal',
      () {
    final bytes = _note.toFleece();
    final doc = NoteRecord(bytes);
    bytes.fillRange(0, bytes.length, 0);
    final original = doc.toFleece();
    final words = List.generate(1200, (i) => 'word-$i');
    final tx = doc.beginTransaction();
    tx.tags = words;
    words[0] = 'overwritten';
    expect(tx.tags.first, 'word-0');
    tx.commit();
    expect(doc.tags.length, 1200);
    expect(doc.tags.first, 'word-0');
    doc.tags.add('last word');
    expect(doc.tags.last, 'last word');
    final changed = doc.toFleece();
    doc.toFleece().fillRange(0, changed.length, 0);
    expect(doc.toFleece(), changed);
    expect(NoteRecord(original).toModel().tags, isEmpty);
    final next = doc.beginTransaction();
    next.title = 'abandoned';
    doc.dispose();
    doc.dispose();
    expect(next.isActive, isFalse);
    expect(() => next.commit(), throwsStateError);
    expect(() => next.title, throwsStateError);
    expect(() => doc.title, throwsStateError);
    expect(() => doc.toFleece(), throwsStateError);
    expect(NoteRecord(changed).toModel().title, 'Field notes');
  });

  test('sync and async transactions release the writer and roll back errors',
      () async {
    final doc = NoteRecord(_note.toFleece());
    addTearDown(doc.dispose);
    final original = doc.toFleece();
    expect(
        () => doc.transaction<void>((d) {
              d.title = 'partial';
              d.address.city = String.fromCharCode(0xd800);
            }),
        throwsArgumentError);
    expect(doc.toFleece(), original);
    final waiting = Completer<void>();
    final result = doc.transaction<int>((d) async {
      d.visits = 1;
      await waiting.future;
      return ++d.visits;
    });
    expect(doc.visits, 0);
    expect(() => doc.transaction<void>((d) => d.visits++), throwsStateError);
    waiting.complete();
    expect(await result, 2);
    expect(doc.visits, 2);
    final saved = doc.toFleece();
    await expectLater(doc.transaction<void>((d) async {
      d.visits = 44;
      await Future<void>.value();
      throw StateError('rollback');
    }), throwsStateError);
    expect(doc.toFleece(), saved);
    final tx = doc.beginTransaction();
    tx.visits = 80;
    tx.rollback();
    expect(doc.toFleece(), saved);
  });

  test('only the callback owner can publish or close a managed draft',
      () async {
    final doc = NoteRecord(_note.toFleece());
    addTearDown(doc.dispose);
    final original = doc.toFleece();
    expect(
        () => doc.transaction<void>((d) {
              d.title = 'early';
              d.address.commit();
            }),
        throwsStateError);
    expect(doc.toFleece(), original);
    await expectLater(doc.transaction<void>((d) async {
      d.tags.add('partial');
      await Future<void>.value();
      d.commit();
    }), throwsStateError);
    expect(doc.toFleece(), original);
    doc.transaction<void>((d) {
      d.title = 'complete';
      expect(d.dispose, throwsStateError);
      expect(d.rollback, throwsStateError);
      expect(doc.title, _note.title);
    });
    expect(doc.title, 'complete');
  });

  test(
      'commits compact inherited documents and preserve unknown fields and shared keys',
      () {
    final keys = SharedKeys();
    final unknown = FleeceInt.u64(BigInt.parse('18446744073709551615'));
    final fields = {'city': 'Lyon', 'postcode': '69000', 'extra': unknown};
    final base = encode({...fields, 'discard': 'x' * 4096}, sharedKeys: keys);
    final tail = appendDelta(base, fields, sharedKeys: keys);
    final history = Uint8List.fromList([...base, ...tail]);
    final external =
        appendDelta(base, fields, external: true, sharedKeys: keys);
    final doc = AddressRecord(history, sharedKeys: keys);
    final split = AddressRecord(external, base: base, sharedKeys: keys);
    addTearDown(doc.dispose);
    addTearDown(split.dispose);
    final savedKeys = SharedKeys.fromState(keys.toState());
    keys.truncate(0);
    expect(SharedKeys.fromState(doc.sharedKeyState!), savedKeys);
    doc.transaction<void>((_) {});
    expect(doc.toFleece().length, lessThan(200));
    expect(doc.toFleece(), split.toFleece());
    for (var i = 0; i < 10; i++) {
      doc.transaction<void>((d) => d.city = 'City-$i');
    }
    expect(doc.toFleece().length, lessThan(200));
    final result = decode(doc.toFleece(), sharedKeys: savedKeys) as Map;
    expect(result, {...fields, 'city': 'City-9'});
    expect(doc.toFleece(), compact(Doc(doc.toFleece(), sharedKeys: savedKeys)));
  });
}
