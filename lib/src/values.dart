part of '../fleece.dart';

/// A standard Fleece float32, including its exact IEEE 754 NaN payload.
final class FleeceFloat32 {
  FleeceFloat32(double value)
      : bits = (ByteData(4)..setFloat32(0, value, _le)).getUint32(0, _le);
  FleeceFloat32.fromBits(this.bits) {
    RangeError.checkValueInInterval(bits, 0, 0xffffffff);
  }
  final int bits;
  double get value => (ByteData(4)..setUint32(0, bits, _le)).getFloat32(0, _le);
  @override
  bool operator ==(Object other) =>
      other is FleeceFloat32 && value == other.value;
  @override
  int get hashCode => value.hashCode;
}

/// Explicit double for backends on which 1 and 1.0 are the same Dart object.
final class FleeceFloat64 {
  const FleeceFloat64(this.value) : _bits = null;
  FleeceFloat64.fromBits(BigInt bits)
      : _bits = _bounded(bits, 64, signed: false),
        value = ByteData.sublistView(_little(bits, 8)).getFloat64(0, _le);
  final double value;
  final BigInt? _bits;
  BigInt get bits => _bits ?? _doubleBits(value);
  @override
  bool operator ==(Object other) =>
      other is FleeceFloat64 && value == other.value;
  @override
  int get hashCode => value.hashCode;
}

BigInt _doubleBits(double value) =>
    _fromLittle((ByteData(8)..setFloat64(0, value, _le)).buffer.asUint8List());

/// A typed value introduced by the 0x31 extension marker.
sealed class FleeceValue {
  const FleeceValue();
  ExtKind get kind;
  Object? get _payload;
  Object? get _equality => _payload;
  void _writePayload(Encoder e) => e.writeValue(_payload);
  @override
  bool operator ==(Object other) =>
      other is FleeceValue &&
      kind == other.kind &&
      _equal(_equality, other._equality);
  @override
  int get hashCode => Object.hash(kind, _valueHash(_equality));
}

final class FleeceNone extends FleeceValue {
  const FleeceNone();
  @override
  ExtKind get kind => ExtKind.none;
  @override
  Object? get _payload => null;
}

/// An IEEE 754 binary16. All bits, including NaN payloads, are significant.
final class FleeceFloat16 extends FleeceValue {
  factory FleeceFloat16.fromF32(double v) =>
      FleeceFloat16.fromF32Bits(FleeceFloat32(v).bits);
  factory FleeceFloat16.fromF32Bits(int bits) {
    RangeError.checkValueInInterval(bits, 0, 0xffffffff);
    final sign = (bits >>> 16) & 0x8000, fraction = bits & 0x7fffff;
    final exp = ((bits >>> 23) & 255) - 112;
    int rounded(int all, int drop) {
      final kept = all >> drop,
          rest = all & ((1 << drop) - 1),
          half = 1 << (drop - 1);
      return kept + (rest > half || rest == half && kept.isOdd ? 1 : 0);
    }

    final int magnitude;
    if (exp == 143 && fraction != 0) {
      magnitude = 0x7e00 | (fraction >> 13);
    } else if (exp >= 31) {
      magnitude = 0x7c00;
    } else if (exp <= 0) {
      magnitude = exp < -10 ? 0 : rounded(fraction | 0x800000, 14 - exp);
    } else {
      magnitude = (exp << 10) + rounded(fraction, 13);
    }
    return FleeceFloat16.fromBits(sign | magnitude);
  }
  static FleeceFloat16? fromF64(double v) {
    if (v.isNaN) return FleeceFloat16.fromBits(0x7e00);
    final half = FleeceFloat16.fromF32(v);
    return half.value == v ? half : null;
  }

  int get f32Bits {
    final frac = bits & 1023, sign = (bits & 0x8000) * 65536;
    return bits & 0x7c00 == 0x7c00
        ? sign + 0x7f800000 + (frac == 0 ? 0 : (frac << 13) | 0x400000)
        : FleeceFloat32(_half(bits)).bits;
  }

  FleeceFloat16.fromBits(this.bits) {
    RangeError.checkValueInInterval(bits, 0, 65535);
  }
  final int bits;
  double get value => _half(bits);
  @override
  ExtKind get kind => ExtKind.f16;
  @override
  void _writePayload(Encoder e) => e.writeInt(bits);
  @override
  int get _payload => bits;
}

