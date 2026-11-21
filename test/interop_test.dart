@TestOn('vm')
library;

import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:fleece/fleece.dart';
import 'package:test/test.dart';

class _Rng {
  int state = 1203;
  int next(int n) {
    state = state * 48271 % 2147483647;
    return state % n;
  }

  Object? value(int depth) {
    switch (next(depth < 4 ? 14 : 10)) {
      case 0:
        return null;
      case 1:
        return next(2) == 0;
      case 2:
        return next(1 << 30) - (1 << 29);
      case 3:
        return FleeceInt.u64(
            (BigInt.one << 64) - BigInt.one - BigInt.from(next(1 << 30)));
      case 4:
        return next(1000000) / 10.0;
      case 5:
        return FleeceFloat32(next(65536) / 8.0);
      case 6:
        return [
          '',
          'a',
          'repeat',
          'é',
          '\ufeff𐀀',
          '0123456789abcdef'
        ][next(6)];
      case 7:
        return Uint8List.fromList(List.generate(next(20), (_) => next(256)));
      case 8:
        return FleeceInt.i16(next(65536).toSigned(16));
      case 9:
        return const FleeceTable('repeat');
      case 10 || 11:
        return List.generate(next(6), (_) => value(depth + 1));
      case 12:
        return FleeceSet(List.generate(next(5), (_) => value(depth + 1)));
      default:
        final n = next(5);
        return {for (var i = 0; i < n; i++) 'k$i': value(depth + 1)};
    }
  }
}

List<Object?> _documents() {
  const point = (-1.5, 2.25);
  final line = [point, (0.0, -3.0)];
  final polygon = [line, <FleecePoint>[], line];
  const bounds =
      FleeceRange(FleeceBound.included('A'), FleeceBound.excluded('Z'));
  final maxU64 = (BigInt.one << 64) - BigInt.one;
  final minI64 = -(BigInt.one << 63);
  final all = [
    const FleeceNone(),
    FleeceInt.i8(-128),
    FleeceInt.u8(255),
    FleeceInt.i16(-32768),
    FleeceInt.u16(65535),
    FleeceInt.i32(-2147483648),
    FleeceInt.u32(4294967295),
    FleeceInt.u64(maxU64),
    FleeceFloat16.fromBits(0xfc01),
    FleeceDecimal((BigInt.one << 96) - BigInt.one, 28, negative: true),
    FleeceBigDecimal(BigInt.from(-32767), 294910),
    FleeceSeconds.duration(maxU64, 999999999),
    FleeceSeconds.datetime(minI64, 2),
    FleeceUuid(Uint8List.fromList(List.filled(16, 0xab))),
    FleeceDate(-2147483648),
    FleeceTime(86400000000000),
    FleeceSeconds.timestamp(-minI64 - BigInt.one, 123),
    FleeceInterval(-12, 3, minI64),
    const FleeceTable('repeat'),
    FleeceRecordId('dogs', bounds),
    const FleeceFile('🐕', '/a'),
    bounds,
    const FleeceRegex('repeat'),
    FleeceSet([2, 1, 1]),
    FleeceGeometry.collection([
      FleeceGeometry.point(point.$1, point.$2),
      FleeceGeometry.line(line),
      FleeceGeometry.polygon(polygon),
      FleeceGeometry.multiPoint(line),
      FleeceGeometry.multiLine([line, []]),
      FleeceGeometry.multiPolygon([polygon]),
      FleeceGeometry.collection([])
    ]),
    FleeceVector.bits(Uint8List.fromList([0xfd, 0xff]), 11),
    FleeceText.fromRuns([
      ('🙂', null),
      ('é', {'bold': true}),
      ('x', {'bold': true}),
      ('𐀀', null)
    ]),
  ];
  final ints = <int>[];
  for (final bit in [
    7,
    8,
    11,
    15,
    16,
    23,
    24,
    31,
    32,
    39,
    40,
    47,
    48,
    55,
    56,
    62
  ]) {
    final n = 1 << bit;
    ints.addAll([n - 1, n, n + 1, -n - 1, -n, -n + 1]);
  }
  final rng = _Rng();
  return [
    all,
    ints,
    {
      '𐀀': 1,
      '\ue000': 2,
      'a\u0000': 3,
      '\ufeff\ufeffkey': 4,
      'é': 5,
      'e\u0301': 6
    },
    [
      'x',
      'aa',
      'aa',
      '123456789012345',
      '123456789012345',
      '1234567890123456',
      '1234567890123456',
      'é',
      'é'
    ],
    for (final n in [0, 1, 14, 15, 127, 128, 16383, 16384, 32762, 32763])
      Uint8List.fromList(List.generate(n, (i) => i & 255)),
    for (final n in [2046, 2047, 2048, 2174, 2175, 40000])
      List.generate(n, (i) => i % 128),
    List.generate(3000, (i) => 'long string number $i'),
    ...List.generate(1024, (_) => rng.value(0)),
  ];
}

