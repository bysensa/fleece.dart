part of '../fleece.dart';

enum SerdeErrorCode { message, encode, decode }

final class SerdeError extends FormatException {
  const SerdeError(String message,
      {this.code = SerdeErrorCode.message, this.cause})
      : super(message);
  final SerdeErrorCode code;
  final Object? cause;
}

/// Describes an application type for Dart, which has no derive(Serialize).
/// The reader can borrow binary fields and UTF-8 slices from [SerdeReader].
final class FleeceAdapter<T> {
  const FleeceAdapter(this.write, this.read);
  final Object? Function(T) write;
  final T Function(SerdeReader) read;
}

/// Serde's externally tagged variants. A unit variant is just its name.
final class FleeceVariant {
  const FleeceVariant.unit(this.name)
      : value = null,
        hasValue = false;
  const FleeceVariant(this.name, this.value) : hasValue = true;
  final String name;
  final Object? value;
  final bool hasValue;
}

Uint8List toVec<T>(T value, {FleeceAdapter<T>? adapter}) {
  final e = Encoder();
  toEncoder(value, e, adapter: adapter);
  return e.finish();
}

void toEncoder<T>(T value, Encoder e, {FleeceAdapter<T>? adapter}) {
  void write(Object? v) {
    switch (v) {
      case FleeceVariant():
        if (!v.hasValue) {
          e.writeString(v.name);
        } else {
          e.beginDict();
          e.writeKey(v.name);
          write(v.value);
          e.endDict();
        }
      case Enum():
        e.writeString(v.name);
      case Uint8List():
        e.writeData(v);
      case List():
        e.beginArray();
        for (final item in v) {
          write(item);
        }
        e.endArray();
      case Map():
        e.beginDict();
        for (final entry in v.entries) {
          final key = entry.key;
          if (key is! String &&
              !_wireInt(key) &&
              key is! BigInt &&
              key is! Enum)
            throw const SerdeError('A map key must be a string or an integer');
          e.writeKey(key is Enum
              ? key.name
              : _wireInt(key)
                  ? _integer(key!).toString()
                  : key.toString());
          write(entry.value);
        }
        e.endDict();
      case BigInt():
        if (v.bitLength < 64) {
          e.writeInt(v);
        } else if (!v.isNegative && v.bitLength <= 64) {
          e.writeUint(v);
        } else {
          throw const SerdeError('Integer exceeds 64 bits');
        }
      case ValueRef():
        e.writeCopy(v);
      default:
        e.writeValue(v);
    }
  }

  try {
    write(adapter == null ? value : adapter.write(value));
  } on EncodeError catch (error) {
    throw SerdeError(error.toString(),
        code: SerdeErrorCode.encode, cause: error);
  } on ArgumentError catch (error) {
    throw SerdeError(error.toString(), cause: error);
  }
}

T fromSlice<T>(Uint8List bytes, FleeceAdapter<T> adapter,
    {SharedKeys? sharedKeys}) {
  try {
    return fromRef(Doc(bytes, sharedKeys: sharedKeys).root, adapter);
  } on SerdeError {
    rethrow;
  } on FormatException catch (error) {
    throw SerdeError(error.message, code: SerdeErrorCode.decode, cause: error);
  }
}

T fromRef<T>(ValueRef value, FleeceAdapter<T> adapter) {
  try {
    return adapter.read(SerdeReader._(value, _ReadRoom(value.doc)));
  } on SerdeError {
    rethrow;
  } on EncodeError catch (error) {
    throw SerdeError(error.toString(),
        code: SerdeErrorCode.encode, cause: error);
  } on FormatException catch (error) {
    throw SerdeError(error.message, code: SerdeErrorCode.decode, cause: error);
  }
}

final class SerdeReader {
  const SerdeReader._(this.ref, this._room);
  final ValueRef ref;
  final _ReadRoom _room;
  Never _wrong(String expected) {
    if (ref.item.type == ItemType.invalid) {
      _malformed('Invalid Fleece value', ref.position);
    }
    throw SerdeError('Expected $expected, found ' +
        (ref.extKind?.wireName ?? ref.item.type.name));
  }

  bool get isAbsent =>
      ref.isNull ||
      ref.item.type == ItemType.undefined ||
      ref.extKind == ExtKind.none;

  /// Materializes a Fleece value with spelled-out dictionary keys. Native
  /// fields may instead be read individually from the same document.
  Object? get value {
    final encoder = Encoder().._copyWithRoom(ref, _room);
    return decode(encoder.finish());
  }

