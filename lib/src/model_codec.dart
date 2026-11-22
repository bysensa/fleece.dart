part of '../fleece.dart';

// SDK types for generated parts whose owning library imports only fleece.dart.
typedef $FleeceBytes = Uint8List;
typedef $FleeceResult<R> = FutureOr<R>;

/// Generates a binary codec and a document-backed implementation of a class.
final class FleeceModel {
  const FleeceModel({this.name, this.constructor});

  /// Overrides the builder's class name for this particular model.
  final String? name;

  /// The constructor used to deserialize the model. Defaults to the unnamed one.
  final String? constructor;
}

/// The literal dictionary key for a constructor-backed property.
final class FleeceKey {
  const FleeceKey(this.name);
  final String name;
}

/// Use a concrete [FleeceCodec] with an unnamed, zero-argument constructor
/// for a field's type, including occurrences inside lists and dictionaries.
final class FleeceUseCodec {
  const FleeceUseCodec(this.type);
  final Type type;
}

/// A codec writes one value into an existing encoder and reads one wire value.
class FleeceCodec<T> {
  const FleeceCodec(this.write, this.read) : _bindAt = null;
  const FleeceCodec._bound(this.write, this.read, this._bindAt);
  final void Function(Encoder, T) write;
  final T Function(ValueRef) read;
  final T Function(FleeceCursor)? _bindAt;
  bool get _hasBinding => _bindAt != null;

  Uint8List encode(T value, {SharedKeys? sharedKeys}) {
    final encoder = Encoder(sharedKeys: sharedKeys);
    write(encoder, value);
    return encoder.finish();
  }

  T decode(Uint8List bytes, {SharedKeys? sharedKeys, Uint8List? base}) =>
      read(Doc(bytes, sharedKeys: sharedKeys, base: base).root);

  /// Reads a field when the codec is supplied as a generic type argument.
  T bindValue(FleeceCursor cursor) {
    final bind = _bindAt;
    return bind == null ? cursor.read(this) : bind(cursor);
  }

  FleeceCodec<T?> nullable() => _NullableCodec(this);
}

final class _NullableCodec<T> extends FleeceCodec<T?> {
  _NullableCodec(this.item)
      : super((e, v) => v == null ? e.writeNull() : item.write(e, v),
            (v) => v.isNull ? null : item.read(v));
  final FleeceCodec<T> item;
  @override
  bool get _hasBinding => item._hasBinding;
  @override
  T? bindValue(FleeceCursor cursor) =>
      cursor.hasValue ? item.bindValue(cursor) : null;
}

final class FleeceModelCodec<T, M extends T> extends FleeceCodec<T> {
  const FleeceModelCodec(super.write, super.read, this._construct);
  final M Function(FleeceCursor) _construct;

  @override
  bool get _hasBinding => true;

  @override
  M bindValue(FleeceCursor cursor) => cursor.object(bind);