List<Object> _floatBits() => [
      for (final bits in [
        0,
        0x80000000,
        1,
        0x7f800000,
        0xff800000,
        0x7fa00001,
        0xffc12345
      ])
        FleeceFloat32.fromBits(bits),
      for (final bits in [
        '0',
        '8000000000000000',
        '1',
        '7ff0000000000000',
        'fff0000000000000',
        '7ff8000000000000',
        'fff8000020000000',
        '7ff0000000000001',
        '7ff8000000000001'
      ])
        FleeceFloat64.fromBits(BigInt.parse(bits, radix: 16)),
    ];

Iterable<Uint8List> _readerInputs() sync* {
  final rng = _Rng();
  for (final bytes in <List<int>>[
    [], [0x30, 0xef], [0x10, 0xfe, 0x80, 1],
    [0x1f, ...List.filled(8, 0xff), 0, 0x80, 5],
    [0x78, 1, 0x43, 102, 111, 111, 0, 123, 0, 0, 0x80, 5],
    [0x68, 1, 0x60, 1, 0x30, 0, 0x80, 3],
    [0x4f, 0x81, 0, 65, 0x80, 2], // Non-minimal but valid string length.
    [0x31, ExtKind.vector.index, 0x53, 4, 6, 255, 0x80, 3],
  ]) {
    yield Uint8List.fromList(bytes);
  }
  for (final type in ExtKind.values.skip(1)) {
    for (final payload in [
      null,
      -1,
      '',
      Uint8List(0),
      <Object?>[],
      <String, Object?>{}
    ]) {
      yield (Encoder()
            ..beginExt(type)
            ..writeValue(payload))
          .finish();
    }
  }
  for (var i = 0; i < 1024; i++) {
    final bytes = encode([rng.value(0), rng.value(0)]);
    if (i.isEven) {
      bytes[rng.next(bytes.length)] = rng.next(256);
      yield bytes;
    } else {
      yield Uint8List.sublistView(bytes, 0, rng.next(bytes.length));
    }
  }
}

Uint8List _pack(Iterable<Uint8List> frames) {
  final input = BytesBuilder();
  for (final frame in frames) {
    input.add((ByteData(4)..setUint32(0, frame.length, Endian.little))
        .buffer
        .asUint8List());
    input.add(frame);
  }
  return input.takeBytes();
}

Iterable<Uint8List> _unpack(Uint8List bytes) sync* {
  final data = ByteData.sublistView(bytes);
  var at = 0;
  while (at < bytes.length) {
    final length = data.getUint32(at, Endian.little);
    at += 4;
    yield Uint8List.sublistView(bytes, at, at + length);
    at += length;
  }
}