  T typed<T>() {
    final v = value;
    return v is T ? v : _wrong(T.toString());
  }

  bool get boolean => ref.asBool ?? _wrong('bool');
  BigInt integer({int bits = 64, bool signed = true}) {
    final kind = ref.extKind;
    final n = ref.asInteger ??
        (kind != null && kind.index >= 1 && kind.index <= ExtKind.u64.index
            ? ref.payload?.asInteger
            : null);
    if (n == null ||
        (signed ? n.bitLength >= bits : n.isNegative || n.bitLength > bits))
      _wrong((signed ? 'i' : 'u') + bits.toString());
    return n;
  }

  double get floating {
    final v = ref.asDouble;
    if (v != null) return v;
    if (ref.extKind == ExtKind.f16) {
      final bits = ref.payload?.asInt;
      if (bits == null || bits < 0 || bits > 65535) _wrong('f16');
      return _half(bits);
    }
    return integer(signed: ref.asU64 == null && ref.extKind != ExtKind.u64)
        .toDouble();
  }

  ValueRef? get _text => switch (ref.extKind) {
        ExtKind.table || ExtKind.regex => ref.payload,
        ExtKind.text => ref.payload?.asArray?.get(0),
        _ => ref,
      };
  String get string {
    final text = _text;
    final s = text?.asString ?? _wrong('string');
    _room.takeBytes(text!._header.arg);
    return s;
  }

  Uint8List get utf8Bytes {
    final b = _text?.asUtf8 ?? _wrong('string');
    _room.takeBytes(b.length);
    return b;
  }

  Uint8List get bytes {
    final b = (ref.extKind == ExtKind.uuid ? ref.payload : ref)?.asData ??
        _wrong('bytes');
    _room.takeBytes(b.length);
    return b;
  }

  /// Reads through the same scalar and collection representations seen by a
  /// serde visitor. Use [value] to retain the Fleece extension types.
  Object? get any {
    switch (ref.item.type) {
      case ItemType.nullValue || ItemType.undefined:
        return null;
      case ItemType.boolean:
        return boolean;
      case ItemType.integer || ItemType.unsigned:
        return _nativeInteger(ref.asInteger!);
      case ItemType.float32 || ItemType.float64:
        return floating;
      case ItemType.string:
        return string;
      case ItemType.data:
        return bytes;
      case ItemType.array:
        return [for (final item in sequence) item.any];
      case ItemType.dict:
        return {for (final e in fields) e.key: e.value.any};
      case ItemType.extended:
        final kind = ref.extKind;
        if (kind == ExtKind.none) return null;
        if (kind != null &&
            kind.index >= ExtKind.i8.index &&
            kind.index <= ExtKind.u64.index) {
          final n = ref.payload?.asInteger;
          return n == null ? _wrong('integer') : _nativeInteger(n);
        }
        return switch (kind) {
          ExtKind.table || ExtKind.regex || ExtKind.text => string,
          ExtKind.uuid => bytes,
          ExtKind.set => [for (final item in sequence) item.any],
          ExtKind.f16 => floating,
          _ => _wrong('an application type or Fleece value'),
        };
      case ItemType.invalid:
        _wrong('value');
    }
  }

  SerdeReader _child(ValueRef v, [String? key]) {
    _room.takeValue();
    if (key != null) _room.takeBytes(_utf8(key).length);
    return SerdeReader._(v, _room);
  }

  Iterable<SerdeReader> get sequence {
    final a = ref.asArray ??
        (ref.extKind == ExtKind.set ? ref.payload?.asArray : null);
    if (a == null) _wrong('array');
    return _elements(a);
  }

  Iterable<SerdeReader> _elements(ArrayRef array) sync* {
    for (var i = 0; i < array.length; i++) {
      final child = array.get(i);
      if (child == null) break;
      yield _child(child);
    }
  }

  Iterable<MapEntry<String, SerdeReader>> get fields {
    final dict = ref.asDict ?? _wrong('object');
    return dict.entries.map((e) => MapEntry(e.key, _child(e.value, e.key)));
  }

  SerdeReader? field(String key) {
    final v = (ref.asDict ?? _wrong('object'))[key];
    return v == null ? null : _child(v, key);
  }

  SerdeReader operator [](String key) =>
      field(key) ?? (throw SerdeError('Missing field ' + key));
  (String, SerdeReader?) get variant {
    final tag = ref.asString;
    if (tag != null) return (tag, null);
    final dict = ref.asDict;
    if (dict == null || dict.length != 1) _wrong('enum variant');
    final entry = dict.entries.first;
    return (entry.key, _child(entry.value));
  }
}