/// A width-tagged integer. Its value is exact on native and web backends.
final class FleeceInt extends FleeceValue {
  FleeceInt._(this.kind, Object value, int bits, bool signed)
      : value = _bounded(_integer(value), bits, signed: signed);
  FleeceInt._decoded(this.kind, this.value);
  FleeceInt.i8(int value) : this._(ExtKind.i8, value, 8, true);
  FleeceInt.u8(int value) : this._(ExtKind.u8, value, 8, false);
  FleeceInt.i16(int value) : this._(ExtKind.i16, value, 16, true);
  FleeceInt.u16(int value) : this._(ExtKind.u16, value, 16, false);
  FleeceInt.i32(int value) : this._(ExtKind.i32, value, 32, true);
  FleeceInt.u32(int value) : this._(ExtKind.u32, value, 32, false);
  FleeceInt.u64(Object value) : this._(ExtKind.u64, value, 64, false);
  @override
  final ExtKind kind;
  final BigInt value;
  @override
  Object get _payload => value;
  @override
  void _writePayload(Encoder e) =>
      e._boundedInteger(value, kind == ExtKind.u64);
}

/// The 96-bit rust_decimal mantissa, its sign (also for zero), and scale.
final class FleeceDecimal extends FleeceValue {
  static const maxScale = 28;
  factory FleeceDecimal.parse(String text) {
    final (n, scale, neg) = _decimalParts(text);
    if (scale > maxScale || n.bitLength > 96) throw ParseError(text);
    return FleeceDecimal(n, scale, negative: neg);
  }
  factory FleeceDecimal.fromBytes(Uint8List b) {
    if (b.length != 16 ||
        b[0] != 0 ||
        b[1] != 0 ||
        b[2] > 28 ||
        b[3] & 127 != 0) throw const FormatException('Invalid decimal');
    return FleeceDecimal(_fromLittle(Uint8List.sublistView(b, 4)), b[2],
        negative: b[3] != 0);
  }
  Uint8List toBytes() => _payload;
  @override
  String toString() => _decimalText(mantissa, scale, negative);
  FleeceDecimal(this.mantissa, this.scale, {this.negative = false}) {
    _bounded(mantissa, 96, signed: false);
    RangeError.checkValueInInterval(scale, 0, 28);
  }
  final BigInt mantissa;
  final int scale;
  final bool negative;
  @override
  ExtKind get kind => ExtKind.decimal;
  @override
  void _writePayload(Encoder e) {
    final at = e._dataSpace(16);
    e._out.bytes[at + 2] = scale;
    e._out.bytes[at + 3] = negative ? 128 : 0;
    _putLittle(e._out.data, at + 4, mantissa, 12);
  }

  @override
  Uint8List get _payload => Uint8List.fromList(
      [0, 0, scale, negative ? 128 : 0, ..._little(mantissa, 12)]);
}

final class FleeceBigDecimal extends FleeceValue {
  static const maxScale = 294910;
  factory FleeceBigDecimal.parse(String text) {
    final (n, scale, neg) = _decimalParts(text);
    if (scale > maxScale) throw ParseError(text);
    return FleeceBigDecimal(neg ? -n : n, scale);
  }
  factory FleeceBigDecimal.fromBytes(Uint8List bytes, int scale) =>
      FleeceBigDecimal(_fromLittle(bytes, signed: true), scale);
  Uint8List get coefficientBytes => _bytes;
  bool get isNegative => coefficient.isNegative;
  @override
  String toString() => _decimalText(coefficient.abs(), scale, isNegative);
  FleeceBigDecimal(this.coefficient, this.scale) {
    RangeError.checkValueInInterval(scale, 0, 294910);
  }
  final BigInt coefficient;
  final int scale;
  @override
  ExtKind get kind => ExtKind.bigDecimal;
  Uint8List get _bytes =>
      _little(coefficient, (coefficient.bitLength + 8) ~/ 8);
  @override
  Object get _payload => [scale, _bytes];
  @override
  void _writePayload(Encoder e) => e
    ..beginArray()
    ..writeUint(scale)
    .._coefficient(coefficient)
    ..endArray();
}

/// Duration uses unsigned seconds. Datetime and timestamp use signed seconds.
sealed class FleeceSeconds extends FleeceValue {
  FleeceSeconds._(this.kind, Object seconds, this.nanoseconds)
      : seconds =
            _bounded(_integer(seconds), 64, signed: kind != ExtKind.duration) {
    RangeError.checkValueInInterval(nanoseconds, 0, 999999999);
  }
  factory FleeceSeconds.duration(Object seconds, int nanos) = FleeceDuration;
  factory FleeceSeconds.datetime(Object seconds, int nanos) = FleeceDatetime;
  factory FleeceSeconds.timestamp(Object seconds, int nanos) = FleeceTimestamp;
  @override
  final ExtKind kind;
  final BigInt seconds;
  final int nanoseconds;
  @override
  void _writePayload(Encoder e) {
    final at = e._dataSpace(12);
    _putLittle(e._out.data, at, seconds, 8);
    e._out.data.setUint32(at + 8, nanoseconds, _le);
  }

