part of '../fleece.dart';

/// An index key in the bytewise ordering of SurrealDB values.
Uint8List encodeKey(Object? value) {
  final out = BytesBuilder();
  encodeKeyInto(value, out);
  return out.takeBytes();
}

/// Append one self-delimiting component to a compound index key.
void encodeKeyInto(Object? value, BytesBuilder out) =>
    _KeyWriter(out).write(value);

final class _KeyWriter {
  _KeyWriter(this.out);
  final BytesBuilder out;
  void word(BigInt n, int width, {bool signed = false}) {
    if (signed) n ^= BigInt.one << (width * 8 - 1);
    out.add(_little(n, width).reversed.toList());
  }

  void text(List<int> bytes) {
    for (final b in bytes) {
      out.addByte(b);
      if (b == 0) out.addByte(255);
    }
    out.add(const [0, 0]);
  }

  void tagged(int tag, String s) {
    out.addByte(tag);
    text(_utf8(s));
  }

  void array(List items) {
    for (final item in items) {
      write(item);
    }
    out.addByte(0);
  }

  void object(Map fields) {
    for (final k in _names(fields)) {
      out.addByte(1);
      text(_utf8(k));
      write(fields[k]);
    }
    out.addByte(0);
  }

  void bound(FleeceBound b, void Function(Object?) put) {
    out.addByte(1 + b.flag);
    if (b.flag != 0) put(b.value);
  }

  void record(Object? v) {
    switch (v) {
      case int() || BigInt():
        out.addByte(1);
        word(_integer(v!), 8, signed: true);
      case String():
        tagged(2, v);
      case FleeceUuid():
        out.addByte(3);
        out.add(v.bytes);
      case List():
        out.addByte(4);
        array(v);
      case Map():
        out.addByte(5);
        object(v);
      case FleeceRange():
        out.addByte(6);
        bound(v.start, record);
        bound(v.end, record);
      default:
        throw ArgumentError.value(v, 'record key');
    }
  }

  void decimal(BigInt n, int scale) {
    if (n == BigInt.zero) {
      out.addByte(2);
      return;
    }
    final digits = n.abs().toString();
    out.addByte(n.isNegative ? 1 : 3);
    final exp = BigInt.from(digits.length - 1 - scale) ^ (BigInt.one << 63);
    final xor = n.isNegative ? 255 : 0;
    for (final b in _little(exp, 8).reversed) {
      out.addByte(b ^ xor);
    }
    var end = digits.length;
    while (digits.codeUnitAt(end - 1) == 48) {
      end--;
    }
    for (var i = 0; i < end; i++) {
      out.addByte((digits.codeUnitAt(i) - 47) ^ xor);
    }
    out.addByte(xor);
  }

  void number(double v) {
    if (!v.isFinite) {
      out.addByte(v.isNaN
          ? 5
          : v.isNegative
              ? 0
              : 4);
      return;
    }
    final bits = _doubleBits(v), bias = ((bits >> 52).toInt() & 2047);
    var m = bits.toUnsigned(52);
    if (bias != 0) m |= BigInt.one << 52;
    if (v.isNegative) m = -m;
    final e = bias == 0 ? -1074 : bias - 1075;
    if (e >= 0) {
      decimal(m << e, 0);
    } else {
      decimal(m * BigInt.from(5).pow(-e), -e);
    }
  }

  void float(double value) {
    final n = value == 0 ? BigInt.zero : _doubleBits(value);
    word(n.bitLength == 64 ? ~n : n ^ (BigInt.one << 63), 8);
  }

  void points(Iterable<FleecePoint> points) {
    for (final (x, y) in points) {
      out.addByte(1);
      float(x);
      float(y);
    }
    out.addByte(0);
  }

  void counts(Iterable<int> counts) {
    for (final n in counts) {
      out.addByte(1);
      word(BigInt.from(n), 8);
    }
    out.addByte(0);
  }

