import 'dart:math';
import 'dart:typed_data';
import 'package:fleece/fleece.dart';
import 'package:test/test.dart';

final class Samples {
  Samples(int seed) : r = Random(seed);
  final Random r;
  String text() => [
        '',
        'abc',
        'é🐾',
        '\u0000',
        r'$field',
        '犬',
        '\uFEFF',
        'a.b'
      ][r.nextInt(8)];
  Object? value([int depth = 0]) {
    final choice = r.nextInt(depth < 3 ? 31 : 25), n = r.nextInt(201) - 100;
    switch (choice) {
      case 0:
        return null;
      case 1:
        return const FleeceNone();
      case 2:
        return r.nextBool();
      case 3:
        return n;
      case 4:
        return FleeceFloat64(n * 1.25);
      case 5:
        return FleeceFloat32(n / 5);
      case 6:
        return FleeceFloat16.fromBits(r.nextInt(0x7c00));
      case 7:
        return FleeceInt.u64((BigInt.one << 63) + BigInt.from(n + 100));
      case 8:
        return FleeceInt.i16(n);
      case 9:
        return text();
      case 10:
        return Uint8List.fromList(
            List.generate(r.nextInt(8), (_) => r.nextInt(256)));
      case 11:
        return FleeceUuid(
            Uint8List.fromList(List.generate(16, (_) => r.nextInt(256))));
      case 12:
        return FleeceDecimal(BigInt.from(n.abs()), r.nextInt(29),
            negative: n < 0);
      case 13:
        return FleeceBigDecimal(
            BigInt.from(n) << r.nextInt(120), r.nextInt(36));
      case 14:
        return FleeceDate(n * 130001);
      case 15:
        return FleeceTime(r.nextInt(999999999));
      case 16:
        return FleeceSeconds.datetime(n * 86400, r.nextInt(1000000000));
      case 17:
        return FleeceSeconds.timestamp(n * 86400, r.nextInt(1000000000));
      case 18:
        return FleeceSeconds.duration(n.abs(), r.nextInt(1000000000));
      case 19:
        return FleeceInterval(n, -n, n);
      case 20:
        return FleeceTable(text());
      case 21:
        return FleeceRegex(text());
      case 22:
        return FleeceFile(text(), text());
      case 23:
        return FleeceVector.quantizedF16(
            List.generate(r.nextInt(8), (_) => r.nextDouble() - 0.5));
      case 24:
        return FleeceGeometry.collection(
            [FleeceGeometry.point(n.toDouble(), -0.5)]);
      case 25:
        return List.generate(r.nextInt(5), (_) => value(depth + 1));
      case 26:
        return {for (var i = 0; i < 4; i++) text(): value(depth + 1)};
      case 27:
        return FleeceSet(List.generate(r.nextInt(4), (_) => value(depth + 1)));
      case 28:
        return FleeceRange(FleeceBound.included(value(depth + 1)),
            FleeceBound.excluded(value(depth + 1)));
      case 29:
        return FleeceRecordId(text(), [value(depth + 1)]);
      default:
        return rich(depth + 1);
    }
  }

  FleeceText rich([int depth = 1]) => FleeceText.fromRuns(List.generate(
      r.nextInt(8),
      (_) => (text(), r.nextBool() ? null : {'a': value(depth)})));
}

int order<T>(List<T> a, List<T> b, int Function(T, T) compare) {
  for (var i = 0; i < min(a.length, b.length); i++) {
    final c = compare(a[i], b[i]);
    if (c != 0) return c.sign;
  }
  return a.length.compareTo(b.length);
}

int keyOrder(Object? a, Object? b) =>
    order(encodeKey(a), encodeKey(b), (a, b) => a.compareTo(b));
void readEverything(Uint8List b) {
  final doc = Doc.trusted(b);
  var valid = true;
  try {
    doc.validate();
  } on DecodeError {
    valid = false;
  }
  if (valid) expect(encode(doc.root.read()), isNotEmpty);
  try {
    doc.root.read();
  } on FormatException {}
  dump(doc);
  doc.liveBytes;
  KeyPath.parse('a[0].b[-1]').eval(doc.root);
  doc.root.item;
  doc.root.asText?.runs.length;
  doc.root.asGeometry;
  doc.root.asVector;
  try {
    (Encoder()..writeCopy(doc.root)).finish();
  } on EncodeError {}
  for (final a in [
    FleeceAdapter<Object?>((v) => v, (r) => r.value),
    FleeceAdapter<Object?>((v) => v, (r) => r.any),
  ]) {
    try {
      fromRef(doc.root, a);
    } on SerdeError {}
  }
  const nested = Kind.either([Kind.number, Kind.named('nested')]);
  nested.conformsWith(doc.root, {'nested': const Kind.array(nested)});
}