  M bind(FleeceCursor cursor) {
    final wasBinding = cursor._binding;
    cursor._document._bindings++;
    cursor._binding = true;
    try {
      return _construct(cursor);
    } finally {
      cursor._binding = wasBinding;
      cursor._document._bindings--;
      if (!wasBinding) {
        cursor._initializing?._close();
        cursor._initializing = null;
      }
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
    return fallback == null ? null : _modelRoot(codec.encode(fallback()));
  }

  T read(ValueRef? ref) {
    if (ref == null) {
      final fallback = whenMissing;
      if (fallback == null) {
        throw FormatException('Missing required Fleece field "$key"');
      }
      final value = fallback();
      if (value == null ||
          value is num ||
          value is bool ||
          value is String ||
          value is Enum ||
          value is BigInt) return value;
      // A constructor default can contain const collections several levels
      // deep. Give a detached model the same ownership as a present field.
      ref = _modelRoot(codec.encode(value));
    }
    try {
      return codec.read(ref);
    } on FormatException catch (error) {
      throw FormatException(
          'Field "$key": ' + error.message, null, error.offset ?? ref.position);
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
      FleeceCodec<Object?>._bound(_writeValue, (v) => v.read(), _bindValue);
  static final object = FleeceCodec<Object>._bound(
      _writeValue,
      (v) => v.read() ?? _wrong(v, 'non-null value'),
      (cursor) =>
          _bindValue(cursor) ?? _wrong(cursor._get()!, 'non-null value'));

  static Object? _bindValue(FleeceCursor cursor) {
    final ref = cursor._get(kind: _ModelRead.type);
    if (ref == null) {
      throw FormatException('Missing Fleece value at ${cursor._path._steps}');
    }
    return switch (ref.type) {
      ValueType.array => cursor._list<Object?, Object?>(value, null),
      ValueType.dict => cursor._map<Object?, Object?>(value, null),
      _ => cursor._get()!.read(),
    };
  }

  static void _writeValue(Encoder encoder, Object? value) {
    final ValueRef? ref;
    if (value is FleeceList) {
      ref = value._cursor._get();
      if (ref?.asArray == null)
        throw const FormatException('Expected Fleece array');
    } else if (value is FleeceMap) {
      ref = value._cursor._get();
      if (ref?.asDict == null)
        throw const FormatException('Expected Fleece dictionary');
    } else {
      encoder.writeValue(value);
      return;
    }
    encoder._copyWithRoom(ref!, _ReadRoom(ref.doc), canonical: true);
  }

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

  static final _millisPerSecond = BigInt.from(Duration.millisecondsPerSecond);
  static final _maxDateMillis = BigInt.from(8640000000000000);
  static final _datetimeExtension = native<FleeceDatetime>();
  static final dateTime = FleeceCodec<DateTime>((e, value) {
    // JavaScript can represent every Dart epoch millisecond exactly, while
    // combining it with the microsecond component can round off low bits.
    final millis = value.millisecondsSinceEpoch;
    final fraction = millis % Duration.millisecondsPerSecond;
    e.writeValue(FleeceDatetime(
        (millis - fraction) ~/ Duration.millisecondsPerSecond,
        (fraction * Duration.microsecondsPerMillisecond + value.microsecond) *
            1000));
  }, (v) {
    final value = _datetimeExtension.read(v);
    final millis = value.seconds * _millisPerSecond +
        BigInt.from(value.nanoseconds ~/ 1000000);
    final micros = value.nanoseconds % 1000000 ~/ 1000;
    if (value.nanoseconds % 1000 != 0 ||
        millis.abs() > _maxDateMillis ||
        millis == _maxDateMillis && micros != 0) {
      throw const FormatException(
          'Datetime exceeds Dart DateTime precision or range');
    }
    final date =
        DateTime.fromMillisecondsSinceEpoch(millis.toInt(), isUtc: true);
    return micros == 0 ? date : date.add(Duration(microseconds: micros));
  });

  static FleeceCodec<List<T>> list<T>(FleeceCodec<T> item) =>
      FleeceCodec._bound((e, values) {
        e.beginArray();
        for (final value in values) {
          item.write(e, value);
        }
        e.endArray();
      }, (v) {
        final array = v.asArray ?? _wrong(v, 'array');
        return [
          for (var i = 0; i < array.length; i++) _readItem(item, array[i], i)
        ];
      }, (cursor) => cursor.list<T, T>(item));

  static FleeceCodec<Map<String, T>> map<T>(FleeceCodec<T> item) =>
      FleeceCodec._bound((e, values) {
        e.beginDict();
        for (final key in _names(values)) {
          e.writeKey(key);
          item.write(e, values[key] as T);
        }
        e.endDict();
      },
          (v) => <String, T>{
                for (final entry in dictionary(v).entries)
                  entry.key: _readItem(item, entry.value, entry.key)
              },
          (cursor) => cursor.map<T, T>(item));

  static T _readItem<T>(FleeceCodec<T> codec, ValueRef ref, Object key) {
    try {
      return codec.read(ref);
    } on FormatException catch (error) {
      final at = key is int ? '[$key]' : key;
      throw FormatException(
          '$at: ${error.message}', null, error.offset ?? ref.position);
    }
  }

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
