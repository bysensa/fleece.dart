import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fleece/fleece.dart';
import 'package:geobase/geobase.dart' as geo;

// The result escapes the timed call, like black_box in the Rust benchmark.
@pragma('vm:entry-point')
Object? _lastResult;

@pragma('vm:never-inline')
void _consume(Object result) {
  _lastResult = result;
}

void _measure(String name, Object Function() operation,
    {int? bytes, int milliseconds = 300}) {
  final clock = Stopwatch();
  final target = clock.frequency * milliseconds ~/ 1000;
  var runs = 0;
  clock.start();
  do {
    _consume(operation());
    runs++;
  } while (clock.elapsedTicks < target);
  clock.stop();
  final us = clock.elapsedTicks / clock.frequency * 1e6 / runs;
  final rate = bytes == null ? '' : '  ${(bytes / us).toStringAsFixed(1)} MB/s';
  print(
      '${name.padRight(54)} ${us.toStringAsFixed(3).padLeft(10)} µs$rate  ($runs runs)');
}

Map<String, Object?> _record(int i) => {
      'id': FleeceRecordId('user', i),
      'name': 'User Number $i',
      'email': 'user$i@example.com',
      'age': FleeceInt.u8(i % 90),
      'score': i * 0.37,
      'active': i % 3 == 0,
      'tags': ['alpha', 'beta', 'group${i % 10}'],
      'created': FleeceDatetime(1700000000 + i * 3600, 0),
      'address': {
        'city': 'City ${i % 50}',
        'zip': (i * 7 % 100000).toString().padLeft(5, '0'),
        'geo': FleeceGeometry.point(i / 10, 51.5),
      },
    };

// Preserve the order in which encode(records) encounters these string values.
(List<Map<String, Object?>>, List<String>) _dictionaryInputs(
    List<Map<String, Object?>> rows) {
  final addresses = <Map<String, Object?>>[], strings = <String>[];
  for (final row in rows) {
    final address = row['address'] as Map<String, Object?>;
    addresses.add(address);
    strings.addAll([
      address['city'] as String,
      address['zip'] as String,
      (row['id'] as FleeceRecordId).table,
      row['name'] as String,
      ...row['tags'] as List<String>,
    ]);
  }
  return (addresses, strings);
}

// Time endArray on the same 1,000 records as encode(). The open encoders
// already contain every record. finish() and the allocation of each batch
// are outside the timed section, as in the Rust counterpart.
void _wideRoot(List<Map<String, Object?>> records) {
  Encoder prepare() {
    final encoder = Encoder()..beginArray();
    for (final record in records) {
      encoder.writeValue(record);
    }
    return encoder;
  }

  final expected = encode(records);
  final sample = (prepare()..endArray()).finish();
  if (sample.length != expected.length ||
      sample[Doc.trusted(sample).root.position] & 0x08 == 0 ||
      Iterable<int>.generate(sample.length)
          .any((i) => sample[i] != expected[i])) {
    throw StateError('The prepared root must match the wide encode() result');
  }
  const batches = 64, count = 8;
  final watch = Stopwatch();
  for (var batch = -2; batch < batches; batch++) {
    final writers = List.generate(count, (_) => prepare(), growable: false);
    if (batch >= 0) watch.start();
    for (final writer in writers) {
      writer.endArray();
    }
    if (batch >= 0) watch.stop();
    for (final writer in writers) {
      _consume(writer.finish());
    }
  }
  final us = watch.elapsedTicks * 1e6 / watch.frequency / (batches * count);
  print('fleece: close wide root  ${us.toStringAsFixed(3)} µs');
}

Object _nested(int depth, int leaf) {
  Object value = leaf;
  for (var level = 0; level < depth; level++) {
    value = {
      for (var i = 0; i < 20; i++)
        'field${i.toString().padLeft(2, '0')}': 'some text',
      'next': value,
    };
  }
  return value;
}

// Rust's sequential sum::<f32>() rounds the product and the sum separately.
// ByteData also works for the unaligned bytes of a decoded Fleece vector.
double _scalarDot(
    ByteData values, Endian endian, Float32List query, Float32List rounding) {
  var sum = 0.0;
  for (var i = 0; i < query.length; i++) {
    rounding[0] = values.getFloat32(i * 4, endian) * query[i];
    rounding[0] = sum + rounding[0];
    sum = rounding[0];
  }
  return sum;
}