  @override
  Uint8List get _payload {
    final bytes = Uint8List(12)..setAll(0, _little(seconds, 8));
    ByteData.sublistView(bytes).setUint32(8, nanoseconds, _le);
    return bytes;
  }
}

final class FleeceDuration extends FleeceSeconds {
  FleeceDuration(Object seconds, int nanos)
      : super._(ExtKind.duration, seconds, nanos);
}

final class FleeceDatetime extends FleeceSeconds {
  FleeceDatetime(Object seconds, int nanos)
      : super._(ExtKind.datetime, seconds, nanos);
}

final class FleeceTimestamp extends FleeceSeconds {
  FleeceTimestamp(Object seconds, int nanos)
      : super._(ExtKind.timestamp, seconds, nanos);
}

final class FleeceUuid extends FleeceValue {
  factory FleeceUuid.parse(String text) {
    if (!RegExp(r'^[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')
        .hasMatch(text)) throw ParseError(text);
    final s = text.replaceAll('-', '');
    return FleeceUuid(Uint8List.fromList([
      for (var i = 0; i < 32; i += 2)
        int.parse(s.substring(i, i + 2), radix: 16)
    ]));
  }
  @override
  String toString() {
    final s = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return [
      s.substring(0, 8),
      s.substring(8, 12),
      s.substring(12, 16),
      s.substring(16, 20),
      s.substring(20)
    ].join('-');
  }

  FleeceUuid(Uint8List bytes)
      : bytes = Uint8List.fromList(bytes).asUnmodifiableView() {
    if (bytes.length != 16) throw ArgumentError('UUID must contain 16 bytes');
  }
  final Uint8List bytes;
  @override
  ExtKind get kind => ExtKind.uuid;
  @override
  void _writePayload(Encoder e) => e.writeData(bytes);
  @override
  Uint8List get _payload => bytes;
}

final class FleeceDate extends FleeceValue {
  FleeceDate(this.days) {
    _bounded(BigInt.from(days), 32, signed: true);
  }
  final int days;
  @override
  ExtKind get kind => ExtKind.date;
  @override
  void _writePayload(Encoder e) => e.writeInt(days);
  @override
  int get _payload => days;
}

final class FleeceTime extends FleeceValue {
  static const maxNanos = 86400000000000;
  FleeceTime(this.nanoseconds) {
    RangeError.checkValueInInterval(nanoseconds, 0, 86400000000000);
  }
  final int nanoseconds;
  @override
  ExtKind get kind => ExtKind.time;
  @override
  int get _payload => nanoseconds;
  @override
  void _writePayload(Encoder e) => e.writeUint(nanoseconds);
}

final class FleeceInterval extends FleeceValue {
  FleeceInterval(this.months, this.days, Object microseconds)
      : microseconds = _bounded(_integer(microseconds), 64, signed: true) {
    _bounded(BigInt.from(months), 32, signed: true);
    _bounded(BigInt.from(days), 32, signed: true);
  }
  final int months, days;
  final BigInt microseconds;
  @override
  ExtKind get kind => ExtKind.interval;
  @override
  void _writePayload(Encoder e) {
    final at = e._dataSpace(16);
    final d = e._out.data;
    d.setInt32(at, months, _le);
    d.setInt32(at + 4, days, _le);
    _putLittle(d, at + 8, microseconds, 8);
  }

  @override
  Uint8List get _payload {
    final data = ByteData(16)
      ..setInt32(0, months, _le)
      ..setInt32(4, days, _le);
    return data.buffer.asUint8List()..setAll(8, _little(microseconds, 8));
  }
}

final class FleeceTable extends FleeceValue {
  const FleeceTable(this.name);
  final String name;
  @override
  ExtKind get kind => ExtKind.table;
  @override
  void _writePayload(Encoder e) => e.writeString(name);
  @override
  String get _payload => name;
}

final class FleeceRegex extends FleeceValue {
  const FleeceRegex(this.pattern);
  final String pattern;
  @override
  ExtKind get kind => ExtKind.regex;
  @override
  void _writePayload(Encoder e) => e.writeString(pattern);
  @override
  String get _payload => pattern;
}

final class FleeceFile extends FleeceValue {
  const FleeceFile(this.bucket, this.key);
  final String bucket, key;
  @override
  ExtKind get kind => ExtKind.file;
  @override
  void _writePayload(Encoder e) => e
    ..beginArray()
    ..writeString(bucket)
    ..writeString(key)
    ..endArray();
  @override
  Object get _payload => [bucket, key];
}

final class FleeceRecordId extends FleeceValue {
  FleeceRecordId(this.table, Object key)
      : key = key is RecordIdKey ? key.value : RecordIdKey(key).value;
  final String table;
  final Object key;
  @override
  ExtKind get kind => ExtKind.recordId;
  @override
  void _writePayload(Encoder e) => e
    ..beginArray()
    ..writeString(table)
    ..writeValue(key)
    ..endArray();
  @override
  Object get _payload => [table, key];
}

