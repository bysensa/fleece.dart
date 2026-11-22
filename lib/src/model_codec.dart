part of '../fleece.dart';

// SDK types for generated parts whose owning library imports only fleece.dart.
typedef $FleeceBytes = Uint8List;
typedef $FleeceResult<R> = FutureOr<R>;

/// Generates a binary codec and a document-backed implementation of a class.
final class FleeceModel {
  const FleeceModel({this.name});

  /// Overrides the builder's class name for this particular model.
  final String? name;
}

/// The literal dictionary key for a constructor-backed property.
final class FleeceKey {
  const FleeceKey(this.name);
  final String name;
}

/// A codec writes one value into an existing encoder and reads one wire value.
class FleeceCodec<T> {
  const FleeceCodec(this.write, this.read);
  final void Function(Encoder, T) write;
  final T Function(ValueRef) read;

  Uint8List encode(T value, {SharedKeys? sharedKeys}) {
    final encoder = Encoder(sharedKeys: sharedKeys);
    write(encoder, value);
    return encoder.finish();
  }

  T decode(Uint8List bytes, {SharedKeys? sharedKeys, Uint8List? base}) =>
      read(Doc(bytes, sharedKeys: sharedKeys, base: base).root);

  FleeceCodec<T?> nullable() => FleeceCodec(
      (e, v) => v == null ? e.writeNull() : write(e, v),
      (v) => v.isNull ? null : read(v));
}

final class FleeceModelCodec<T, M extends T> extends FleeceCodec<T> {
  const FleeceModelCodec(super.write, super.read, this._construct);
  final M Function(FleeceCursor) _construct;

  M bind(FleeceCursor cursor) {
    final wasBinding = cursor._binding;
    cursor._binding = true;
    try {
      return _construct(cursor);
    } finally {
      cursor._binding = wasBinding;
    }
  }

  M open(Uint8List bytes,
      {Uint8List? base,
      SharedKeys? sharedKeys,
      FleeceTracking Function()? tracking}) {
    final document = _ModelDocument.open(bytes, base, sharedKeys, tracking);
    try {
      return bind(FleeceCursor._(document, KeyPath._(const [])));
    } catch (_) {
      document.dispose();
      rethrow;
    }
  }
}

/// Shared by the generated serializer, deserializer and accessors.
final class FleeceField<T> {
  const FleeceField(this.key, this.codec, {this.whenMissing});
  final String key;
  final FleeceCodec<T> codec;
  final T Function()? whenMissing;

  ValueRef? _encodeDefault() {
    final fallback = whenMissing;
    return fallback == null ? null : Doc(codec.encode(fallback())).root;
  }

  T read(ValueRef? ref) {
    if (ref == null) {
      final fallback = whenMissing;
      if (fallback != null) return fallback();
      throw FormatException('Missing required Fleece field "$key"');
    }
    try {
      return codec.read(ref);
    } on FormatException catch (error) {
      throw FormatException(
          'Field "$key": ' + error.message, null, ref.position);
    }
  }

  void write(Encoder e, T value) {
    e.writeKey(key);
    codec.write(e, value);
  }
}

abstract final class FleeceCodecs {
  static Never _wrong(ValueRef v, String expected) => throw FormatException(
      'Expected $expected, found ' + v.type.name, null, v.position);

