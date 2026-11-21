import 'dart:js_interop';

extension type _FileSystem(JSObject _) {
  external JSString readFileSync(JSString path, JSString encoding);
}

Future<String> readFixture(String path) async {
  final fs = _FileSystem(await importModule('node:fs'.toJS).toDart);
  return fs.readFileSync(path.toJS, 'utf8'.toJS).toDart;
}