/// A key that can be stored in a record ID. Native arrays and objects may
/// contain arbitrary Fleece values. Each bound of a range must itself be a key.
final class RecordIdKey {
  factory RecordIdKey(Object value) =>
      tryFrom(value) ??
      (throw ArgumentError.value(value, 'value', 'Invalid record key'));
  const RecordIdKey._(this.value);
  final Object value;
  static RecordIdKey? tryFrom(Object? value) {
    if (value is RecordIdKey) return value;
    if (value is RecordIdKeyRange) return RecordIdKey._(value.toRange());
    return value != null && _recordKey(value) ? RecordIdKey._(value) : null;
  }

  @override
  bool operator ==(Object other) =>
      other is RecordIdKey && _equal(value, other.value);
  @override
  int get hashCode => _valueHash(value);
}

typedef FleeceObject = Map<String, Object?>;

bool _recordKey(Object? key) => switch (key) {
      int n => _wireInt(n) && BigInt.from(n).bitLength < 64,
      BigInt n => n.bitLength < 64,
      String() || FleeceUuid() => true,
      Map m => m.keys.every((k) => k is String),
      List() => key is! Uint8List,
      FleeceRange r =>
        [r.start, r.end].every((b) => b.flag == 0 || _recordKey(b.value)),
      _ => false,
    };

final class FleeceBound {
  const FleeceBound.unbounded()
      : flag = 0,
        value = null;
  const FleeceBound.included(this.value) : flag = 1;
  const FleeceBound.excluded(this.value) : flag = 2;
  final int flag;
  final Object? value;
}

final class FleeceRange extends FleeceValue {
  const FleeceRange(this.start, this.end);
  final FleeceBound start, end;
  @override
  ExtKind get kind => ExtKind.range;
  @override
  void _writePayload(Encoder e) => e
    ..beginArray()
    ..writeInt(start.flag | end.flag << 2)
    ..writeValue(start.value)
    ..writeValue(end.value)
    ..endArray();
  @override
  Object get _payload => [start.flag | end.flag << 2, start.value, end.value];
}

/// A record key range restricts both endpoints to record key values.
final class RecordIdKeyRange {
  RecordIdKeyRange(FleeceBound start, FleeceBound end)
      : start = _keyBound(start),
        end = _keyBound(end);
  final FleeceBound start, end;
  static FleeceBound _keyBound(FleeceBound bound) {
    if (bound.flag == 0) return bound;
    final key = RecordIdKey.tryFrom(bound.value);
    if (key == null)
      throw ArgumentError.value(bound.value, 'bound', 'Invalid record key');
    return bound.flag == 1
        ? FleeceBound.included(key.value)
        : FleeceBound.excluded(key.value);
  }

  FleeceRange toRange() => FleeceRange(start, end);
}

/// The reference stores members in the supplied order.
final class FleeceSet extends FleeceValue {
  FleeceSet(Iterable<Object?> members) : members = List.unmodifiable(members);
  FleeceSet._owned(List<Object?> values)
      : members = UnmodifiableListView(values);
  final List<Object?> members;
  @override
  ExtKind get kind => ExtKind.set;
  @override
  Object get _payload => members;
  @override
  void _writePayload(Encoder e) => e._array(members);
}

typedef FleecePoint = (double, double);

enum GeometryType {
  point,
  line,
  polygon,
  multiPoint,
  multiLine,
  multiPolygon,
  collection
}

Uint8List _points(List<FleecePoint> points) {
  if (points is _PackedPoints && Endian.host == _le) {
    return Uint8List.sublistView(points.xy).asUnmodifiableView();
  }
  final data = ByteData(16 * points.length);
  for (var i = 0; i < points.length; i++) {
    data.setFloat64(16 * i, points[i].$1, _le);
    data.setFloat64(16 * i + 8, points[i].$2, _le);
  }
  return data.buffer.asUint8List().asUnmodifiableView();
}

// An owned coordinate buffer also provides the public read-only list of pairs.
// The source document can be released or reused as soon as it has been read.
final class _PackedPoints extends UnmodifiableListView<FleecePoint> {
  _PackedPoints(this.xy)
      : super(Iterable.generate(xy.length ~/ 2, (i) => _at(xy, i)));
  final Float64List xy;
  // Repeated indexed access reuses each materialized point. A plain read or
  // re-encode of the geometry only needs the packed buffer.
  late final _pairs = List<FleecePoint?>.filled(length, null);
  static FleecePoint _at(Float64List xy, int i) => (xy[i * 2], xy[i * 2 + 1]);