void _vectors({Directory? inputs}) {
  final embedding = Float32List.fromList(
      List.generate(768, (i) => (i * 37 % 101 - 50) / 400));
  final query =
      Float32List.fromList(List.generate(768, (i) => (i * 53 % 97 - 48) / 400));
  final rounding = Float32List(1);
  final array = embedding.map(FleeceFloat32.new).toList();
  final path = KeyPath.parse('embedding');
  Uint8List note(FleeceVector vector) =>
      encode({'title': 'Tintin in Tibet', 'embedding': vector});
  VectorRef field(Uint8List bytes) =>
      path.eval(Doc.trusted(bytes).root)!.asVector!;

  final scores = <double>[];
  if (inputs == null) {
    print('768 dimensions as an array of f32: ${encode(array).length} bytes');
  }
  for (final (name, vector) in [
    ('f32', FleeceVector.f32(embedding)),
    ('f16', FleeceVector.quantizedF16(embedding)),
    ('i8', FleeceVector.quantizedI8(embedding)),
    ('bits', FleeceVector.quantizedBits(embedding)),
  ]) {
    final stored = note(vector);
    if (inputs == null) {
      _measure('vector $name, ${stored.length} bytes: dot in place',
          () => field(stored).dot(query)!);
    } else {
      File.fromUri(inputs.uri.resolve('vector-$name.fleece'))
          .writeAsBytesSync(stored);
      final ref = field(stored);
      scores.add(ref.dot(query)!);
      if (name == 'f32') scores.add(ref.cosine(query)!);
    }
  }
  final stored = note(FleeceVector.f32(embedding));
  double decodedDot() {
    final fields = Doc.trusted(stored).root.read() as Map;
    final vector = fields['embedding'] as FleeceVector;
    return _scalarDot(
        ByteData.sublistView(vector.bytes), Endian.little, query, rounding);
  }

  final values = ByteData.sublistView(embedding);
  double plainDot() => _scalarDot(values, Endian.host, query, rounding);
  if (inputs != null) {
    scores.addAll([decodedDot(), plainDot()]);
    final data = ByteData(scores.length * 4);
    for (var i = 0; i < scores.length; i++) {
      data.setFloat32(i * 4, scores[i], Endian.little);
    }
    File.fromUri(inputs.uri.resolve('vector-results.f32'))
        .writeAsBytesSync(data.buffer.asUint8List());
    return;
  }
  _measure('vector f32: cosine in place', () => field(stored).cosine(query)!);
  _measure('vector f32: decode the document, then dot', decodedDot);
  _measure('plain slices: dot of 768 f32, one sum', plainDot);
}

void _geometry() {
  final ring = List<FleecePoint>.generate(
      10000, (i) => (math.cos(i), math.sin(i)),
      growable: true);
  ring.add(ring.first);
  final stored = encode(FleeceGeometry.polygon([ring]));
  FleeceGeometry read() => Doc.trusted(stored).root.asGeometry!;
  _measure('polygon of 10 000 points: read', read, bytes: stored.length);
  _measure('polygon: read, given to geobase', () => read().toGeo());
  _measure('polygon: read, copied to geobase', () {
    final rings = read().coordinates as FleecePolygon;
    final copies = <geo.PositionSeries>[];
    for (final ring in rings) {
      final xy = Float64List(ring.length * 2);
      for (var i = 0; i < ring.length; i++) {
        xy[i * 2] = ring[i].$1;
        xy[i * 2 + 1] = ring[i].$2;
      }
      copies.add(geo.PositionSeries.view(xy));
    }
    return geo.Polygon(copies);
  });
}

