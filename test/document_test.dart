import 'dart:typed_data';
import 'package:fleece/fleece.dart';
import 'package:test/test.dart';
import 'format_test.dart' show hex;
import 'limits_test.dart' show held, refused;

void main() {
  test(
      'record keys are signed i64, strings, UUIDs, arrays, objects or key ranges',
      () {
    final min = -(BigInt.one << 63);
    final bounds = RecordIdKeyRange(FleeceBound.included(RecordIdKey(min)),
        const FleeceBound.excluded('z'));
    expect(encode(FleeceRecordId('dog', bounds)),
        encode(FleeceRecordId('dog', bounds.toRange())));
    for (final key in <Object>[
      min,
      -min - BigInt.one,
      'id',
      FleeceUuid(Uint8List(16)),
      [true],
      {'value': null},
      FleeceRange(FleeceBound.included(min), const FleeceBound.unbounded()),
    ]) {
      final tagged = RecordIdKey.tryFrom(key)!;
      expect(encode(FleeceRecordId('t', tagged)),
          encode(FleeceRecordId('t', key)));
      expect(RecordIdKey(tagged.value), tagged);
    }
    for (final k in [
      null,
      FleeceInt.u8(1),
      -min,
      Uint8List(0),
      {2: 1},
      const FleeceRange(FleeceBound.included(null), FleeceBound.unbounded())
    ]) {
      expect(RecordIdKey.tryFrom(k), isNull);
    }
  });
  test('delta errors preserve the cause and shared key state compares by value',
      () {
    final keys = SharedKeys()..add('abc');
    expect(SharedKeys.fromState(keys.toState()), keys);
    expect(KeyPath.parse(r'$.a[-1]'), KeyPath.parse('a[-1]'));
    expect(
        () => appendDelta(Uint8List(1), 'a'),
        throwsA(isA<DeltaError>()
            .having((e) => e.code, 'code', DeltaErrorCode.decode)
            .having((e) => e.cause, 'cause', isA<DecodeError>())));
    final root = Doc.trusted(Uint8List.fromList([0x81, 0]));
    expect(
        () => extract(root, KeyPath.parse('')),
        throwsA(isA<DeltaError>()
            .having((e) => e.code, 'code', DeltaErrorCode.encode)));
    expect(extensionName(26), 'text');
    expect(extensionName(27), isNull);
  });
  test(
      'inherited dictionary shadows an entry, removes another, keeps lookup and count',
      () {
    final b = hex(
            '70 02 41 61 00 01 41 62 00 02 70 03 08 00 80 07 41 62 3c 00 41 63 00 03 80 07'),
        dict = Doc(b).root.asDict!;
    expect(dict['a']!.asInt, 1);
    expect(dict['b'], isNull);
    expect(dict['c']!.asInt, 3);
    expect(dict.length, 2);
    expect(decode(b), {'a': 1, 'c': 3});
  });
  test('large collections go wide and far roots use a trampoline', () {
    final v = List.generate(
            3000, (i) => 'a string number ' + i.toString().padLeft(6, '0')),
        b = encode(v),
        r = Doc(b).root;
    expect(b[r.position] & 8, 8);
    expect((r.item.value as ArrayRef).length, 3000);
    expect(r.asArray![2999].asString, v.last);
    expect(decode(b), v);
    final arr = List.generate(40000, (i) => i % 100), far = encode(arr);
    expect(far.sublist(far.length - 2), [128, 2]);
    expect(Doc(far).liveBytes, far.length);
    expect(decode(far), arr);
  });
  test('dictionary layouts use the current keys and values on every visit', () {
    final large =
        List.generate(35, (i) => 'field-${i.toString().padLeft(2, '0')}');
    const short = 'alpha', multibyte = 'длинныйключ';
    final orders = [
      [short, multibyte, ''],
      [short, multibyte, ''],
      ['', multibyte, short],
      ['', 'beta', short],
      large.reversed.toList(),
      [short, multibyte, ''],
    ];
    final rows = [
      for (var i = 0; i < orders.length; i++)
        Map<String, Object?>.identity()
          ..addEntries(orders[i].map((key) =>
              MapEntry(String.fromCharCodes(key.codeUnits), 'row $i: $key')))
    ];
    for (final shared in [false, true]) {
      final keys = shared ? (SharedKeys()..add('beta')) : null;
      final otherKeys = shared ? (SharedKeys()..add('beta')) : null;
      final expected = Encoder(sharedKeys: otherKeys)..beginArray();
      for (final row in rows) {
        expected.beginDict();
        for (final key in row.keys.toList()..sort()) {
          expected
            ..writeKey(key)
            ..writeValue(row[key]);
        }
        expected.endDict();
      }
      final bytes = encode(rows, sharedKeys: keys);
      expect(bytes, (expected..endArray()).finish());
      expect(keys, otherKeys);
      expect(decode(bytes, sharedKeys: keys),
          [for (final row in rows) Map.of(row)]);
    }
    final a = String.fromCharCodes(short.codeUnits),
        b = String.fromCharCodes(short.codeUnits);
    if (!identical(a, b)) {
      for (final extras in [<String>[], large]) {
        final duplicates = Map<String, int>.identity()
          ..[a] = 1
          ..[b] = 2
          ..addEntries(extras.map((key) => MapEntry(key, 3)));
        expect(
            () => encode(duplicates),
            throwsA(isA<EncodeError>()
                .having((e) => e.code, 'code', EncodeErrorCode.duplicateKey)));
      }
    }
  });
  test('large dictionaries with a shared prefix sort by Unicode scalar value',
      () {
    final sorted = [
      for (final scalar in [0xd7ff, 0xe000, 0xffff, 0x10000, 0x10ffff])
        for (var suffix = 0; suffix < 8; suffix++)
          'field-${String.fromCharCode(scalar)}$suffix',
    ];
    final fields = {for (final key in sorted.reversed) key: key};
    final writer = Encoder()..beginDict();
    for (final key in sorted) {
      writer
        ..writeKey(key)
        ..writeString(key);
    }
    expect(encode(fields), (writer..endDict()).finish());
  });
  test('short strings keep their first body through collisions and growth', () {
    // These names have the same low hash bits on the current backend.
    final buckets = List.generate(64, (_) => <String>[]);
    for (var i = 0; i < 48 * buckets.length; i++) {
      final key = 'key$i';
      buckets[key.hashCode & 63].add(key);
    }
    final names = buckets.firstWhere((b) => b.length >= 48).take(48).toList();
    const short = '🙂🙂🙂éx', long = '🙂🙂🙂éxy'; // 15 and 16 UTF-8 bytes
    final rows = [
      ...names,
      short,
      long,
      for (final name in names.reversed) String.fromCharCodes(name.codeUnits),
      short,
      long,
    ];
    final array = Doc(encode(rows)).root.asArray!;
    expect(array.map((v) => v.asString), rows);
    for (var i = 0; i < names.length; i++) {
      expect(array[i].position, array[rows.length - 3 - i].position);
    }
    expect(array[names.length].position, array[rows.length - 2].position);
    expect(array[names.length + 1].position,
        isNot(array[rows.length - 1].position));
  });
  test('inherited dictionaries keep the parent ahead of reordered shared keys',
      () {
    final keys = SharedKeys()
      ..add('z')
      ..add('a')
      ..add('b');
    final old = {
      'a': 1,
      'b': 2,
      'z': 3,
      for (var i = 0; i < 10; i++) 'field$i': i
    };
    final base = encode(old, sharedKeys: keys);
    final next = {...old, 'a': 11, 'z': 12}..remove('b');
    final parent = Doc(base, sharedKeys: keys).root.position;
    for (final external in [false, true]) {
      final delta =
          appendDelta(base, next, external: external, sharedKeys: keys);
      final units = (base.length + 4 - parent) ~/ 2;
      expect(delta, [
        ...hex('70 04 08 00'),
        (external ? 0xc0 : 0x80) | (units >> 8),
        units & 255,
        ...hex('00 00 00 0c 00 01 00 0b 00 02 3c 00 80 09')
      ]);
      final doc = external
          ? Doc(delta, base: base, sharedKeys: keys)
          : Doc(Uint8List.fromList([...base, ...delta]), sharedKeys: keys);
      expect(doc.root.read(), next);
    }
  });
  test('an external pointer widens the preceding inline slot at the boundary',
      () {
    for (final (length, expected) in [
      (32762, '60 02 00 05 ff ff 80 03'),
      (32764, '68 02 00 05 00 00 c0 00 40 01 80 05'),
    ]) {
      final base = Uint8List(length)
        ..[0] = 0x42
        ..[1] = 97
        ..[2] = 98;
      final ref = Doc.trusted(base).valueAt(0);
      final bytes = (Encoder(base: base, external: true)
            ..beginArray()
            ..writeInt(5)
            ..writeRef(ref)
            ..endArray())
          .finish();
      expect(bytes, hex(expected));
      expect(decode(bytes, base: base), [5, 'ab']);
    }
  });
  test(
      'wide slots preserve all offset bytes, external flags and inline padding',
      () {
    final base = Uint8List(0x02040608);
    base.setAll(0, hex('42 78 79 00'));
    base.setAll(base.length - 4, hex('42 6f 6b 00'));
    final doc = Doc.trusted(base);
    final far = doc.valueAt(0), near = doc.valueAt(base.length - 4);
    for (final firstIsFar in [true, false]) {
      final writer = Encoder(base: base, external: true)
        ..beginExt(ExtKind.set)
        ..beginArray();
      if (firstIsFar) writer.writeRef(far);
      writer
        ..writeInt(-1)
        ..writeString('lo');
      if (!firstIsFar) writer.writeRef(far);
      final bytes = (writer
            ..writeRef(near)
            ..endArray())
          .finish();
      expect(bytes, [
        ...hex('42 6c 6f 00 31 17 68 04'),
        ...hex(firstIsFar
            ? 'c1 02 03 08 0f ff 00 00 80 00 00 08'
            : '0f ff 00 00 80 00 00 06 c1 02 03 0c'),
        ...hex('c0 00 00 0c 80 0a')
      ]);
      final values = (decode(bytes, base: base) as FleeceSet).members;
      expect(
          values, firstIsFar ? ['xy', -1, 'lo', 'ok'] : [-1, 'lo', 'xy', 'ok']);
    }
  });
  test('a wide parent pointer must have an even byte distance', () {
    final old = {for (var i = 0; i < 12; i++) 'field-$i': i};
    final encoded = encode(old);
    final base = Uint8List(0x10000)..setRange(1, 1 + encoded.length, encoded);
    final parent = Doc.trusted(base).valueAt(1 + Doc(encoded).root.position);
    expect(parent.read(), old);
    final writer = Encoder(base: base, external: true);
    expect(
        () => writer.writeChanged(parent, {...old, 'field-4': -1}),
        throwsA(isA<EncodeError>()
            .having((e) => e.code, 'code', EncodeErrorCode.tooLarge)));
  });
  test('a rejected string leaves the next body and its padding intact', () {
    for (final tagged in [false, true]) {
      Encoder start() {
        final e = Encoder()
          ..beginArray()
          ..writeInt(1);
        if (tagged) e.beginExt(ExtKind.table);
        return e;
      }

      for (final valid in ['', 'a', 'ab', 'prefix-é', '🙂']) {
        final actual = start();
        expect(() => actual.writeString('abcdefghijklmnop\ud800'),
            throwsArgumentError);
        Uint8List finish(Encoder e) => (e
              ..writeString(valid)
              ..writeInt(3000)
              ..endArray())
            .finish();
        expect(finish(actual), finish(start()));
      }
    }
  });
  test('writing can continue at a rejected dictionary or string-array value',
      () {
    const invalid = '\ud800';
    final dict = Encoder();
    expect(() => dict.writeValue({'b': invalid, 'a': 'first'}),
        throwsArgumentError);
    expect(
        (dict
              ..writeString('last')
              ..endDict())
            .finish(),
        encode({'a': 'first', 'b': 'last'}));

    final nested = Encoder();
    expect(
        () => nested.writeValue({
              'a': 1,
              'b': <String>['before', invalid]
            }),
        throwsArgumentError);
    expect(
        (nested
              ..writeString('after')
              ..endArray()
              ..endDict())
            .finish(),
        encode({
          'a': 1,
          'b': ['before', 'after']
        }));
  });
  test('shared keys shrink documents and are needed to read them', () {
    final v = {'first_name': 'Tintin', 'last-name': '', 'not eligible': 1},
        keys = SharedKeys(),
        b = encode(v, sharedKeys: keys);
    expect(keys.keys, ['first_name', 'last-name']);
    expect(b.length, lessThan(encode(v).length));
    expect(() => Doc(b), refused(DecodeErrorCode.missingSharedKey));
    final r = Doc(b, sharedKeys: SharedKeys.fromState(keys.toState())).root;
    expect(r.read(), v);
    expect(r.asDict!['other'], isNull);
  });
  test('encoding calls out of order have distinct failures', () {
    Matcher error(EncodeErrorCode c) =>
        throwsA(isA<EncodeError>().having((e) => e.code, 'code', c));
    final e = Encoder();
    expect(() => e.writeKey('a'), error(EncodeErrorCode.unexpectedKey));
    e.beginDict();
    expect(() => e.writeInt(1), error(EncodeErrorCode.expectedKey));
    expect(e.endArray, error(EncodeErrorCode.unbalanced));
    e.writeKey('a');
    expect(e.endDict, error(EncodeErrorCode.unbalanced));
    expect(() => e.writeKey('b'), error(EncodeErrorCode.unexpectedKey));
    e
      ..writeInt(1)
      ..writeKey('a')
      ..writeInt(2);
    expect(e.endDict, error(EncodeErrorCode.duplicateKey));
    final n = Encoder();
    for (final id in [0, 200])
      expect(() => n.beginExt(id), error(EncodeErrorCode.badExtKind));
    n.writeNull();
    expect(n.writeNull, error(EncodeErrorCode.multipleRoots));
    expect(Encoder().finish, error(EncodeErrorCode.incomplete));
    final deep = Encoder();
    for (var i = 0; i < maxDepth; i++) {
      deep.beginArray();
    }
    expect(deep.beginArray, error(EncodeErrorCode.tooDeep));
  });
  test('malformed documents report their Rust error class and offset', () {
    for (final (s, code, pos) in [
      ('00', DecodeErrorCode.truncated, null),
      ('80 05', DecodeErrorCode.badPointer, 0),
      ('80 00', DecodeErrorCode.badPointer, 0),
      ('45 68 80 01', DecodeErrorCode.malformed, 0),
      ('42 ff fe 00 80 02', DecodeErrorCode.invalidUtf8, 0),
      ('70 02 41 62 00 01 41 61 00 02 80 05', DecodeErrorCode.unsortedKeys, 0),
      ('70 01 30 00 00 01 80 03', DecodeErrorCode.badKey, 0),
      ('31 c8 00 01 80 02', DecodeErrorCode.unknownExt, 0),
      ('31 0d', DecodeErrorCode.badPayload, 0),
      ('31 0d 00 01 80 02', DecodeErrorCode.badPayload, 0),
      ('3c 00', DecodeErrorCode.undefined, 0),
      ('00 01 60 01 c0 02 80 02', DecodeErrorCode.badPointer, 4)
    ]) {
      expect(
          () => Doc(hex(s)),
          throwsA(isA<DecodeError>()
              .having((e) => e.code, 'code', code)
              .having((e) => e.position, 'position', pos)),
          reason: s);
    }
  });
  test(
      'maximum depth across all recursive value families and a 5000-level unchecked document',
      () {
    Object? deep(int n, Object? Function(Object?) wrap) {
      Object? v = 1;
      for (var i = 0; i < n; i++) {
        v = wrap(v);
      }
      return v;
    }

    var g = FleeceGeometry.point(1, 2) as FleeceGeometry;
    for (var i = 0; i < maxDepth ~/ 2 - 1; i++) {
      g = FleeceGeometry.collection([g]);
    }
    final values = [
      deep(maxDepth, (v) => [v]),
      deep(maxDepth, (v) => {'k': v}),
      deep(maxDepth, (v) => FleeceSet([v])),
      deep(
          maxDepth,
          (v) => FleeceRange(
              FleeceBound.included(v), const FleeceBound.unbounded())),
      deep(maxDepth ~/ 2, (v) => FleeceRecordId('t', [v])),
      g,
      deep(
          maxDepth ~/ 2,
          (v) => FleeceText.fromRuns([
                ('marked', {'k': v})
              ]))
    ];
    final bytes = Uint8List.fromList([
          0,
          1,
          for (var i = 0; i < 5000; i++) ...[96, 1, 128, i == 0 ? 2 : 3],
          128,
          2
        ]),
        un = Doc.trusted(bytes);
    expect(un.validate, refused(DecodeErrorCode.tooDeep));
    expect(un.root.read, refused(DecodeErrorCode.tooDeep));
    expect(dump(un), isNotEmpty);
    expect(un.liveBytes, lessThanOrEqualTo(bytes.length));
    expect(() => compact(un), throwsFormatException);
    expect(() => update(un, Patch()), throwsA(anything));
    for (final v in values) {
      final b = encode(v), d = Doc(b);
      expect(encode(d.root.read()), b);
      expect(dump(d), isNotEmpty);
      expect(d.liveBytes, b.length);
      expect(compact(d), b);
      expect(update(d, Patch()), b);
      expect(Kind.any.conforms(d.root), isTrue);
      expect(encodeKey(v), isNotEmpty);
      expect(encode(fromJson(toJson(v))), b);
    }
    for (final v in values.take(3)) {
      expect(() => encode([v]), throwsA(isA<EncodeError>()));
    }
  });
  test('small documents cannot expand to an endless one', () {
    for (final (n, w) in [(10, 16), (5, 16), (20, 2)])
      expect(() => Doc(held(n, w)), refused(DecodeErrorCode.tooManyValues));
    expect(decode(held(1, 2)), [
      ['some string'],
      ['some string']
    ]);
  });
  test('unchecked self-inheritance terminates and logical reads hide the loop',
      () {
    final doc = Doc.trusted(hex('70 01 08 00 80 02 80 03'));
    expect(doc.validate, refused(DecodeErrorCode.tooDeep));
    final dict = doc.root.asDict!;
    expect(dict['name'], isNull);
    expect(dict.length, 0);
    expect(dict.entries, isEmpty);
    expect(doc.root.read(), {});
    expect(Doc.trusted(held(40, 2)).root.read,
        refused(DecodeErrorCode.tooManyValues));
  });
  test('a dictionary does not pay for the fields it hides', () {
    Map<String, Object?> outer(int n) => {
          for (var i = 97; i <= 104; i++) String.fromCharCode(i): 1,
          'i': {
            for (var k = 48; k <= 122; k++) String.fromCharCode(k): k - 48 + n
          }
        };
    var bytes = encode(outer(0));
    for (var change = 1; change < 40; change++) {
      final next = outer(change ~/ 2 * 100);
      if (change.isOdd) (next['i'] as Map)['0'] = change;
      bytes = Uint8List.fromList([...bytes, ...appendDelta(bytes, next)]);
      expect(decode(bytes), next);
    }
  });
  test(
      'every accepted document is decodable, structural checks include payload semantics',
      () {
    for (final (s, id) in [
      ('31 01 06 f8 80 02', 1),
      ('31 0f 1f ff ff ff ff ff ff ff ff 00 80 06', 15),
      ('31 0d 53 01 02 03 80 03', 13),
      ('31 12 00 07 80 02', 18)
    ]) {
      expect(
          () => Doc(hex(s)),
          throwsA(isA<DecodeError>()
              .having((e) => e.kind, 'extension', id)
              .having((e) => e.code, 'code', DecodeErrorCode.badPayload)));
    }
    expect(() => Doc(hex('60 01 3c 00 80 02')),
        refused(DecodeErrorCode.undefined));
    expect(Doc.trusted(hex('3c 00')).root.item.type, ItemType.undefined);
  });
}