  @override
  int get length => xy.length ~/ 2;

  @override
  @pragma('vm:prefer-inline')
  FleecePoint operator [](int index) => _pairs[index] ??= _at(xy, index);
}

FleeceLine _ownedPoints(Uint8List bytes) {
  final Float64List xy;
  if (Endian.host == _le) {
    xy = Float64List.sublistView(bytes);
  } else {
    xy = Float64List(bytes.length ~/ 8);
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < xy.length; i++) {
      xy[i] = data.getFloat64(8 * i, _le);
    }
  }
  return _PackedPoints(xy.asUnmodifiableView());
}

typedef FleeceLine = List<FleecePoint>;
typedef FleecePolygon = List<FleeceLine>;

/// The coordinates are ordinary Dart (x, y) records. The first polygon
/// ring is its exterior, followed by zero or more interior rings.
final class FleeceGeometry<T extends Object> extends FleeceValue {
  const FleeceGeometry._(this.type, this.coordinates, this._pack);
  static FleeceGeometry<FleecePoint> point(double x, double y) =>
      FleeceGeometry._(GeometryType.point, (x, y), (p) => _points([p]));
  static FleeceLine _freezeLine(FleeceLine points) =>
      points is _PackedPoints ? points : List.unmodifiable(points);
  static FleeceGeometry<FleeceLine> line(FleeceLine points) =>
      FleeceGeometry._(GeometryType.line, _freezeLine(points), _points);
  static FleeceGeometry<FleeceLine> multiPoint(FleeceLine points) =>
      FleeceGeometry._(GeometryType.multiPoint, _freezeLine(points), _points);

  static FleecePolygon _rings(FleecePolygon rings) =>
      List.unmodifiable(rings.map(_freezeLine));
  static FleecePolygon _polygon(FleecePolygon rings) {
    if (rings.isEmpty) throw ArgumentError('A polygon needs an exterior ring');
    return _rings(rings);
  }

  static List<Uint8List> _packRings(FleecePolygon rings) =>
      rings.map(_points).toList();
  static FleeceGeometry<FleecePolygon> polygon(FleecePolygon rings) =>
      FleeceGeometry._(GeometryType.polygon, _polygon(rings), _packRings);
  static FleeceGeometry<List<FleeceLine>> multiLine(List<FleeceLine> lines) =>
      FleeceGeometry._(GeometryType.multiLine, _rings(lines), _packRings);
  static FleeceGeometry<List<FleecePolygon>> multiPolygon(
          List<FleecePolygon> polygons) =>
      FleeceGeometry._(
          GeometryType.multiPolygon,
          List.unmodifiable(polygons.map(_polygon)),
          (all) => all.map(_packRings).toList());
  static FleeceGeometry<List<FleeceGeometry>> collection(
          List<FleeceGeometry> geometries) =>
      FleeceGeometry._(GeometryType.collection, List.unmodifiable(geometries),
          (items) => items);

  final GeometryType type;
  final T coordinates;
  final Object Function(T) _pack;
  @override
  ExtKind get kind => ExtKind.geometry;
  @override
  void _writePayload(Encoder e) {
    e.beginArray();
    e.writeInt(type.index);
    final c = coordinates;
    switch (type) {
      case GeometryType.point:
        final point = c as FleecePoint;
        final at = e._dataSpace(16);
        e._out.data.setFloat64(at, point.$1, _le);
        e._out.data.setFloat64(at + 8, point.$2, _le);
      case GeometryType.line || GeometryType.multiPoint:
        e._line(c as FleeceLine);
      case GeometryType.polygon || GeometryType.multiLine:
        e._rings(c as FleecePolygon);
      case GeometryType.multiPolygon:
        e.beginArray();
        for (final polygon in c as List<FleecePolygon>) {
          e._rings(polygon);
        }
        e.endArray();
      case GeometryType.collection:
        e.writeValue(c);
    }
    e.endArray();
  }

  @override
  Object get _payload => [type.index, _pack(coordinates)];
  @override
  Object get _equality => [type, coordinates];
}

enum VectorElement { f32, f64, f16, i8, bit }

enum _VectorMetric { dot, l2Squared, cosine }

final _i8Step = _asF32(1.0 / 127);
final _i8Scale = Float32x4.splat(_i8Step);
final _bitLanes = List.generate(16, (bits) {
  double sign(int mask) => bits & mask == 0 ? -1.0 : 1.0;
  return Float32x4(sign(1), sign(2), sign(4), sign(8));
});

