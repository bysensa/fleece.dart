// AOT document I/O by wire type. Each timed call handles an entire 128-item
// document. Input construction, compatibility checks and warmup are untimed.
import 'dart:io';
import 'dart:typed_data';

import 'package:fleece/fleece.dart';

const _count = 128;
typedef _Values = List<Object?>;
typedef _Write = Uint8List Function(_Values values);

@pragma('vm:entry-point')
Object? _result;
@pragma('vm:never-inline')
void _consume(Object? value) {
  _result = value;
}

Uint8List _unsigned(_Values values) {
  final e = Encoder()..beginArray();
  for (final v in values) {
    e.writeUint(v is FleeceInt ? v.value : v!);
  }
  return (e..endArray()).finish();
}

void _measure(String name, Object? Function() operation) {
  // Batch very short operations to amortize reading the clock.
  for (var i = 0; i < 16; i++) {
    _consume(operation());
  }
  final watch = Stopwatch()..start();
  var iterations = 0;
  do {
    for (var i = 0; i < 8; i++) {
      _consume(operation());
    }
    iterations += 8;
  } while (watch.elapsedTicks < watch.frequency ~/ 12);
  final us = watch.elapsedTicks * 1e6 / watch.frequency / iterations;
  print('${name.padRight(32)} ${us.toStringAsFixed(3)} µs');
}

