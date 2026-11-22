@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

void main() {
  test(
    'a fresh consumer builds from source and diagnoses invalid schemas',
    () async {
      final dir = await Directory.systemTemp.createTemp('fleece-consumer-');
      addTearDown(() => dir.delete(recursive: true));
      Future<void> write(String path, String source) async {
        final file = File.fromUri(dir.uri.resolve(path));
        await file.parent.create(recursive: true);
        await file.writeAsString(source);
      }

      Future<Directory> package(String uri) async => File.fromUri(
        (await Isolate.resolvePackageUri(Uri.parse(uri)))!,
      ).parent.parent;
      final runtime = await package('package:fleece/model.dart');
      final generator = await package('package:fleece_generator/builder.dart');
      final example = await package('package:fleece_model_example/note.dart');
      final runner = await package('package:build_runner/build_runner.dart');
      final dart = Platform.resolvedExecutable;
      Future<String> run(List<String> args, {bool success = true}) async {
        final result = await Process.run(
          dart,
          args,
          workingDirectory: dir.path,
        );
        final output = '${result.stdout}\n${result.stderr}';
        expect(result.exitCode == 0, success, reason: output);
        return output;
      }

      await write('pubspec.yaml', '''
name: consumer
environment:
  sdk: '>=3.11.0 <4.0.0'
dependencies:
  fleece:
    path: ${jsonEncode(runtime.path)}
  fleece_model_example:
    path: ${jsonEncode(example.path)}
dev_dependencies:
  build_runner:
    path: ${jsonEncode(runner.path)}
  fleece_generator:
    path: ${jsonEncode(generator.path)}
''');
      await write('build.yaml', r'''
targets:
  $default:
    builders:
      fleece_generator:fleece_model:
        options:
          class_name: 'Live{name}'
          strip_suffix: Dto
''');
      await write('lib/defaults.dart', '''
import 'package:fleece_model_example/note.dart' as schema;
const _limit = 7;
const _priorities = [schema.Priority.high];
class BaseSettings {
  const BaseSettings({this.limit = _limit, this.priorities = _priorities,
      this.city = const schema.Address('Lyon')});
  final int limit;
  final List<schema.Priority> priorities;
  final schema.Address city;
}
class BaseBatch<T> {
  const BaseBatch({this.values = const []});
  final List<T> values;
}
''');
      await write('lib/catalog.dart', '''
import 'package:fleece/model.dart';
import 'package:fleece_model_example/note.dart' as notes;
import 'defaults.dart' as base;
part 'catalog.fleece.g.dart';
@FleeceModel(constructor: 'stored')
class CatalogDto<T> {
  const CatalogDto.stored(this.items, this.address);
  final List<T> items;
  final notes.Address address;
}
@FleeceModel()
class SettingsDto extends base.BaseSettings {
  const SettingsDto({super.limit, super.priorities, super.city});
}
@FleeceModel()
class BatchDto<T> extends base.BaseBatch<T> {
  const BatchDto({super.values});
}
@FleeceModel()
class AnyDto {
  const AnyDto(this.data);
  final Object? data;
}
@FleeceModel()
class PairDto<A, B> {
  const PairDto(this.left, this.right);
  final A left;
  final List<B> right;
}
''');
      await write('bin/main.dart', r'''
import 'package:consumer/catalog.dart';
import 'package:fleece/model.dart';
import 'package:fleece_model_example/note.dart' as notes;
void main() {
  const dto = CatalogDto.stored([1, 2], notes.Address('Lyon'));
  final codec = LiveCatalog.codec<int>(codecT: FleeceCodecs.integer);
  final doc = LiveCatalog(codec.encode(dto), codecT: FleeceCodecs.integer);
  doc.transaction<void>((draft) {
    draft.items.add(3);
    draft.address.city = 'Paris';
  });
  final saved = codec.decode(doc.toFleece());
  print('${saved.address.city} ${saved.items}');
  doc.dispose();
  final empty = (Encoder()..beginDict()..endDict()).finish();
  final settings = LiveSettings(empty);
  print('${settings.limit} ${settings.priorities.single.name} ${settings.city.city}');
  settings.dispose();
  final batch = LiveBatch<int>(empty, codecT: FleeceCodecs.integer);
  batch.values.add(12);
  print('batch ${batch.values.single}');
  batch.dispose();
  final any = LiveAny(const AnyDto({'tags': []}).toFleece());
  ((any.data as Map)['tags'] as List).add('live');
  print('dynamic ${(any.toModel().data as Map)['tags']}');
  any.dispose();
  final preserve = FleeceCodec<int>((e, v) => e.writeInt(v),
      (_) => throw StateError('an unchanged type parameter was decoded'));
  final pair = LivePair<int, int>(
    PairDto(5, [7]).toFleece(codecA: preserve, codecB: FleeceCodecs.integer),
    codecA: preserve, codecB: FleeceCodecs.integer);
  final asText = FleeceCodec<int>((e, v) => e.writeString(v.toString()),
      (ref) => int.parse(ref.asString!));
  final changed = pair.toFleece(codecB: asText);
  final read = LivePair<int, String>(changed, codecA: FleeceCodecs.integer, codecB: FleeceCodecs.string);
  print('${read.left} ${read.right.single.runtimeType}');
  read.dispose();
  pair.dispose();
}
''');
      await run(['pub', 'get', '--offline']);
      await run(['run', 'build_runner', 'build']);
      final output = await run(['run', 'bin/main.dart']);
      expect(output, contains('Paris [1, 2, 3]'));
      expect(output, contains('7 high Lyon'));
      expect(output, contains('batch 12'));
      expect(output, contains('dynamic [live]'));
      expect(output, contains('5 String'));

      Future<void> invalid(String name, String body) =>
          write('lib/$name.dart', '''
import 'package:fleece/model.dart';
part '$name.fleece.g.dart';
$body
''');
      await invalid(
        'duplicate',
        "@FleeceModel() class Duplicate { const Duplicate(this.a, this.b); @FleeceKey('x') final int a; @FleeceKey('x') final int b; }",
      );
      await invalid(
        'ctor',
        "@FleeceModel(constructor: 'absent') class Only { const Only(); }",
      );
      await invalid('codec', '''
class IntCodec extends FleeceCodec<int> {
  IntCodec() : super(FleeceCodecs.integer.write, FleeceCodecs.integer.read);
}
@FleeceModel() class BadCodec { const BadCodec(this.value); @FleeceUseCodec(IntCodec) final String value; }
''');
      await invalid(
        'keys',
        '@FleeceModel() class BadKeys { const BadKeys(this.value); final Map<int, String> value; }',
      );
      await invalid(
        'collision',
        '@FleeceModel() class NoteDto { const NoteDto(); } class LiveNote {}',
      );
      final diagnostics = await run([
        'run',
        'build_runner',
        'build',
      ], success: false);
      for (final expected in [
        'Duplicate Fleece key x',
        'Select a named constructor',
        'does not match String',
        'dictionary keys must have type String',
        'Generated name "LiveNote" is already in use',
      ]) {
        expect(diagnostics, contains(expected));
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