/// Packed elements in little-endian order, with bit dimensions LSB first.
final class FleeceVector extends FleeceValue {
  FleeceVector._(this.element, this.length, Uint8List bytes)
      : bytes = bytes.asUnmodifiableView();
  factory FleeceVector.quantizedF16(List<double> values) =>
      FleeceVector.f16Bits(
          [for (final v in values) FleeceFloat16.fromF32(v).bits]);
  factory FleeceVector.quantizedI8(List<double> values) => FleeceVector.i8([
        for (final v in values)
          v.isNaN ? 0 : _asF32(_asF32(v) * 127).clamp(-127.0, 127.0).round()
      ]);
  factory FleeceVector.quantizedBits(List<double> values) {
    final bits = Uint8List((values.length + 7) ~/ 8);
    for (var i = 0; i < values.length; i++) {
      if (_asF32(values[i]) > 0) bits[i ~/ 8] |= 1 << (i % 8);
    }
    return FleeceVector._(VectorElement.bit, values.length, bits);
  }
  factory FleeceVector.f32(List<double> values) {
    final data = ByteData(values.length * 4);
    for (var i = 0; i < values.length; i++) {
      data.setFloat32(i * 4, values[i], _le);
    }
    return FleeceVector._(
        VectorElement.f32, values.length, data.buffer.asUint8List());
  }
  factory FleeceVector.f64(List<double> values) {
    final data = ByteData(values.length * 8);
    for (var i = 0; i < values.length; i++) {
      data.setFloat64(i * 8, values[i], _le);
    }
    return FleeceVector._(
        VectorElement.f64, values.length, data.buffer.asUint8List());
  }
  factory FleeceVector.f16Bits(List<int> values) {
    final data = ByteData(values.length * 2);
    for (var i = 0; i < values.length; i++) {
      data.setUint16(
          i * 2, RangeError.checkValueInInterval(values[i], 0, 65535), _le);
    }
    return FleeceVector._(
        VectorElement.f16, values.length, data.buffer.asUint8List());
  }
  factory FleeceVector.i8(List<int> values) {
    final bytes = Uint8List(values.length);
    for (var i = 0; i < values.length; i++) {
      bytes[i] = RangeError.checkValueInInterval(values[i], -128, 127);
    }
    return FleeceVector._(VectorElement.i8, values.length, bytes);
  }
  factory FleeceVector.bits(Uint8List bytes, int length) {
    RangeError.checkNotNegative(length);
    final packed = Uint8List((length + 7) ~/ 8);
    packed.setRange(0, math.min(packed.length, bytes.length), bytes);
    if (length % 8 != 0) packed.last &= (1 << (length % 8)) - 1;
    return FleeceVector._(VectorElement.bit, length, packed);
  }
  final VectorElement element;
  final int length;
  final Uint8List bytes;

  /// The element as f32, including the reference's i8 and bit dequantization.
  double operator [](int index) {
    RangeError.checkValidIndex(index, this, 'index', length);
    return _elementAt(ByteData.sublistView(bytes), index);
  }

  double _elementAt(ByteData data, int index) => switch (element) {
        VectorElement.f32 => data.getFloat32(index * 4, _le),
        VectorElement.f64 => _asF32(data.getFloat64(index * 8, _le)),
        VectorElement.f16 => _half(data.getUint16(index * 2, _le)),
        VectorElement.i8 => _asF32(data.getInt8(index) * _i8Step),
        VectorElement.bit =>
          bytes[index ~/ 8] & (1 << (index % 8)) != 0 ? 1.0 : -1.0,
      };

  // Fleece vector payloads need not be aligned even to an f32 boundary.
  Float32x4 _four(ByteData data, int i) => switch (element) {
        VectorElement.f32 => Float32x4(
            data.getFloat32(4 * i, _le),
            data.getFloat32(4 * i + 4, _le),
            data.getFloat32(4 * i + 8, _le),
            data.getFloat32(4 * i + 12, _le)),
        VectorElement.f64 => Float32x4(
            data.getFloat64(8 * i, _le),
            data.getFloat64(8 * i + 8, _le),
            data.getFloat64(8 * i + 16, _le),
            data.getFloat64(8 * i + 24, _le)),
        VectorElement.f16 => Float32x4(
            _half(data.getUint16(2 * i, _le)),
            _half(data.getUint16(2 * i + 2, _le)),
            _half(data.getUint16(2 * i + 4, _le)),
            _half(data.getUint16(2 * i + 6, _le))),
        VectorElement.i8 => Float32x4(
                data.getInt8(i).toDouble(),
                data.getInt8(i + 1).toDouble(),
                data.getInt8(i + 2).toDouble(),
                data.getInt8(i + 3).toDouble()) *
            _i8Scale,
        VectorElement.bit => _bitLanes[(bytes[i ~/ 8] >> (i % 8)) & 15],
      };