void main() {
  final sibling = Directory('../the-base/crates/fleece');
  final crate = Platform.environment['FLEECE_REFERENCE'] ??
      (File.fromUri(sibling.uri.resolve('src/lib.rs')).existsSync()
          ? sibling.path
          : null);
  test('Dart and Rust independently write and read the same binary documents',
      () async {
    if (crate == null) {
      markTestSkipped(
          'Set FLEECE_REFERENCE to the Rust crates/fleece directory');
      return;
    }
    final dir = await Directory.systemTemp.createTemp('fleece-interop-');
    addTearDown(() => dir.delete(recursive: true));
    String file(String name) => dir.uri.resolve(name).toFilePath();
    Future<void> run(String exe, List<String> args) async {
      final result = await Process.run(exe, args);
      expect(result.exitCode, 0, reason: result.stderr.toString());
    }

    await run('rustc', [
      '--edition=2024',
      '--crate-name=fleece',
      '--crate-type=rlib',
      '$crate/src/lib.rs',
      '-o',
      file('libfleece.rlib')
    ]);
    await run('rustc', [
      '--edition=2024',
      'test/reference/oracle.rs',
      '--extern',
      'fleece=' + file('libfleece.rlib'),
      '-o',
      file('oracle')
    ]);

    final values = _documents();
    final old = {for (var i = 0; i < 32; i++) 'field$i': 'value $i'};
    final next = <String, Object?>{...old, 'field4': null}..remove('field12');
    final keys = SharedKeys()..add('field4');
    final shared = encode(old, sharedKeys: keys);
    final base = encode(old);
    final delta = appendDelta(base, next);
    final external = appendDelta(base, next, external: true);
    final patch = Patch()
      ..set(KeyPath.parse('field4'), null)
      ..remove(KeyPath.parse('field12'))
      ..set(KeyPath.parse('more.items'), [7, '水']);
    final edited = update(Doc(external, base: base), patch);
    final structure = diff(old, next)!;
    final frames = [
      for (final v in values) encode(v),
      encode(_floatBits()),
      shared,
      keys.toState(),
      base,
      delta,
      external,
      compact(Doc(Uint8List.fromList([...base, ...delta]))),
      edited,
      extract(Doc(edited), KeyPath.parse('more.items[-1]'))!,
      encode(structure.value),
      encode(apply(old, structure)),
    ];
    final checks = _readerInputs().toList();
    await File(file('dart.bin')).writeAsBytes(_pack(frames));
    await File(file('checks.bin')).writeAsBytes(_pack(checks));
    await run(file('oracle'), [dir.path]);
    final received =
        _unpack(await File(file('rust.bin')).readAsBytes()).toList();
    expect(received, frames);
    for (var i = 0; i < values.length; i++) {
      expect(decode(received[i]), values[i], reason: 'Rust document $i');
    }
    final floats = received[values.length];
    expect(encode(decode(floats)), floats);
    final special = received.sublist(values.length + 1);
    final restored = SharedKeys.fromState(special[1]);
    expect(decode(special[0], sharedKeys: restored), old);
    expect(decode(Uint8List.fromList([...special[2], ...special[3]])), next);
    expect(decode(special[4], base: special[2]), next);
    expect(decode(special[5]), next);

    final results =
        _unpack(await File(file('checked.bin')).readAsBytes()).toList();
    expect(results.length, checks.length * 5);
    for (var i = 0; i < checks.length; i++) {
      final bytes = checks[i], expected = results[5 * i];
      if (expected.isEmpty) {
        final rust = utf8.decode(results[5 * i + 4]);
        final reason = 'input $i: $bytes, Rust: $rust';
        for (final check in [() => Doc(bytes), () => decode(bytes)]) {
          try {
            check();
            fail('Unexpectedly accepted $reason');
          } on DecodeError catch (e) {
            final name = e.code.name;
            expect(name[0].toUpperCase() + name.substring(1),
                rust.split(' ').first,
                reason: reason);
            final pos = RegExp(r'pos: (\d+)').firstMatch(rust);
            if (pos != null)
              expect(e.position, int.parse(pos[1]!), reason: reason);
          }
        }
      } else {
        expect(encode(decode(bytes)), expected, reason: 'owned value $i');
        expect(compact(Doc(bytes)), results[5 * i + 1],
            reason: 'copied value $i');
      }
      final root = Doc.trusted(bytes).root;
      final operations = [
        () => encode(root.read()),
        () => (Encoder()..writeCopy(root)).finish(),
      ];
      for (var j = 0; j < operations.length; j++) {
        final result = results[5 * i + 2 + j];
        final reason = 'trusted input $i, operation $j, bytes $bytes';
        if (result.isEmpty) {
          expect(
              operations[j],
              throwsA(anyOf(isA<DecodeError>(), isA<EncodeError>(),
                  isA<FormatException>())),
              reason: reason);
        } else {
          Uint8List actual;
          try {
            actual = operations[j]();
          } catch (error) {
            fail('$reason was accepted by Rust but Dart threw $error');
          }
          expect(actual, result, reason: reason);
        }
      }
    }
  },
      skip: crate == null
          ? 'Set FLEECE_REFERENCE to the Rust crates/fleece directory'
          : false,
      timeout: const Timeout(Duration(minutes: 2)));
}