  static DictRef dictionary(ValueRef v) => v.asDict ?? _wrong(v, 'dictionary');
  static final string = FleeceCodec<String>(
      (e, s) => e.writeString(s), (v) => v.asString ?? _wrong(v, 'string'));
  static final boolean = FleeceCodec<bool>(
      (e, b) => e.writeBool(b), (v) => v.asBool ?? _wrong(v, 'bool'));
  static final integer = FleeceCodec<int>(
      (e, n) => e.writeInt(n), (v) => v.asInt ?? _wrong(v, 'Dart int'));
  static final number = FleeceCodec<num>((e, n) => e.writeValue(n),
      (v) => v.asInt ?? v.asDouble ?? _wrong(v, 'Dart num'));
  static final value =
      FleeceCodec<Object?>((e, value) => e.writeValue(value), (v) => v.read());
  static final object = FleeceCodec<Object>((e, value) => e.writeValue(value),
      (v) => v.read() ?? _wrong(v, 'non-null value'));
  static final bigInteger = FleeceCodec<BigInt>(
      (e, n) => n.bitLength < 64 ? e.writeInt(n) : e.writeUint(n),
      (v) => v.asInteger ?? _wrong(v, 'integer'));
  static final floating = FleeceCodec<double>(
      (e, n) => e.writeF64(n), (v) => v.asDouble ?? _wrong(v, 'float'));
  static final float32 =
      FleeceCodec<FleeceFloat32>((e, n) => e.writeValue(n), (v) {
    if (v.type != ValueType.float32) _wrong(v, 'float32');
    return FleeceFloat32.fromBits(
        ByteData.sublistView(v.doc._tail(v.position)).getUint32(2, _le));
  });
  static final float64 =
      FleeceCodec<FleeceFloat64>((e, n) => e.writeValue(n), (v) {
    if (v.type != ValueType.float64) _wrong(v, 'float64');
    final value = v._readDouble(v._header);
    return value is FleeceFloat64 ? value : FleeceFloat64(value as double);
  });
  static final bytes = FleeceCodec<Uint8List>((e, b) => e.writeData(b),
      (v) => Uint8List.fromList(v.asData ?? _wrong(v, 'binary data')));

  static final _microsPerSecond = BigInt.from(Duration.microsecondsPerSecond);
  static final _maxDateMicros = BigInt.parse('8640000000000000000');
  static final _datetimeExtension = native<FleeceDatetime>();
  static final dateTime = FleeceCodec<DateTime>((e, value) {
    final micros = BigInt.from(value.microsecondsSinceEpoch);
    final fraction = micros % _microsPerSecond;
    e.writeValue(FleeceDatetime(
        (micros - fraction) ~/ _microsPerSecond, fraction.toInt() * 1000));
  }, (v) {
    final value = _datetimeExtension.read(v);
    final micros = value.seconds * _microsPerSecond +
        BigInt.from(value.nanoseconds ~/ 1000);
    if (value.nanoseconds % 1000 != 0 ||
        micros.abs() > _maxDateMicros ||
        BigInt.from(micros.toInt()) != micros) {
      throw const FormatException(
          'Datetime exceeds Dart DateTime precision or range');
    }
    return DateTime.fromMicrosecondsSinceEpoch(micros.toInt(), isUtc: true);
  });

  static FleeceCodec<List<T>> list<T>(FleeceCodec<T> item) =>
      FleeceCodec((e, values) {
        e.beginArray();
        for (final value in values) {
          item.write(e, value);
        }
        e.endArray();
      }, (v) {
        final array = v.asArray ?? _wrong(v, 'array');
        return List.unmodifiable(array.map(item.read));
      });

  static FleeceCodec<Map<String, T>> map<T>(FleeceCodec<T> item) =>
      FleeceCodec((e, values) {
        e.beginDict();
        for (final key in _names(values)) {
          e.writeKey(key);
          item.write(e, values[key] as T);
        }
        e.endDict();
      },
          (v) => Map.unmodifiable({
                for (final entry in dictionary(v).entries)
                  entry.key: item.read(entry.value)
              }));

  static FleeceCodec<E> enumeration<E extends Enum>(List<E> values) {
    final byName = {for (final value in values) value.name: value};
    return FleeceCodec((e, value) => e.writeString(value.name),
        (v) => byName[string.read(v)] ?? _wrong(v, 'a known enum name'));
  }

  /// Preserves the Fleece extension tag and binary representation.
  static FleeceCodec<T> native<T extends FleeceValue>() =>
      FleeceCodec((e, v) => e.writeValue(v), (ref) {
        final value = ref.read();
        return value is T ? value : _wrong(ref, T.toString());
      });
}