  @override
  Object get _equality {
    if (element != VectorElement.f32 && element != VectorElement.f64)
      return _payload;
    final data = ByteData.sublistView(bytes);
    return [
      element,
      for (var i = 0; i < length; i++)
        FleeceFloat64(element == VectorElement.f32
            ? data.getFloat32(i * 4, _le)
            : data.getFloat64(i * 8, _le))
    ];
  }

  @override
  ExtKind get kind => ExtKind.vector;
  @override
  void _writePayload(Encoder e) {
    final bits = element == VectorElement.bit;
    final header = bits ? 2 : 1;
    if (header + bytes.length == 1) {
      e._word(0x5100 + element.index);
      return;
    }
    final at = e._dataSpace(header + bytes.length);
    final out = e._out.bytes;
    out[at] = element.index;
    out.setRange(at + header, at + header + bytes.length, bytes);
    if (bits) {
      final padding = bytes.length * 8 - length;
      out[at + 1] = padding;
      if (padding != 0) out[at + header + bytes.length - 1] &= 255 >> padding;
    }
  }

  @override
  Uint8List get _payload {
    final bits = element == VectorElement.bit;
    final header = bits ? 2 : 1;
    final data = Uint8List(header + bytes.length)
      ..[0] = element.index
      ..setAll(header, bytes);
    if (bits) {
      data[1] = bytes.length * 8 - length;
      if (length % 8 != 0) data.last &= (1 << (length % 8)) - 1;
    }
    return data;
  }

  static bool _fits(Uint8List b) {
    if (b.isEmpty || b.first >= VectorElement.values.length) return false;
    if (b[0] == VectorElement.bit.index) {
      return b.length >= 2 && b[1] < 8 && b[1] <= (b.length - 2) * 8;
    }
    return (b.length - 1) % [4, 8, 2, 1][b.first] == 0;
  }

  static FleeceVector _fromBytes(Uint8List b, {bool owned = false}) {
    final element = VectorElement.values[b.first];
    final bits = element == VectorElement.bit;
    final view = Uint8List.sublistView(b, bits ? 2 : 1);
    final bytes = owned ? Uint8List.fromList(view) : view;
    final length = bits
        ? bytes.length * 8 - b[1]
        : bytes.length ~/ const [4, 8, 2, 1][element.index];
    if (owned && bits && b[1] != 0) bytes.last &= 255 >> b[1];
    return FleeceVector._(element, length, bytes);
  }
}

// Typed-data stores round to f32 on both the VM and JavaScript. The scratch
// belongs to the isolate; the write and read contain no calls to user code.
final _f32Scratch = Float32List(1);
double _asF32(double value) {
  _f32Scratch[0] = value;
  return _f32Scratch[0];
}

double _half(int bits) {
  final sign = bits & 0x8000 == 0 ? 1.0 : -1.0;
  final exponent = (bits >> 10) & 31, fraction = bits & 1023;
  if (exponent == 31) {
    final f = (bits & 0x8000) * 65536 +
        0x7f800000 +
        (fraction == 0 ? 0 : 0x400000 | (fraction << 13));
    return FleeceFloat32.fromBits(f).value;
  }
  if (exponent == 0) return sign * fraction / 16777216.0;
  return sign * (1024 + fraction) * (1 << exponent) / 33554432.0;
}

