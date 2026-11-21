import 'dart:convert';
import 'dart:typed_data';
import 'package:fleece/fleece.dart';
import 'package:test/test.dart';

const bold = {'bold': true}, link = {'link': 'x'};
Uint8List textParts(Object parts) => (Encoder()
      ..beginExt(ExtKind.text)
      ..writeValue(parts))
    .finish();
Uint8List marked(String s, List<int> m, List<Object?> sets) =>
    textParts([s, Uint8List.fromList(m), ...sets]);
void main() {
  test('a delta goes in and comes out', () {
    final t =
        FleeceText.fromRuns([('Hello ', null), ('world', bold), ('!', null)]);
    expect(t.text, 'Hello world!');
    expect(t.isPlain, isFalse);
    expect(t.marks.map((m) => (m.start, m.end)), [(6, 11)]);
    expect(t.runs.map((r) => r.$1), ['Hello ', 'world', '!']);
    expect(t.runs.elementAt(1).$2, bold);
    expect(FleeceText.plain('no marks').runs.single, ('no marks', null));
    expect(FleeceText.plain('').runs, isEmpty);
  });
  test('equivalent descriptions of text normalize to one representation', () {
    final wanted = FleeceText.withMarks('abcd', [const TextMark(0, 2, bold)]);
    expect(
        FleeceText.fromRuns(
            [('a', bold), ('', link), ('b', bold), ('c', {}), ('d', null)]),
        wanted);
    expect(
        FleeceText.withMarks(
            'abcd', [const TextMark(0, 1, bold), const TextMark(1, 2, bold)]),
        wanted);
    expect(
        FleeceText.fromRuns([
          ('a', {'indent': const FleeceFloat64(0.0)}),
          ('b', {'indent': const FleeceFloat64(-0.0)})
        ]).marks.length,
        1);
    expect(FleeceText.fromRuns([('a', bold), ('b', link)]).marks.length, 2);
  });
  test('out of place marks are refused', () {
    for (final (s, m) in <(String, List<TextMark>)>[
      ('abc', [const TextMark(2, 4, bold)]),
      ('éa', [const TextMark(1, 3, bold)]),
      ('abc', [const TextMark(0, 2, bold), const TextMark(1, 3, link)]),
      ('abc', [const TextMark(2, 3, bold), const TextMark(0, 1, link)]),
      ('abc', [const TextMark(1, 1, bold)]),
      ('abc', [const TextMark(0, 1, {})])
    ]) {
      expect(() => FleeceText.withMarks(s, m), throwsArgumentError);
    }
    expect(
        FleeceText.withMarks(
                'éa', [const TextMark(0, 2, bold), const TextMark(2, 3, link)])
            .marks
            .length,
        2);
  });
  test('text and attributes are read from their slots', () {
    final t = FleeceText.fromRuns(
        [('Tintin', link), (' and ', null), ('Milou', bold)]);
    final bytes = encode({'title': t, 'pages': 62}),
        dict = Doc(bytes).root.asDict!;
    final ref = dict['title']!, view = ref.asText!;
    expect(ref.asString, isNull);
    expect(dict['pages']!.asText, isNull);
    expect(view.text, t.text);
    expect(view.marks.map((m) => (m.start, m.end)), [(0, 6), (11, 16)]);
    expect(view.marks.last.attributes['bold']!.asBool, isTrue);
    expect(view.runs.map((r) => (r.$1, r.$2 != null)),
        [('Tintin', true), (' and ', false), ('Milou', true)]);
    expect(view.utf8Bytes.offsetInBytes, greaterThan(0));
    expect(view.utf8Bytes.buffer.lengthInBytes, bytes.buffer.lengthInBytes);
    final plain = Doc(encode(FleeceText.plain('plain'))).root.asText!;
    expect(plain.isPlain, isTrue);
    expect(plain.runs.single, ('plain', null));
    expect(plain.marks, isEmpty);
  });
  test('a set of attributes is written once', () {
    final t = FleeceText.fromRuns(List.generate(
        2000,
        (i) => i.isOdd
            ? (' and then ', null)
            : ('word', i % 4 == 0 ? bold : {'italic': true})));
    final bytes = encode(t);
    expect(t.marks.length, 1000);
    expect(bytes.length - t.text.length, lessThan(3064));
    expect(decode(bytes), t);
  });
  test('invalid text payloads and nonminimal marks are refused', () {
    final good = marked('abcdef', [1, 2, 0], [bold]);
    expect(decode(good),
        FleeceText.withMarks('abcdef', [const TextMark(1, 3, bold)]));
    final bad = [
      for (final m in [
        [5, 2, 0],
        [1, 0, 0],
        [1, 2, 1],
        [0, 1, 0, 0, 1, 0],
        [1, 2],
        [0x81, 0, 1, 0],
        [...List.filled(9, 255), 127, 1, 0],
        <int>[]
      ])
        marked('abcdef', m, [bold]),
      marked('éa', [1, 1, 0], [bold]),
      for (final sets in [
        <Object?>[{}],
        <Object?>[1],
        <Object?>[bold, null],
        <Object?>[]
      ])
        marked('abcdef', [1, 2, 0], sets),
      textParts([1]),
      textParts([]),
      textParts('abcdef')
    ];
    for (final bytes in bad) {
      expect(
          () => Doc(bytes),
          throwsA(isA<DecodeError>()
              .having((e) => e.code, 'code', DecodeErrorCode.badPayload)));
      final root = Doc.trusted(bytes).root;
      expect(root.read, throwsFormatException);
      final t = root.asText;
      if (t != null)
        expect(t.runs.fold<int>(0, (n, r) => n + utf8.encode(r.$1).length),
            lessThanOrEqualTo(t.utf8Bytes.length));
    }
    expect(decode(marked('abcdef', [0, 1, 0, 0, 1, 1], [bold, bold])),
        FleeceText.withMarks('abcdef', [const TextMark(0, 2, bold)]));
  });
  test('text index key equals its plain string', () {
    expect(encodeKey(FleeceText.fromRuns([('Mil', bold), ('ou', null)])),
        encodeKey('Milou'));
    expect(encodeKey(FleeceText.plain('')), encodeKey(''));
  });
  test('many marks refer to one large dictionary', () {
    final attrs = {for (var i = 0; i < 50; i++) 'field$i': i};
    final t = FleeceText.fromRuns(
        List.generate(10000, (i) => ('ab', i.isEven ? attrs : null)));
    final bytes = encode(t);
    expect(t.marks.length, 5000);
    expect(
        Doc(bytes)
            .root
            .asText!
            .marks
            .map((m) => m.attributes['field49']!.position)
            .toSet(),
        hasLength(1));
    expect(decode(bytes), t);
  });
  test('text referring to itself ends every read', () {
    final b = Uint8List.fromList([49, 26, 96, 1, 128, 2, 128, 3]),
        d = Doc.trusted(b);
    expect(d.validate, throwsFormatException);
    expect(d.root.asText, isNull);
    expect(d.root.read, throwsFormatException);
    expect(() => Encoder().writeCopy(d.root), throwsA(isA<EncodeError>()));
    expect(dump(d), isNotEmpty);
    expect(
        () => fromRef(d.root, FleeceAdapter<Object?>((v) => v, (r) => r.value)),
        throwsFormatException);
    expect(
        () => fromRef(d.root, FleeceAdapter<String>((v) => v, (r) => r.string)),
        throwsFormatException);
  });
  test('text is a delta in JSON and dollar attribute names are escaped', () {
    final t = FleeceText.fromRuns([
      ('Hello ', null),
      ('world', {r'$size': 2})
    ]);
    final wanted = {
      r'$text': [
        {'insert': 'Hello '},
        {
          'insert': 'world',
          'attributes': {r'$$size': 2}
        }
      ]
    };
    expect(toJson(t), wanted);
    expect(fromJson(wanted), t);
    expect(fromJson({r'$text': []}), FleeceText.plain(''));
    for (final bad in [
      'Hello',
      [
        {'attributes': bold}
      ],
      [
        {'insert': 'a', 'attributes': 1}
      ],
      [
        {'insert': 'a', 'retain': 1}
      ]
    ]) expect(() => fromJson({r'$text': bad}), throwsFormatException);
  });
  test('v1 marks use multibyte gaps and lengths', () {
    final t = FleeceText.withMarks('x' * 400, [const TextMark(200, 400, bold)]);
    final doc = Doc(encode(t));
    expect(doc.root.payload!.asArray![1].asData, [200, 1, 200, 1, 0]);
    expect(doc.root.read(), t);
  });
}