void main(List<String> args) {
  final writeOnly = args.length == 1 && args.first == '--write-only';
  final Directory? fixtures;
  if (args.isEmpty || writeOnly) {
    fixtures = null;
  } else if (args.length == 2 && args[0] == '--write-inputs') {
    fixtures = Directory(args[1])..createSync(recursive: true);
  } else {
    throw ArgumentError(
        'Usage: types [--write-only | --write-inputs directory]');
  }
  final covered = <ExtKind>{};
  void bench(String name, Object? Function(int) make,
      {_Write write = encode, Uint8List? base, SharedKeys? sharedKeys}) {
    final values = _Values.generate(_count, make);
    if (values.first case FleeceValue value) covered.add(value.kind);
    final bytes = write(values);
    final checked = Doc(bytes, base: base, sharedKeys: sharedKeys);
    final roundtrip = write(checked.root.read() as _Values);
    if (roundtrip.length != bytes.length ||
        Iterable<int>.generate(bytes.length)
            .any((i) => roundtrip[i] != bytes[i])) {
      throw StateError('Round-trip byte mismatch for $name');
    }
    if (fixtures != null) {
      if (base != null)
        File.fromUri(fixtures.uri.resolve('$name.base')).writeAsBytesSync(base);
      File.fromUri(fixtures.uri.resolve('$name.fleece'))
          .writeAsBytesSync(bytes);
    } else {
      _measure('write/$name', () => write(values));
      if (writeOnly) return;
      _measure('read/$name', () => checked.root.read());
      _measure('decode/$name',
          () => decode(bytes, base: base, sharedKeys: sharedKeys));
    }
  }

  final high = BigInt.one << 63;
  bench('null', (_) => null);
  bench('bool', (i) => i.isOdd);
  bench('int12', (i) => i - 64);
  bench('int64', (i) => (i.isOdd ? 1 : -1) * ((1 << 57) + i));
  bench('uint64', (i) => high + BigInt.from(i), write: _unsigned);
  bench('float32', (i) => FleeceFloat32(i / 7));
  bench('float64-narrow', (i) => i / 4);
  bench('float64', (i) => i / 17);
  bench('string-interned', (i) => 'field-${i % 16}');
  bench('string-utf8', (i) => '\ufeffгород 東京 🦋 $i');
  bench('data', (i) => Uint8List(256)..fillRange(0, 256, i));
  bench('array', (i) => [i, 'entry', i.isEven]);
  bench('dict', (i) => {'name': 'row $i', 'id': i, 'ok': i.isEven});
  final keys = SharedKeys()
    ..add('name')
    ..add('id')
    ..add('ok');
  bench('dict-shared', (i) => {'name': 'row $i', 'id': i, 'ok': i.isEven},
      write: (v) => encode(v, sharedKeys: keys), sharedKeys: keys);
  Map<String, Object?> row(int i, int revision) => {
        'id': i,
        'name': 'row $i',
        'category': 'entry',
        'count': i * 3,
        'ok': true,
        'revision': revision,
      };
  final base = encode(List.generate(_count, (i) => row(i, 0)));
  bench('dict-inherited', (i) => row(i, 1),
      write: (v) => appendDelta(base, v, external: true), base: base);
  bench('none', (_) => const FleeceNone());
  bench('i8', (i) => FleeceInt.i8(i - 64));
  bench('u8', (i) => FleeceInt.u8(255 - i));
  bench('i16', (i) => FleeceInt.i16(-32000 + i));
  bench('u16', (i) => FleeceInt.u16(65000 + i));
  bench('i32', (i) => FleeceInt.i32(-2100000000 + i));
  bench('u32', (i) => FleeceInt.u32(4100000000 + i));
  bench('u64', (i) => FleeceInt.u64(high + BigInt.from(i)));
  bench('f16', (i) => FleeceFloat16.fromBits(0xb800 + i));
  bench(
      'decimal',
      (i) =>
          FleeceDecimal((high << 26) + BigInt.from(i), 7, negative: i.isOdd));
  bench('bigdecimal',
      (i) => FleeceBigDecimal(-(high << 150) + BigInt.from(i), 10));
  bench('duration', (i) => FleeceDuration(high + BigInt.from(i), i));
  bench('datetime', (i) => FleeceDatetime(-1700000000 + i, i));
  bench('uuid',
      (i) => FleeceUuid(Uint8List.fromList(List.generate(16, (j) => i + j))));
  bench('date', (i) => FleeceDate(19000 + i));
  bench('time', (i) => FleeceTime(43200000000000 + i));
  bench('timestamp', (i) => FleeceTimestamp(1700000000 + i, i));
  bench('interval', (i) => FleeceInterval(i, i - 64, -340000000000 + i));
  bench('table', (i) => FleeceTable('table-${i % 8}'));
  bench('record-id', (i) => FleeceRecordId('sensor', [i, 'east']));
  bench('file', (i) => FleeceFile('bucket', 'file-$i'));
  bench('range',
      (i) => FleeceRange(FleeceBound.included(i), FleeceBound.excluded(i + 8)));
  bench('regex', (i) => FleeceRegex('^group$i.*'));
  bench('set', (i) => FleeceSet([i, i + 2, i + 4]));
  FleeceLine line(int i) => List.generate(12, (j) => (i + j / 8, j / 7));
  bench('geo-point', (i) => FleeceGeometry.point(i / 2, i / 3));
  bench('geo-line', (i) => FleeceGeometry.line(line(i)));
  bench('geo-polygon', (i) => FleeceGeometry.polygon([line(i)]));
  bench('geo-multipoint', (i) => FleeceGeometry.multiPoint(line(i)));
  bench(
      'geo-multiline', (i) => FleeceGeometry.multiLine([line(i), line(i + 1)]));
  bench(
      'geo-multipolygon',
      (i) => FleeceGeometry.multiPolygon([
            [line(i)],
            [line(i + 1)]
          ]));
  bench(
      'geo-collection',
      (i) => FleeceGeometry.collection(
          [FleeceGeometry.point(i / 2, i / 3), FleeceGeometry.line(line(i))]));
  List<double> coords(int i) => List.generate(64, (j) => (i - j) / 128);
  bench('vector-f32', (i) => FleeceVector.f32(coords(i)));
  bench('vector-f64', (i) => FleeceVector.f64(coords(i)));
  bench('vector-f16', (i) => FleeceVector.quantizedF16(coords(i)));
  bench('vector-i8', (i) => FleeceVector.quantizedI8(coords(i)));
  bench(
      'vector-bit', (i) => FleeceVector.bits(Uint8List.fromList([i, 255]), 13));
  bench('text-plain', (i) => FleeceText.plain('naïve $i'));
  bench(
      'text-marked',
      (i) => FleeceText.fromRuns([
            ('résumé', {'bold': true}),
            (' $i ', null),
            ('東京', {'color': 'red'})
          ]));
  if (covered.length != ExtKind.values.length) {
    throw StateError(
        'Missing extension fixtures: ${ExtKind.values.toSet().difference(covered)}');
  }
  if (_result is Stopwatch) throw StateError('Unreachable');
}