  void geometry(FleeceGeometry g) {
    Iterable<FleeceLine> rings(FleecePolygon p) => [...p.skip(1), p.first];
    Iterable<int> shape(FleecePolygon p) =>
        [p.length - 1, ...rings(p).map((r) => r.length)];
    out.addByte(g.type.index + 1);
    final coords = g.coordinates;
    switch (g.type) {
      case GeometryType.point:
        points([coords as FleecePoint]);
      case GeometryType.line || GeometryType.multiPoint:
        points(coords as FleeceLine);
      case GeometryType.polygon:
        final p = coords as FleecePolygon;
        points(rings(p).expand((r) => r));
        counts(shape(p));
      case GeometryType.multiLine:
        final lines = coords as List<FleeceLine>;
        points(lines.expand((r) => r));
        counts(lines.map((r) => r.length));
      case GeometryType.multiPolygon:
        final polys = coords as List<FleecePolygon>;
        points(polys.expand(rings).expand((r) => r));
        counts([polys.length, ...polys.expand(shape)]);
      case GeometryType.collection:
        for (final child in coords as List<FleeceGeometry>) {
          out.addByte(1);
          geometry(child);
        }
        out.addByte(0);
    }
  }

  void write(Object? v) {
    switch (v) {
      case FleeceNone():
        out.addByte(1);
      case null:
        out.addByte(2);
      case bool():
        out.add([3, v ? 1 : 0]);
      case int() || BigInt() when v is BigInt || _wireInt(v):
        out.addByte(4);
        decimal(_bounded(_integer(v), 64, signed: true), 0);
      case FleeceInt():
        out.addByte(4);
        decimal(v.value, 0);
      case double():
        out.addByte(4);
        number(v);
      case FleeceFloat16():
        out.addByte(4);
        number(v.value);
      case FleeceFloat32():
        out.addByte(4);
        number(v.value);
      case FleeceFloat64():
        out.addByte(4);
        number(v.value);
      case FleeceBigDecimal():
        out.addByte(4);
        decimal(v.coefficient, v.scale);
      case FleeceDecimal():
        out.addByte(4);
        decimal(v.negative ? -v.mantissa : v.mantissa, v.scale);
      case String():
        tagged(5, v);
      case FleeceText():
        tagged(5, v.text);
      case FleeceSeconds():
        final duration = v.kind == ExtKind.duration;
        out.addByte(duration
            ? 6
            : v.kind == ExtKind.datetime
                ? 7
                : 21);
        word(v.seconds, 8, signed: !duration);
        word(BigInt.from(v.nanoseconds), 4);
      case FleeceUuid():
        out.addByte(8);
        out.add(v.bytes);
      case Uint8List():
        out.addByte(13);
        text(v);
      case List():
        out.addByte(9);
        array(v);
      case FleeceSet():
        out.addByte(10);
        final sorted = SplayTreeSet<Uint8List>(_compareBytes)
          ..addAll(v.members.map(encodeKey));
        sorted.forEach(out.add);
        out.addByte(0);
      case Map():
        out.addByte(11);
        object(v);
      case FleeceGeometry():
        out.addByte(12);
        geometry(v);
      case FleeceTable():
        tagged(14, v.name);
        out.addByte(0);
      case FleeceRecordId():
        tagged(14, v.table);
        out.addByte(1);
        record(v.key);
      case FleeceFile():
        tagged(16, v.bucket);
        text(_utf8(v.key));
      case FleeceRange():
        out.addByte(17);
        bound(v.start, write);
        bound(v.end, write);
      case FleeceRegex():
        tagged(18, v.pattern);
      case FleeceDate():
        out.addByte(19);
        word(BigInt.from(v.days), 8, signed: true);
      case FleeceTime():
        out.addByte(20);
        word(BigInt.from(v.nanoseconds), 8);
      case FleeceInterval():
        out.addByte(22);
        final days =
            BigInt.from(v.months) * BigInt.from(30) + BigInt.from(v.days);
        word(days * BigInt.from(86400000000) + v.microseconds, 16,
            signed: true);
      case FleeceVector():
        out.addByte(23);
        for (var i = 0; i < v.length; i++) {
          out.addByte(1);
          float(v[i]);
        }
        out.addByte(0);
      default:
        throw ArgumentError.value(v, 'value');
    }
  }
}