/// Native Dart counterpart of crates/fleece/benches/throughput.rs.
void main(List<String> args) {
  final profile = args.length == 2 && args.first == '--profile-encode';
  final wideRoot = args.length == 1 && args.first == '--wide-root';
  final dictionaries = args.length == 1 && args.first == '--dict-strings';
  final seconds = profile ? int.tryParse(args[1]) ?? 0 : 0;
  if (args.isNotEmpty &&
      !wideRoot &&
      !dictionaries &&
      !(args.length == 2 && args.first == '--write-inputs') &&
      !(profile && seconds > 0)) {
    stderr.writeln(
        'Usage: throughput [--write-inputs DIRECTORY | --profile-encode SECONDS | --wide-root | --dict-strings]');
    exitCode = 64;
    return;
  }
  final records = List.generate(1000, _record);
  if (dictionaries) {
    final (addresses, strings) = _dictionaryInputs(records);
    _measure('fleece: encode address dictionaries', () => encode(addresses),
        bytes: encode(addresses).length);
    _measure('fleece: encode short string values', () => encode(strings),
        bytes: encode(strings).length);
    return;
  }
  if (wideRoot) {
    _wideRoot(records);
    return;
  }
  if (profile) {
    final bytes = encode(records).length;
    _measure('fleece: encode a value', () => encode(records),
        bytes: bytes, milliseconds: seconds * 1000);
    return;
  }
  final bytes = encode(records);
  final one = _record(500);
  final oneBytes = encode(one);
  // Start with the canonical field order used by serde_json's object tree.
  final tree = jsonDecode(stringifyFleeceJson(records)) as List;
  final text = jsonEncode(tree);
  final oneTree = tree[500];
  final oneTextSize = jsonEncode(oneTree).length;
  final path = KeyPath.parse('[500].address.city');
  final checked = Doc(bytes);
  final age = FleeceInt.u8(99);
  // Rust changes an independently owned clone of the document.
  final changed = List.generate(1000, _record);
  changed[500]['age'] = age;
  final delta = appendDelta(bytes, changed);
  final appended = Uint8List.fromList([...bytes, ...delta]);
  final patch = Patch()..set(KeyPath.parse('[500].age'), age);
  final onePatch = Patch()..set(KeyPath.parse('age'), age);
  final keys = SharedKeys();
  final oneShared = encode(one, sharedKeys: keys);
  if (args.isNotEmpty) {
    final dir = Directory(args[1])..createSync(recursive: true);
    File.fromUri(dir.uri.resolve('records.fleece')).writeAsBytesSync(bytes);
    File.fromUri(dir.uri.resolve('records.json')).writeAsStringSync(text);
    File.fromUri(dir.uri.resolve('record.fleece')).writeAsBytesSync(oneBytes);
    File.fromUri(dir.uri.resolve('record-shared.fleece'))
        .writeAsBytesSync(oneShared);
    File.fromUri(dir.uri.resolve('change.fleece')).writeAsBytesSync(delta);
    final (addresses, strings) = _dictionaryInputs(records);
    File.fromUri(dir.uri.resolve('addresses.fleece'))
        .writeAsBytesSync(encode(addresses));
    File.fromUri(dir.uri.resolve('short-strings.fleece'))
        .writeAsBytesSync(encode(strings));
    _vectors(inputs: dir);
    return;
  }
  if (path.eval(checked.root)?.asString != 'City 0' ||
      KeyPath.parse('[500].age').eval(Doc(appended).root)?.read() != age) {
    throw StateError('Unexpected benchmark data');
  }
  // The entire JSON fixture is ASCII, so its UTF-8 and String lengths agree.
  print(
      '1000 records: ${bytes.length} bytes of Fleece, ${text.length} bytes of JSON');
  _measure('fleece: encode a value', () => encode(records),
      bytes: bytes.length);
  _measure('fleece: encode one record', () => encode(one),
      bytes: oneBytes.length);
  _measure('dart:convert: write one record', () => jsonEncode(oneTree),
      bytes: oneTextSize);
  _measure('fleece: check a document', () => Doc(bytes), bytes: bytes.length);
  _measure('fleece: check and decode to a value', () => decode(bytes)!,
      bytes: bytes.length);
  _measure('fleece: decode a checked document', () => checked.root.read()!,
      bytes: bytes.length);
  _measure('fleece: read one field in place, unchecked',
      () => path.eval(Doc.trusted(bytes).root)!.asString!.length);
  _measure('fleece: check, then read one field',
      () => path.eval(Doc(bytes).root)!.asString!.length,
      bytes: bytes.length);
  _measure('dart:convert: write text', () => jsonEncode(tree),
      bytes: text.length);
  _measure('dart:convert: parse text', () => jsonDecode(text) as List,
      bytes: text.length);
  _measure('dart:convert: parse, then read one field',
      () => (jsonDecode(text)[500]['address']['city'] as String).length,
      bytes: text.length);

  print('one field of one record changed: a delta of ${delta.length} bytes');
  _measure('fleece: delta to append', () => appendDelta(bytes, changed));
  _measure('fleece: delta as a value', () => diff(records, changed)!);
  _measure(
      'fleece: compact base and delta', () => compact(Doc.trusted(appended)),
      bytes: appended.length);
  _measure('fleece: update one field without a decode',
      () => update(Doc.trusted(bytes), patch));
  _measure('fleece: decode, change, encode', () {
    final copy = Doc.trusted(bytes).root.read() as List;
    (copy[500] as Map)['age'] = age;
    return encode(copy);
  });
  _measure('fleece: update one field of one record',
      () => update(Doc.trusted(oneBytes), onePatch));
  _measure('fleece: key of an index entry (a string)',
      () => encodeKey('user500@example.com'));
  _measure('fleece: key of an index entry (a float)', () => encodeKey(185.37));
  print(
      'one record: ${oneBytes.length} bytes, ${oneShared.length} with shared keys');

  _vectors();
  _geometry();
  for (final depth in [25, 50, 100]) {
    final base = encode(_nested(depth, 1)), next = _nested(depth, 2);
    _measure('fleece: delta at the bottom of $depth levels',
        () => appendDelta(base, next));
  }
  if (_lastResult == null) throw StateError('No measurement completed');
}