bool _equal(Object? a, Object? b) {
  if (a is List && b is List) {
    if ((a is Uint8List) != (b is Uint8List) || a.length != b.length)
      return false;
    for (var i = 0; i < a.length; i++) {
      if (!_equal(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((k) => b.containsKey(k) && _equal(a[k], b[k]));
  }
  if (a is FleeceFloat32 && b is FleeceFloat32) return a.value == b.value;
  if (a is FleeceFloat64 || b is FleeceFloat64) {
    double? floating(Object? v) => v is FleeceFloat64
        ? v.value
        : v is double && !_wireInt(v)
            ? v
            : null;
    final left = floating(a), right = floating(b);
    return left != null && right != null && left == right;
  }
  if ((_wireInt(a) || a is BigInt) && (_wireInt(b) || b is BigInt))
    return _integer(a!) == _integer(b!);
  if (_wireInt(a) != _wireInt(b)) return false;
  return a == b;
}

int _valueHash(Object? v) => switch (v) {
      List items => Object.hashAll(items.map(_valueHash)),
      Map map => Object.hashAllUnordered(
          map.entries.map((e) => Object.hash(e.key, _valueHash(e.value)))),
      FleeceFloat32 f => f.value.hashCode,
      FleeceFloat64 f => f.value.hashCode,
      int n when _wireInt(n) => BigInt.from(n).hashCode,
      _ => v.hashCode,
    };

final class ParseError extends FormatException {
  const ParseError(String source) : super('Invalid Fleece value', source);
}

(BigInt, int, bool) _decimalParts(String text) {
  final match = RegExp(r'^(-?)([0-9]+)(?:\.([0-9]+))?$').firstMatch(text);
  if (match == null) throw ParseError(text);
  final fraction = match[3] ?? '';
  return (BigInt.parse(match[2]! + fraction), fraction.length, match[1] == '-');
}

String _decimalText(BigInt magnitude, int scale, bool negative) {
  final digits = magnitude.toString().padLeft(scale + 1, '0'),
      cut = digits.length - scale;
  return (negative ? '-' : '') +
      digits.substring(0, cut) +
      (scale == 0 ? '' : '.' + digits.substring(cut));
}

extension ElementWidth on VectorElement {
  int get bits => [32, 64, 16, 8, 1][index];
  String get wireName => this == VectorElement.bit ? 'bits' : name;
}

/// Packed vectors and document-backed vector views expose the same operations.
typedef VectorRef = FleeceVector;

extension VectorOperations on FleeceVector {
  bool get isEmpty => length == 0;
  double? get(int i) => i < 0 || i >= length ? null : this[i];
  List<double> toF32() => List.generate(length, (i) => this[i]);
  FleeceVector toVector() => element == VectorElement.bit
      ? FleeceVector.bits(bytes, length)
      : FleeceVector._(element, length, Uint8List.fromList(bytes));
  VectorRef? prefix(int dims) => dims < 0 || dims > length
      ? null
      : FleeceVector._(element, dims,
          Uint8List.sublistView(bytes, 0, (dims * element.bits + 7) ~/ 8));

  double? dot(List<double> query) => _measureVector(query, _VectorMetric.dot);
  double? l2Squared(List<double> query) =>
      _measureVector(query, _VectorMetric.l2Squared);
  double? cosine(List<double> query) =>
      _measureVector(query, _VectorMetric.cosine);

  double? _measureVector(List<double> query, _VectorMetric metric) {
    if (query.length != length) return null;
    final data = ByteData.sublistView(bytes);
    // Rust uses eight independent accumulators, reduced in lane order before
    // the scalar tail. Two groups of four retain the exact rounding order.
    final end = length - length % 8;
    final blocks = element == VectorElement.f32 &&
            Endian.host == _le &&
            bytes.offsetInBytes % 16 == 0
        ? Float32x4List.view(bytes.buffer, bytes.offsetInBytes, end ~/ 4)
        : null;
    final queries = query is Float32List && query.offsetInBytes % 16 == 0
        ? Float32x4List.view(query.buffer, query.offsetInBytes, end ~/ 4)
        : null;
    final sum = Float32x4List(2);
    final cosine = metric == _VectorMetric.cosine;
    final own = cosine ? Float32x4List(2) : null;
    final other = cosine ? Float32x4List(2) : null;
    for (var i = 0; i < end; i += 4) {
      final chunk = i ~/ 4, lane = chunk & 1;
      final a = blocks?[chunk] ?? _four(data, i);
      final b = queries?[chunk] ??
          Float32x4(query[i], query[i + 1], query[i + 2], query[i + 3]);
      if (metric == _VectorMetric.l2Squared) {
        final d = a - b;
        sum[lane] += d * d;
      } else {
        sum[lane] += a * b;
        if (cosine) {
          own![lane] += a * a;
          other![lane] += b * b;
        }
      }
    }
    double fold(Float32x4List pairs) {
      var total = 0.0;
      for (final v in pairs) {
        total = _asF32(total + v.x);
        total = _asF32(total + v.y);
        total = _asF32(total + v.z);
        total = _asF32(total + v.w);
      }
      return total;
    }

    var total = fold(sum);
    var aa = cosine ? fold(own!) : 0.0, bb = cosine ? fold(other!) : 0.0;
    for (var i = end; i < length; i++) {
      final a = _elementAt(data, i), b = _asF32(query[i]);
      if (metric == _VectorMetric.l2Squared) {
        final d = _asF32(a - b);
        total = _asF32(total + _asF32(d * d));
      } else {
        total = _asF32(total + _asF32(a * b));
        if (cosine) {
          aa = _asF32(aa + _asF32(a * a));
          bb = _asF32(bb + _asF32(b * b));
        }
      }
    }
    if (!cosine) return total;
    final divisor = _asF32(math.sqrt(_asF32(aa * bb)));
    return divisor > 0 ? _asF32(total / divisor) : 0.0;
  }

  int? hamming(VectorRef other) {
    if (element != VectorElement.bit ||
        other.element != element ||
        length != other.length) return null;
    var total = 0;
    for (var i = 0; i < bytes.length; i++) {
      var n = bytes[i] ^ other.bytes[i];
      if (i == bytes.length - 1 && length % 8 != 0)
        n &= (1 << (length % 8)) - 1;
      while (n != 0) {
        n &= n - 1;
        total++;
      }
    }
    return total;
  }
}
