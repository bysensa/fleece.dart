@TestOn('vm || node')
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:fleece/fleece.dart';
import 'package:test/test.dart';
import 'serde_test.dart' show dog, dogAdapter;
import 'reference/fixture_io.dart'
    if (dart.library.js_interop) 'reference/fixture_node.dart';

Uint8List unhex(String s) => Uint8List.fromList([
      for (var i = 0; i < s.length; i += 2)
        int.parse(s.substring(i, i + 2), radix: 16)
    ]);
int compareKeys(Object? a, Object? b) {
  final x = encodeKey(a), y = encodeKey(b);
  for (var i = 0; i < x.length && i < y.length; i++) {
    if (x[i] != y[i]) return x[i].compareTo(y[i]);
  }
  return x.length.compareTo(y.length);
}

void main() {
  late List<List> rows;
  setUpAll(() async {
    rows = (jsonDecode(await readFixture('test/reference/cases.json')) as List)
        .cast<List>();
  });
  void check(String tag, String name, void Function(List) run) {
    test(name, () {
      for (final row in rows.where((r) => r.first == tag)) {
        run(row);
      }
    });
  }

  check('value',
      'Rust proptest values have identical Dart binary, JSON, index keys and live sizes',
      (r) {
    final bytes = unhex(r[1]), v = decode(bytes);
    expect(encode(v), bytes);
    expect(encodeKey(v), unhex(r[3]), reason: r[2]);
    expect(Doc(bytes).liveBytes, r[4]);
    expect(jsonToFleece(r[2]), bytes, reason: r[2]);
    expect(fleeceToJson(bytes), r[2]);
    expect(encode(fromJson(toJson(v))), bytes);
  });
  check('value', 'Address listings match Rust dump', (r) {
    expect(dump(Doc(unhex(r[1]))), r[5]);
  });
  check(
      'surreal',
      'keys sort as surrealdb sorts its values',
      (r) =>
          expect(compareKeys(decode(unhex(r[1])), decode(unhex(r[2]))), r[3]));
  check(
      'ordered',
      'the key of a number is surrealdbs ordered encoding',
      (r) => expect(
          encodeKey(FleeceBigDecimal.parse(r[1])).sublist(1), unhex(r[2])));
  check(
      'table',
      'a table sorts with the records of tables',
      (r) => expect(
          compareKeys(FleeceTable(r[1]), FleeceRecordId(r[2], r[3])), r[4]));
  check(
      'number',
      'keys of numbers sort as the numbers',
      (r) =>
          expect(compareKeys(decode(unhex(r[1])), decode(unhex(r[2]))), r[3]));
  check('decimal', 'decimal is the decimal of rust_decimal', (r) {
    expect(FleeceDecimal.parse(r[1]).toBytes(), unhex(r[2]));
    expect(FleeceDecimal.fromBytes(unhex(r[2])).toString(), r[1]);
  });
  check('bigint', 'the coefficient is the bytes of a bigint', (r) {
    final n = FleeceBigDecimal.fromBytes(unhex(r[1]), r[4]);
    expect(n.coefficient.toString(), r[2]);
    expect(n.coefficientBytes, unhex(r[3]));
    expect(FleeceBigDecimal.parse(n.toString()), n);
  });
  check('half', 'a double is an f16 when half says so', (r) {
    final d = FleeceFloat64.fromBits(BigInt.parse(r[1], radix: 16));
    expect(FleeceFloat16.fromF64(d.value)?.bits, r[2]);
  });
  check('dog', 'application struct is byte-identical to Rust serde', (r) {
    final expected = unhex(r[1]);
    expect(toVec(dog, adapter: dogAdapter), expected);
    expect(fromSlice(expected, dogAdapter).name, dog.name);
  });
  check('seed', 'read target on every upstream fuzz seed', (r) {
    final bytes = unhex(r[1]), d = Doc(bytes), root = d.root;
    final v = root.read();
    final owned = FleeceAdapter<Object?>((v) => v, (r) => r.value);
    expect(encode(v), bytes);
    expect(encode(decode(compact(d))), bytes);
    expect(encode(fromSlice(bytes, owned)), bytes);
    expect(encode(decode(toVec(v))), bytes);
    expect((Encoder()..writeCopy(root)).finish(), compact(d));
    expect(d.liveBytes, lessThanOrEqualTo(bytes.length));
    expect(dump(d), isNotEmpty);
    expect(encodeKey(v), isNotEmpty);
    if (v is FleeceGeometry) expect(geometryFromGeo(root.asGeo!), v);
    if (v is FleeceVector) {
      final vector = root.asVector!, query = List.filled(vector.length, 0.5);
      expect(vector.dot(query), v.dot(query));
      expect(vector.l2Squared(query), v.l2Squared(query));
      expect(vector.cosine(query), v.cosine(query));
      expect(vector.toVector(), v);
      expect(vector.prefix(vector.length ~/ 2)!.length, vector.length ~/ 2);
    }
    if (v is FleeceText) {
      final text = FleeceText.fromRuns(root.asText!.runs.map((r) => (
            r.$1,
            r.$2 == null ? null : {for (final e in r.$2!) e.key: e.value.read()}
          )));
      expect(encode(text), bytes);
    }
  });
  check('seed', 'JSON target on every upstream fuzz seed', (r) {
    expect(jsonToFleece(r[2]), unhex(r[1]));
    final v = parseFleeceJson(r[2]);
    expect(encode(fromJson(toJson(v))), unhex(r[1]));
  });
  check('seed', 'shared key target on every upstream fuzz seed', (r) {
    final keys = SharedKeys.fromState(unhex(r[3]));
    expect(keys.toState(), unhex(r[3]));
    final v = decode(unhex(r[4]), sharedKeys: keys);
    expect(encode(v), unhex(r[1]));
    expect(
        (Encoder(sharedKeys: keys, fixedSharedKeys: true)..writeValue(v))
            .finish(),
        unhex(r[4]));
  });
  test('delta and update targets on the upstream seed pairs and paths', () {
    final docs =
        rows.where((r) => r[0] == 'seed').map((r) => unhex(r[1])).toList();
    const paths = [
      'name',
      'inner.name',
      'inner.tags[0]',
      '[1]',
      '[2][0]',
      'missing.deeper'
    ];
    for (var i = 0; i < docs.length; i++) {
      final first = docs[i], second = docs[(i + 1) % docs.length];
      final old = decode(first),
          next = decode(second),
          change = diff(old, next);
      expect(encode(change == null ? old : apply(old, change)), second);
      final d =
          Doc(Uint8List.fromList([...first, ...appendDelta(first, next)]));
      expect(encode(decode(compact(d))), second);
      final doc = Doc(second), path = KeyPath.parse(paths[i % paths.length]);
      final part = extract(doc, path);
      if (part != null)
        expect(encode(decode(part)), encode(path.eval(doc.root)!.read()));
      try {
        final changed = Doc(update(doc, Patch()..set(path, old)));
        expect(encode(path.eval(changed.root)!.read()), first);
      } on DeltaError catch (e) {
        expect(e.code, DeltaErrorCode.mismatch);
      }
      try {
        Doc(update(doc, Patch()..remove(path)));
      } on DeltaError catch (e) {
        expect(e.code, DeltaErrorCode.mismatch);
      }
    }
  });
  check('half_sweep', 'f16 matches half for every half and the Rust f32 stride',
      (r) {
    var a = 1, b = 0;
    void byte(int x) {
      a = (a + (x & 255)) % 65521;
      b = (b + a) % 65521;
    }

    for (var i = 0; i <= 65535; i++) {
      final half = FleeceFloat16.fromBits(i), f = half.f32Bits;
      for (var j = 0; j < 4; j++) {
        byte(f >>> (8 * j));
      }
      if (!half.value.isNaN &&
          (FleeceFloat16.fromF32(half.value).bits != i ||
              FleeceFloat16.fromF64(half.value)?.bits != i)) fail('half $i');
    }
    expect(b * 65536 + a, r[1]);
    a = 1;
    b = 0;
    for (var i = 0; i <= 0xffffffff; i += 4099) {
      final h = FleeceFloat16.fromF32Bits(i).bits;
      byte(h);
      byte(h >> 8);
    }
    expect(b * 65536 + a, r[2]);
  });
}
