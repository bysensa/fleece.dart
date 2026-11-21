import 'dart:io';

Future<String> readFixture(String path) => File(path).readAsString();