void main() {
  test(
      'generated values round trip through every owned and shared-key entry point',
      () {
    final samples = Samples(12);
    for (var i = 0; i < 350; i++) {
      final v = samples.value(), b = encode(v), keys = SharedKeys();
      expect(b.length.isEven, isTrue);
      expect(encode(decode(b)), b);
      expect(encodeKey(decode(b)), encodeKey(v));
      final shared = encode(v, sharedKeys: keys),
          doc = Doc.trusted(shared, sharedKeys: keys);
      doc.validate();
      expect(encode(doc.root.read()), b);
    }
  });
  test('a generated text is its runs wherever it is read', () {
    final samples = Samples(19);
    for (var i = 0; i < 180; i++) {
      final t = samples.rich(), v = Doc(encode(t)).root.asText!;
      expect(FleeceText.fromRuns(t.runs), t);
      expect(FleeceText.withMarks(t.text, t.marks), t);
      expect(t.runs.map((r) => r.$1).join(), t.text);
      final runs = v.runs.map((r) => (
            r.$1,
            r.$2 == null
                ? null
                : {for (final e in r.$2!.entries) e.key: e.value.read()}
          ));
      expect(FleeceText.fromRuns(runs), t);
    }
  });
  test('path updates have the same effect as edits of the owned record', () {
    final s = Samples(721);
    for (var sample = 0; sample < 28; sample++) {
      final m = {
        for (var i = 0; i < 20 + s.r.nextInt(35); i++) 'k$i': s.value()
      };
      var b = encode(m);
      for (var t = 0; t < 8; t++) {
        final p = Patch();
        for (var j = 0; j < 3; j++) {
          final key = 'k' + s.r.nextInt(55).toString(),
              path = KeyPath.parse(key);
          if (s.r.nextInt(4) == 0) {
            p.remove(path);
            m.remove(key);
          } else {
            final v = s.value();
            p.set(path, v);
            m[key] = v;
          }
        }
        b = update(Doc(b), p);
        expect(encode(decode(b)), encode(m));
        expect(Doc(b).liveBytes, b.length);
      }
    }
  });
  test('arbitrary bytes and mutations of generated documents end every read',
      () {
    final s = Samples(532);
    for (var i = 0; i < 700; i++) {
      readEverything(Uint8List.fromList(
          List.generate(s.r.nextInt(200), (_) => s.r.nextInt(256))));
      final b = encode(s.value());
      for (var j = 0; j < 1 + i % 3; j++) {
        b[s.r.nextInt(b.length)] = s.r.nextInt(256);
      }
      readEverything(b);
    }
  });
  test('structural and appended deltas transform generated values', () {
    final s = Samples(987);
    for (var i = 0; i < 320; i++) {
      final old = s.value(),
          v = i % 9 == 0 ? old : s.value(),
          base = encode(old),
          next = encode(v);
      final d = diff(old, v);
      if (d == null) {
        expect(encode(old), next);
      } else {
        expect(encode(apply(old, d)), next);
        expect(encode(apply(old, decode(encode(d.value)))), next);
      }
      final appended = Uint8List.fromList([...base, ...appendDelta(base, v)]);
      expect(encode(decode(appended)), next);
      expect(encode(decode(appendDelta(base, v, external: true), base: base)),
          next);
    }
  });
  test(
      'many appended changes keep indexed lookup and compact to the live values',
      () {
    final s = Samples(873);
    for (var i = 0; i < 24; i++) {
      final keys = i.isEven ? SharedKeys() : null;
      final m = {for (var j = 0; j < 32; j++) 'k$j': s.value()};
      var b = encode(m, sharedKeys: keys);
      for (var t = 0; t < 7; t++) {
        for (var n = 0; n < 3; n++) {
          final k = 'k' + s.r.nextInt(64).toString();
          if (s.r.nextInt(4) == 0) {
            m.remove(k);
          } else {
            m[k] = s.value();
          }
        }
        final old = Doc(b,
            sharedKeys:
                keys == null ? null : SharedKeys.fromState(keys.toState()));
        final delta = (Encoder(base: b, sharedKeys: keys)
              ..writeChanged(old.root, m))
            .finish();
        b = Uint8List.fromList([...b, ...delta]);
        final d = Doc(b, sharedKeys: keys).root.asDict!;
        expect(d.length, m.length);
        for (final e in m.entries) {
          expect(encode(d[e.key]!.read()), encode(e.value));
        }
      }
      final doc = Doc(b, sharedKeys: keys), c = compact(doc);
      expect(doc.liveBytes, lessThanOrEqualTo(b.length));
      expect(c.length, lessThanOrEqualTo(b.length));
      final fresh = Doc(c, sharedKeys: keys);
      expect(fresh.liveBytes, c.length);
      expect(encode(fresh.root.read()), encode(m));
    }
  });
  test('typed JSON round trips through objects, text and binary documents', () {
    final s = Samples(200);
    for (var i = 0; i < 350; i++) {
      final v = s.value(), b = encode(v);
      expect(encode(fromJson(toJson(v))), b);
      expect(jsonToFleece(fleeceToJson(b)), b);
    }
  });
  test('a small change to a large dictionary makes a 30-byte delta', () {
    final inner = {
      for (var i = 0; i < 200; i++)
        'field' + i.toString().padLeft(3, '0'): 'the value of $i'
    };
    final old = {...inner, 'inner': inner},
        next = {
          ...inner,
          'inner': {...inner, 'field007': 'changed'}
        },
        base = encode(old);
    final d = appendDelta(base, next);
    expect(d.length, 30);
    final b = Uint8List.fromList([...base, ...d]),
        doc = Doc(b),
        fields = doc.root.asDict!['inner']!.asDict!;
    expect(fields.length, 200);
    expect(fields['field007']!.asString, 'changed');
    expect(fields['field008']!.asString, 'the value of 8');
    expect(doc.liveBytes, lessThan(b.length));
    expect(compact(doc).length, encode(next).length);
    expect(diff(old, next)!.value, {
      'inner': {'field007': 'changed'}
    });
  });
  test('sortable keys of non-finite numbers and different value types', () {
    final items = [
      double.negativeInfinity,
      -double.maxFinite,
      -(BigInt.one << 63),
      -double.minPositive,
      0,
      double.minPositive,
      FleeceInt.u64((BigInt.one << 64) - BigInt.one),
      double.maxFinite,
      double.infinity,
      double.nan
    ];
    for (var i = 1; i < items.length; i++)
      expect(keyOrder(items[i - 1], items[i]), -1);
    expect(
        encodeKey(double.infinity), encodeKey(FleeceFloat32(double.infinity)));
    final types = [
      const FleeceNone(),
      null,
      false,
      true,
      -1,
      0.5,
      '',
      'a',
      'a\u0000',
      'ab',
      'b',
      FleeceSeconds.duration(1, 0),
      FleeceSeconds.datetime(-1, 999999999),
      FleeceSeconds.datetime(0, 0),
      FleeceUuid(Uint8List(16)),
      [],
      [1],
      [1, const FleeceNone()],
      [2],
      FleeceSet([]),
      {},
      {'a': 1},
      {'a': 1, 'b': 0},
      {'a': 2},
      {'b': 0},
      FleeceGeometry.point(0, 0),
      Uint8List(1),
      const FleeceTable('t'),
      const FleeceFile('b', 'k'),
      const FleeceRange(FleeceBound.unbounded(), FleeceBound.unbounded()),
      const FleeceRegex('r'),
      FleeceDate(-1),
      FleeceDate(0),
      FleeceTime(0),
      FleeceSeconds.timestamp(0, 0),
      FleeceInterval(0, 0, 0),
      FleeceVector.f32([])
    ];
    for (var i = 1; i < types.length; i++)
      expect(keyOrder(types[i - 1], types[i]), -1);
    expect(encodeKey(FleeceSet([2, 1, 2])), encodeKey(FleeceSet([1, 2])));
    expect(encodeKey(FleeceInterval(1, 0, 0)),
        encodeKey(FleeceInterval(0, 30, 0)));
  });
  test('bytes and lists sort lexicographically including embedded zeros', () {
    final r = Random(169);
    List<Uint8List> make() => List.generate(
        r.nextInt(5),
        (_) => Uint8List.fromList(
            List.generate(r.nextInt(6), (_) => r.nextInt(8))));
    int cmp(int a, int b) => a.compareTo(b);
    for (var i = 0; i < 300; i++) {
      final a = make(), b = make();
      expect(keyOrder(a, b), order(a, b, (a, b) => order(a, b, cmp)));
      final x = Uint8List.fromList(a.expand((v) => v).toList()),
          y = Uint8List.fromList(b.expand((v) => v).toList());
      expect(keyOrder(x, y), order(x, y, cmp));
    }
  });
  test('numbers are laid out as documented, all widths share the exact key',
      () {
    const key = [4, 3, 128, 0, 0, 0, 0, 0, 0, 0, 2, 6, 0];
    for (final v in [
      1.5,
      FleeceFloat32(1.5),
      FleeceDecimal.parse('1.50'),
      FleeceBigDecimal.parse('1.5000')
    ]) expect(encodeKey(v), key);
    expect(encodeKey(-1.5),
        [4, 1, 127, 255, 255, 255, 255, 255, 255, 255, 253, 249, 255]);
    expect(encodeKey(0), [4, 2]);
    expect(encodeKey(const FleeceFloat64(-0.0)), [4, 2]);
    expect(encodeKey(100), [4, 3, 128, 0, 0, 0, 0, 0, 0, 2, 2, 0]);
    expect(keyOrder(0.1, FleeceDecimal.parse('0.1')), 1);
    expect(keyOrder(0.5, FleeceDecimal.parse('0.5')), 0);
    expect(encodeKey(double.minPositive),
        encodeKey(FleeceBigDecimal(BigInt.from(5).pow(1074), 1074)));
    final out = BytesBuilder();
    encodeKeyInto('a', out);
    encodeKeyInto(2, out);
    expect(out.takeBytes(), [...encodeKey('a'), ...encodeKey(2)]);
  });
}
