@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:fleece/fleece.dart';
import 'package:test/test.dart';

void main() {
  test('all CLI commands accept the Rust file and stream formats', () async {
    final dir = await Directory.systemTemp.createTemp('fleece-cli-');
    addTearDown(() => dir.delete(recursive: true));
    File file(String name) => File.fromUri(dir.uri.resolve(name));
    final old = file('old.json'), next = file('next.json');
    await old.writeAsString('{"tags":["dog"],"age":9,"name":"Milou"}');
    await next
        .writeAsString('{"tags":["dog","chien"],"age":10,"name":"Milou"}');
    final original = jsonToFleece(await old.readAsString());
    final updated = jsonToFleece(await next.readAsString());
    final base = file('base.fleece')..writeAsBytesSync(original);

    Future<List<int>> run(
        String exe, List<String> args, List<int> input) async {
      final child = await Process.start(exe, args);
      final result = child.stdout.fold<BytesBuilder>(
          BytesBuilder(), (buffer, chunk) => buffer..add(chunk));
      final errors = utf8.decodeStream(child.stderr);
      child.stdin.add(input);
      await child.stdin.close();
      expect(await child.exitCode, 0, reason: await errors);
      return (await result).takeBytes();
    }

    Future<Uint8List> check(List<String> args, List<int> expected,
        [List<int> input = const []]) async {
      final actual = await run(
          Platform.resolvedExecutable, ['bin/fleece.dart', ...args], input);
      expect(actual, expected, reason: args.first);
      final rust = Platform.environment['FLEECE_REFERENCE_CLI'];
      if (rust != null)
        expect(actual, await run(rust, args, input), reason: args.first);
      return Uint8List.fromList(actual);
    }

    await check(['encode'], original, await old.readAsBytes());
    await check(['decode'], utf8.encode(fleeceToJson(original)), original);
    await check(['dump'], utf8.encode(dump(Doc(original))), original);
    final changes = diff(decode(original), decode(updated))!;
    final patch = await check(['diff', old.path, next.path],
        utf8.encode(stringifyFleeceJson(changes.value)));
    final deltaFile = file('delta.json')..writeAsBytesSync(patch);
    await check(['apply', old.path, deltaFile.path],
        utf8.encode(fleeceToJson(updated)));
    final appended = await check(['append', base.path, next.path],
        appendDelta(original, decode(updated)));
    final history = Uint8List.fromList([...original, ...appended]);
    expect(decode(await check(['compact'], compact(Doc(history)), history)),
        decode(updated));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
