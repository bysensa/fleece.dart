/// Binary Fleece documents, including the extensions defined by the-base.
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'src/slot_buffer_native.dart'
    if (dart.library.js_interop) 'src/slot_buffer_web.dart';
import 'src/varint.dart' as varint;
import 'package:geobase/geobase.dart' as geo;

part 'src/format.dart';
part 'src/errors.dart';
part 'src/values.dart';
part 'src/text.dart';
part 'src/encoder.dart';
part 'src/reader.dart';
part 'src/decoder.dart';
part 'src/validation.dart';
part 'src/delta.dart';
part 'src/storage.dart';
part 'src/geo.dart';
part 'src/json.dart';
part 'src/inspect.dart';
part 'src/debug_unicode.dart';
part 'src/serde.dart';
part 'src/key.dart';
part 'src/kind.dart';

/// Writes a document in the order of Rust's owned Value encoder.
Uint8List encode(Object? value, {SharedKeys? sharedKeys}) =>
    (Encoder(sharedKeys: sharedKeys)..writeValue(value)).finish();

/// Validates a document and returns an owned copy of its root.
Object? decode(Uint8List bytes, {SharedKeys? sharedKeys, Uint8List? base}) =>
    _decodeDocument(Doc.trusted(bytes, sharedKeys: sharedKeys, base: base));
