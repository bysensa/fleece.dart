import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:fleece/fleece.dart';

Future<void> main(List<String> args) async {
  Future<Uint8List> input() async {
    final b = BytesBuilder();
    await stdin.forEach(b.add);
    return b.takeBytes();
  }

  Future<Object?> fileValue(String name) async =>
      parseFleeceJson(await File(name).readAsString());
  try {
    final List<int> result;
    switch (args) {
      case ['encode']:
        result = jsonToFleece(utf8.decode(await input()));
      case ['decode']:
        result = utf8.encode(fleeceToJson(await input()));
      case ['dump']:
        result = utf8.encode(dump(Doc(await input())));
      case ['compact']:
        result = compact(Doc(await input()));
      case ['diff', final a, final b]:
        final delta = diff(await fileValue(a), await fileValue(b));
        result = utf8.encode(stringifyFleeceJson(
            delta == null ? <String, Object?>{} : delta.value));
      case ['apply', final a, final b]:
        result = utf8.encode(
            stringifyFleeceJson(apply(await fileValue(a), await fileValue(b))));
      case ['append', final a, final b]:
        result = appendDelta(await File(a).readAsBytes(), await fileValue(b));
      default:
        stderr.writeln(
            'Usage: fleece encode|decode|dump|compact or fleece diff|apply|append OLD NEW');
        exitCode = 64;
        return;
    }
    stdout.add(result);
    await stdout.flush();
  } catch (e) {
    stderr.writeln(e);
    exitCode = 1;
  }
}
