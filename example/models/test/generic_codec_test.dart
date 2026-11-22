import 'dart:typed_data';
import 'package:fleece/fleece.dart';
import 'package:fleece_model_example/note.dart';
import 'package:test/test.dart';
import 'fixtures.dart';

Uint8List _bytes(String hex) => Uint8List.fromList([
  for (int i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

void main() {
  test(
    'a zero-copy custom codec cannot mutate committed or staged storage',
    () {
      final raw = FleeceCodec<ValueRef>(
        (encoder, ref) => encoder.writeCopy(ref),
        (ref) => ref,
      );
      final keys = SharedKeys()..add('value');
      final bytes = encode({'value': 'initial'}, sharedKeys: keys);
      final doc = EnvelopeRecord<ValueRef>(
        bytes,
        codecT: raw,
        sharedKeys: keys,
      );
      addTearDown(doc.dispose);
      void readOnly(ValueRef ref) {
        expect(
          () => ref.doc.bytes[ref.position] = 0x30,
          throwsUnsupportedError,
        );
        expect(
          () => ref.doc.bytes.buffer.asUint8List()[ref.position] = 0x30,
          throwsUnsupportedError,
        );
      }

      final first = doc.value;
      readOnly(first);
      expect(() => first.doc.sharedKeys!.truncate(0), throwsUnsupportedError);
      expect(() => first.doc.sharedKeys!.add('new'), throwsUnsupportedError);
      final draft = doc.beginTransaction();
      draft.value = Doc(encode('pending')).root;
      readOnly(draft.value);
      expect(first.asString, 'initial');
      draft.commit();
      readOnly(doc.value);
      expect(doc.value.asString, 'pending');
      expect(first.asString, 'initial');
      expect(doc.sharedKeyState, keys.toState());
    },
  );

  test(
    'a bound generic honors the destination codec and preserves unknown keys',
    () {
      final asText = FleeceCodec<int>(
        (e, value) => e.writeString(value.toString()),
        (ref) => int.parse(FleeceCodecs.string.read(ref)),
      );
      final numbers = EnvelopeRecord.codec<int>(codecT: FleeceCodecs.integer);
      final strings = EnvelopeRecord.codec<int>(codecT: asText);
      final original = encode({
        'value': 4,
        'history': [null, 7],
        'future': FleeceInt.u32(32),
      });
      // crates/fleece/examples/fleece encode, including an unknown typed u32.
      final expected = _bytes(
        '46667574757265003106002047686973746f72796002300041374576616c7565'
        '70038011800e800d800a800841348007',
      );
      final doc = numbers.open(original);
      addTearDown(doc.dispose);
      final Envelope<int> domain = doc;
      expect(strings.encode(doc), expected);
      expect(doc.toFleece(codecT: asText), expected);
      expect(domain.toFleece(codecT: asText), expected);
      expect(domain.toFleece(codecT: FleeceCodecs.integer), original);
      expect(strings.decode(expected).history, [null, 7]);
      final outer = EnvelopeRecord.codec<Envelope<int>>(
        codecT: numbers,
      ).open(encode({'value': decode(original), 'untouched': true}));
      addTearDown(outer.dispose);
      final outerStrings = EnvelopeRecord.codec<Envelope<int>>(codecT: strings);
      final draft = outer.beginTransaction();
      draft.value = doc;
      draft.history.add(doc);
      expect(
        outerStrings.encode(draft),
        encode({
          'value': decode(expected),
          'history': [decode(expected)],
          'untouched': true,
        }),
      );
      draft.rollback();
      expect(doc.toFleece(), original);
    },
  );

  test(
    'detached models from older documents own their collection defaults',
    () {
      final bytes = encode({'value': 'old'});
      final codec = EnvelopeRecord.codec<String>(codecT: FleeceCodecs.string);
      final doc = codec.open(bytes);
      addTearDown(doc.dispose);
      final first = codec.decode(bytes);
      final second = doc.toModel();
      first.links['added'] = [Uri.parse('/new')];
      first.history.add('new');
      second.history.add(null);
      expect(second.links, isEmpty);
      expect(first.history, ['new']);
      expect(doc.history, isEmpty);
      expect(doc.toFleece(), bytes);
      expect(
        () => codec.decode(encode({'value': 'old', 'history': null})),
        throwsFormatException,
      );
    },
  );

  // Independent output from crates/fleece/examples/fleece encode at 1be207f.
  final uriBytes = _bytes(
    '47686973746f72794f1068747470733a2f2f646172742e64657660023000800b'
    '456c696e6b7344f09f8c8d004f1568747470733a2f2f6578616d706c652e6f72'
    '672f61006002800d30007001801380054576616c75654f1068747470733a2f2f'
    '646172742e646576700380358029802780138011800f8007',
  );
  final before = _bytes(
    '47686973746f727942686900600280033000456c696e6b73452f6c6173746001'
    '80047001417a80044576616c75654568656c6c6f7003801b80168014800d800b80098007',
  );
  final after = _bytes(
    '47686973746f727942686900600280033000456c696e6b7343612e62462f6669'
    '72737400600280053000452f6c617374600180047002800f800a417a80064576'
    '616c75654568656c6c6f700380268021801f800f800b80098007',
  );

  test(
    'custom binary codecs and a named generic constructor match Rust bytes',
    () {
      const uriCodec = UriCodec();
      final format = EnvelopeRecord.codec<Uri>(codecT: uriCodec);
      final uri = Uri.parse('https://dart.dev');
      final model = Envelope<Uri>.stored(
        uri,
        history: [null, uri],
        links: {
          '🌍': [Uri.parse('https://example.org/a'), null],
        },
      );
      expect(format.encode(model), uriBytes);
      final saved = format.decode(uriBytes);
      expect(saved.value, uri);
      expect(saved.history, [null, uri]);
      expect(saved.links, model.links);
      expect(saved.toFleece(codecT: uriCodec), uriBytes);
      saved.history.clear();
      saved.links['🌍']!.removeLast();
      expect(format.decode(uriBytes).links['🌍'], hasLength(2));
      expect(() => format.decode(encode({'value': 9})), throwsFormatException);
      expect(
        AddressRecord.codec.decode(const Address('Riga').toFleece()).city,
        'Riga',
      );

      final record = EnvelopeRecord<String>(
        before,
        codecT: FleeceCodecs.string,
      );
      addTearDown(record.dispose);
      record.transaction<void>((draft) {
        draft.links.putIfAbsent('a.b', () => [Uri.parse('/first')]).add(null);
        expect(draft.toFleece(), after);
      });
      expect(record.toFleece(), after);
      expect(record.toModel().toFleece(codecT: FleeceCodecs.string), after);
      record.links.remove('a.b');
      expect(record.toFleece(), before);
    },
  );

  test(
    'generic bindings keep codec instances, bounds and mutable nested types',
    () {
      final format = LedgerRecord.codec<int>(codecR: FleeceCodecs.integer);
      const dto = Ledger(Envelope.stored(Address('Lyon')), 10);
      final record = LedgerRecord<int>(
        format.encode(dto),
        codecR: FleeceCodecs.integer,
      );
      addTearDown(record.dispose);
      expect(record.balance, 10);
      record.transaction<void>((draft) {
        draft.amount++;
        draft.envelope.value = const Address('Oslo');
        draft.envelope.history.add(const Address('Paris'));
      });
      expect(
        format.decode(record.toFleece()).envelope.history.single!.city,
        'Paris',
      );
      expect(record.envelope.value.city, 'Oslo');
      expect(record.balance, 11);
      final cells = Envelope.stored(
        CounterModel(1),
        history: [CounterModel(2)],
      );
      final counters = EnvelopeRecord<CounterModel>(
        cells.toFleece(codecT: CounterRecord.codec),
        codecT: CounterRecord.codec,
      );
      addTearDown(counters.dispose);
      counters.value.increment();
      counters.history.single!.increment(3);
      expect(counters.toModel().history.single!.count, 5);
      expect(cells.value.count, 1);
      final listCodec = FleeceCodecs.list(FleeceCodecs.integer);
      final listDoc = EnvelopeRecord<List<int>>(
        encode({
          'value': [1],
        }),
        codecT: listCodec,
      );
      addTearDown(listDoc.dispose);
      listDoc.value.add(2);
      expect(listDoc.toModel().value, [1, 2]);
      final nullable = EnvelopeRecord<int?>(
        encode({'value': null}),
        codecT: FleeceCodecs.integer.nullable(),
      );
      addTearDown(nullable.dispose);
      expect(nullable.value, isNull);
      nullable.value = 4;
      expect(nullable.value, 4);
    },
  );
}
