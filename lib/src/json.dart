part of '../fleece.dart';

enum JsonErrorCode { syntax, unknownType, badValue, decode, encode }

final class JsonError extends FormatException {
  const JsonError(this.code, String message, [this.cause]) : super(message);
  final JsonErrorCode code;
  final Object? cause;
}

Never _badJson(String name) =>
    throw JsonError(JsonErrorCode.badValue, 'Invalid value for ' + name);

/// Native JSON values, with BigInt where a Dart int cannot hold a JSON integer.
/// On JavaScript [FleeceFloat64] preserves the distinction between 1 and 1.0.
Object? toJson(Object? v) {
  Map<String, Object?> typed(String name, Object? payload) =>
      {r'$' + name: payload};
  Object finite(double d) =>
      identical(1, 1.0) && d is int ? FleeceFloat64(d) : d;
  Object floating(double d) => d.isFinite
      ? finite(d)
      : d.isNaN
          ? 'NaN'
          : d.isNegative
              ? '-Infinity'
              : 'Infinity';
  Object? geoCoords(Object p) => switch (p) {
        (double x, double y) => [
            x.isFinite ? finite(x) : null,
            y.isFinite ? finite(y) : null
          ],
        List coords => coords.map((p) => geoCoords(p as Object)).toList(),
        _ => throw StateError('Invalid geometry coordinates'),
      };
  Map<String, Object?> geometry(FleeceGeometry g) =>
      g.type == GeometryType.collection
          ? {
              'type': 'GeometryCollection',
              'geometries':
                  (g.coordinates as List<FleeceGeometry>).map(geometry).toList()
            }
          : {
              'type': [
                'Point',
                'LineString',
                'Polygon',
                'MultiPoint',
                'MultiLineString',
                'MultiPolygon'
              ][g.type.index],
              'coordinates': geoCoords(g.coordinates)
            };
  Map<String, Object?> fields(Map map) => {
        for (final k in _names(map))
          (k.startsWith(r'$') ? r'$' + k : k): toJson(map[k])
      };
  switch (v) {
    case null || bool() || String():
      return v;
    case int() when _wireInt(v):
      return v;
    case BigInt():
      return _nativeInteger(v);
    case FleeceInt():
      return typed(v.kind.wireName, _nativeInteger(v.value));
    case double():
      return v.isFinite ? finite(v) : typed('float', floating(v));
    case FleeceFloat64():
      return v.value.isFinite
          ? finite(v.value)
          : typed('float', floating(v.value));
    case FleeceFloat32():
      return typed('f32', floating(v.value));
    case FleeceFloat16():
      return typed('f16', floating(v.value));
    case FleeceNone():
      return typed('none', null);
    case FleeceDecimal() || FleeceBigDecimal() || FleeceUuid():
      return typed((v as FleeceValue).kind.wireName, v.toString());
    case Uint8List():
      return typed('bytes', base64.encode(v));
    case List():
      return v.map(toJson).toList();
    case Map():
      return fields(v);
    case FleeceSet():
      return typed('set', v.members.map(toJson).toList());
    case FleeceRange():
      Map<String, Object?> bound(FleeceBound b) =>
          {b.flag == 1 ? 'included' : 'excluded': toJson(b.value)};
      return typed('range', {
        if (v.start.flag != 0) 'start': bound(v.start),
        if (v.end.flag != 0) 'end': bound(v.end)
      });
    case FleeceRecordId():
      return typed('record', {'table': v.table, 'key': toJson(v.key)});
    case FleeceText():
      return typed('text', [
        for (final (s, attrs) in v.runs)
          {'insert': s, if (attrs != null) 'attributes': fields(attrs)}
      ]);
    case FleeceSeconds():
      if (v.kind == ExtKind.duration)
        return typed('duration',
            {'secs': _nativeInteger(v.seconds), 'nanos': v.nanoseconds});
      final day = BigInt.from(86400), second = v.seconds % day;
      final date = _formatDate(((v.seconds - second) ~/ day).toInt());
      return typed(
          v.kind.wireName,
          date +
              'T' +
              _formatClock(second.toInt() * 1000000000 + v.nanoseconds) +
              (v.kind == ExtKind.datetime ? 'Z' : ''));
    case FleeceDate():
      return typed('date', _formatDate(v.days));
    case FleeceTime():
      return typed('time', _formatClock(v.nanoseconds));
    case FleeceInterval():
      return typed('interval', {
        'months': v.months,
        'days': v.days,
        'micros': _nativeInteger(v.microseconds)
      });
    case FleeceTable():
      return typed('table', v.name);
    case FleeceRegex():
      return typed('regex', v.pattern);
    case FleeceFile():
      return typed('file', {'bucket': v.bucket, 'key': v.key});
    case FleeceGeometry():
      return typed('geometry', geometry(v));
    case FleeceVector():
      final data = ByteData.sublistView(v.bytes);
      final items = switch (v.element) {
        VectorElement.bit =>
          List.generate(v.length, (i) => v[i] > 0 ? '1' : '0').join(),
        VectorElement.i8 => [
            for (var i = 0; i < v.length; i++) data.getInt8(i)
          ],
        VectorElement.f64 => [
            for (var i = 0; i < v.length; i++)
              floating(data.getFloat64(i * 8, _le))
          ],
        _ => [for (var i = 0; i < v.length; i++) floating(v[i])],
      };
      return typed('vector', {v.element.wireName: items});
    default:
      throw ArgumentError.value(v, 'value');
  }
}

Object _jsonFloat(double d) =>
    identical(1, 1.0) && d is int ? FleeceFloat64(d) : d;
BigInt _jsonInteger(Object? v, String name,
    {int bits = 64, bool signed = true}) {
  if (v is! int && v is! BigInt) _badJson(name);
  final n = _integer(v!);
  if (signed ? n.bitLength >= bits : n.isNegative || n.bitLength > bits)
    _badJson(name);
  return n;
}

double _jsonNumber(Object? v, String name) {
  if (v is FleeceFloat64) return v.value;
  if (v is num) return v.toDouble();
  if (v is BigInt) return v.toDouble();
  return _badJson(name);
}

double _readJsonFloat(Object? v, String name) => switch (v) {
      'NaN' => double.nan,
      'Infinity' => double.infinity,
      '-Infinity' => double.negativeInfinity,
      _ => _jsonNumber(v, name)
    };
double _exactF32(Object? v, String name) {
  final d = _readJsonFloat(v, name);
  return _asF32(d) == d || d.isNaN ? d : _badJson(name);
}

FleeceFloat16 _exactF16(Object? v, String name) =>
    FleeceFloat16.fromF64(_readJsonFloat(v, name)) ?? _badJson(name);
List _jsonList(Object? v, String name) =>
    v is List && v is! Uint8List ? v : _badJson(name);
Map _jsonMap(Object? v, String name) => v is Map ? v : _badJson(name);
String _jsonString(Object? v, String name) => v is String ? v : _badJson(name);

Object? fromJson(Object? json) {
  if (_wireInt(json) || json is BigInt) {
    final n = _integer(json!);
    if (n.bitLength < 64) return _nativeInteger(n);
    if (!n.isNegative && n.bitLength == 64) return FleeceInt.u64(n);
    return _jsonFloat(n.toDouble());
  }
  if (json == null ||
      json is bool ||
      json is String ||
      json is double ||
      json is FleeceFloat64) return json;
  if (json is List) return json.map(fromJson).toList();
  final m = _jsonMap(json, 'object');
  final keys = _names(m);
  if (keys.length == 1 &&
      keys.first.startsWith(r'$') &&
      !keys.first.startsWith(r'$$')) {
    final name = keys.first.substring(1);
    try {
      return _fromTag(name, m[keys.first]);
    } on JsonError {
      rethrow;
    } on ArgumentError {
      return _badJson(name);
    } on FormatException {
      return _badJson(name);
    }
  }
  return {
    for (final k in keys)
      (k.startsWith(r'$$') ? k.substring(1) : k): fromJson(m[k])
  };
}

Object? _fromTag(String name, Object? p) {
  Map map() => _jsonMap(p, name);
  String str() => _jsonString(p, name);
  int integer(int bits, bool signed) =>
      _jsonInteger(p, name, bits: bits, signed: signed).toInt();
  FleeceBound bound(String key) {
    final fields = map();
    if (!fields.containsKey(key)) return const FleeceBound.unbounded();
    final b = _jsonMap(fields[key], name),
        inc = b.containsKey('included'),
        exc = b.containsKey('excluded');
    if (inc == exc) _badJson(name);
    return inc
        ? FleeceBound.included(fromJson(b['included']))
        : FleeceBound.excluded(fromJson(b['excluded']));
  }

  switch (name) {
    case 'none':
      return p == null ? const FleeceNone() : _badJson(name);
    case 'i8':
      return FleeceInt.i8(integer(8, true));
    case 'u8':
      return FleeceInt.u8(integer(8, false));
    case 'i16':
      return FleeceInt.i16(integer(16, true));
    case 'u16':
      return FleeceInt.u16(integer(16, false));
    case 'i32':
      return FleeceInt.i32(integer(32, true));
    case 'u32':
      return FleeceInt.u32(integer(32, false));
    case 'u64':
      return FleeceInt.u64(_jsonInteger(p, name, signed: false));
    case 'float':
      return _jsonFloat(_readJsonFloat(p, name));
    case 'f32':
      return FleeceFloat32(_exactF32(p, name));
    case 'f16':
      return _exactF16(p, name);
    case 'decimal':
      return FleeceDecimal.parse(str());
    case 'bigdecimal':
      return FleeceBigDecimal.parse(str());
    case 'bytes':
      final s = str();
      if (s.length % 4 != 0 || !RegExp(r'^[A-Za-z0-9+/]*={0,2}$').hasMatch(s))
        _badJson(name);
      // The reference ignores unused low bits of the final sextet.
      const alphabet =
          'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
      final out = BytesBuilder();
      for (var i = 0; i < s.length; i += 4) {
        final a = alphabet.indexOf(s[i]), b = alphabet.indexOf(s[i + 1]);
        if (a < 0 || b < 0) _badJson(name);
        out.addByte((a << 2) | (b >> 4));
        if (s[i + 2] != '=') {
          final c = alphabet.indexOf(s[i + 2]);
          out.addByte((b << 4) | (c >> 2));
          if (s[i + 3] != '=')
            out.addByte((c << 6) | alphabet.indexOf(s[i + 3]));
        }
      }
      return out.takeBytes();
    case 'duration':
      final m = map();
      return FleeceSeconds.duration(
          _jsonInteger(m['secs'], name, signed: false),
          _jsonInteger(m['nanos'], name, bits: 32, signed: false).toInt());
    case 'date':
      return FleeceDate(_parseDate(str()));
    case 'time':
      return FleeceTime(_parseClock(str()));
    case 'datetime':
    case 'timestamp':
      var s = str();
      if (name == 'datetime') {
        if (!s.endsWith('Z')) _badJson(name);
        s = s.substring(0, s.length - 1);
      }
      final parts = s.split('T');
      if (parts.length != 2) _badJson(name);
      final day = _parseDate(parts.first), clock = _parseClock(parts.last);
      if (clock >= FleeceTime.maxNanos) _badJson(name);
      final base =
              _bounded(BigInt.from(day) * BigInt.from(86400), 64, signed: true),
          secs = base + BigInt.from(clock ~/ 1000000000),
          nanos = clock % 1000000000;
      return name == 'datetime'
          ? FleeceSeconds.datetime(secs, nanos)
          : FleeceSeconds.timestamp(secs, nanos);
    case 'interval':
      final m = map();
      return FleeceInterval(
          _jsonInteger(m['months'], name, bits: 32).toInt(),
          _jsonInteger(m['days'], name, bits: 32).toInt(),
          _jsonInteger(m['micros'], name));
    case 'uuid':
      return FleeceUuid.parse(str());
    case 'table':
      return FleeceTable(str());
    case 'regex':
      return FleeceRegex(str());
    case 'file':
      final m = map();
      return FleeceFile(
          _jsonString(m['bucket'], name), _jsonString(m['key'], name));
    case 'set':
      return FleeceSet(_jsonList(p, name).map(fromJson));
    case 'range':
      return FleeceRange(bound('start'), bound('end'));
    case 'record':
      final m = map(), k = fromJson(m['key']);
      return FleeceRecordId(_jsonString(m['table'], name), k ?? _badJson(name));
    case 'text':
      return FleeceText.fromRuns(_jsonList(p, name).map((run) {
        final r = _jsonMap(run, name), s = _jsonString(r['insert'], name);
        if (r.length == 1) return (s, null);
        if (r.length != 2 || !r.containsKey('attributes')) _badJson(name);
        final a = fromJson(r['attributes']);
        return (s, a is TextAttributes ? a : _badJson(name));
      }));
    case 'geometry':
      return _jsonGeometry(p);
    case 'vector':
      final m = map();
      if (m.length != 1) _badJson(name);
      final k = m.keys.first, value = m[k];
      if (k == 'bits') {
        final s = _jsonString(value, name);
        if (!RegExp(r'^[01]*$').hasMatch(s)) _badJson(name);
        return FleeceVector.quantizedBits(
            [for (var i = 0; i < s.length; i++) s[i] == '1' ? 1.0 : 0.0]);
      }
      final items = _jsonList(value, name);
      return switch (k) {
        'f32' => FleeceVector.f32([for (final e in items) _exactF32(e, name)]),
        'f64' =>
          FleeceVector.f64([for (final e in items) _readJsonFloat(e, name)]),
        'f16' => FleeceVector.f16Bits(
            [for (final e in items) _exactF16(e, name).bits]),
        'i8' => FleeceVector.i8(
            [for (final e in items) _jsonInteger(e, name, bits: 8).toInt()]),
        _ => _badJson(name)
      };
    default:
      throw JsonError(
          JsonErrorCode.unknownType, 'Unknown Fleece JSON type ' + name);
  }
}

FleeceGeometry _jsonGeometry(Object? p) {
  const name = 'geometry';
  List array(Object? v) => _jsonList(v, name);
  FleecePoint point(Object? v) {
    final a = array(v);
    if (a.length != 2) _badJson(name);
    return (_jsonNumber(a[0], name), _jsonNumber(a[1], name));
  }

  FleeceLine line(Object? v) => array(v).map(point).toList();
  FleecePolygon rings(Object? v) => array(v).map(line).toList();
  final m = _jsonMap(p, name), c = m['coordinates'];
  switch (m['type']) {
    case 'Point':
      final (x, y) = point(c);
      return FleeceGeometry.point(x, y);
    case 'LineString':
      return FleeceGeometry.line(line(c));
    case 'MultiPoint':
      return FleeceGeometry.multiPoint(line(c));
    case 'Polygon':
      return FleeceGeometry.polygon(rings(c));
    case 'MultiLineString':
      return FleeceGeometry.multiLine(rings(c));
    case 'MultiPolygon':
      return FleeceGeometry.multiPolygon(array(c).map(rings).toList());
    case 'GeometryCollection':
      return FleeceGeometry.collection(
          array(m['geometries']).map(_jsonGeometry).toList());
    default:
      return _badJson(name);
  }
}

// Howard Hinnant's proleptic Gregorian civil_from_days / days_from_civil.
(int, int, int) _civil(int days) {
  final z = days + 719468, doe = z % 146097, era = (z - doe) ~/ 146097;
  final y = (doe - doe ~/ 1460 + doe ~/ 36524 - doe ~/ 146096) ~/ 365;
  final doy = doe - (365 * y + y ~/ 4 - y ~/ 100), mp = (5 * doy + 2) ~/ 153;
  final m = mp + (mp < 10 ? 3 : -9);
  return (y + era * 400 + (m <= 2 ? 1 : 0), m, doy - (153 * mp + 2) ~/ 5 + 1);
}

String _pad(int n, int digits) => n.toString().padLeft(digits, '0');
String _formatDate(int days) {
  final (y, m, d) = _civil(days);
  return (y < 0
          ? '-'
          : y > 9999
              ? '+'
              : '') +
      _pad(y.abs(), 4) +
      '-' +
      _pad(m, 2) +
      '-' +
      _pad(d, 2);
}

int _parseDate(String s) {
  final m = RegExp(r'^([+-]?[0-9]{4,12})-([0-9]{2})-([0-9]{2})$').firstMatch(s);
  if (m == null) throw ParseError(s);
  final y = int.parse(m[1]!), month = int.parse(m[2]!), day = int.parse(m[3]!);
  final year = y - (month <= 2 ? 1 : 0),
      yoe = year % 400,
      era = (year - yoe) ~/ 400,
      mp = month + (month > 2 ? -3 : 9);
  final days = era * 146097 +
      yoe * 365 +
      yoe ~/ 4 -
      yoe ~/ 100 +
      (153 * mp + 2) ~/ 5 +
      day -
      1 -
      719468;
  if (_civil(days) != (y, month, day)) throw ParseError(s);
  return days;
}

String _formatClock(int nanos) {
  final s = nanos ~/ 1000000000, f = nanos % 1000000000;
  return _pad(s ~/ 3600, 2) +
      ':' +
      _pad(s ~/ 60 % 60, 2) +
      ':' +
      _pad(s % 60, 2) +
      (f == 0 ? '' : '.' + _pad(f, 9).replaceFirst(RegExp(r'0+$'), ''));
}

int _parseClock(String s) {
  final m = RegExp(r'^([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.([0-9]{1,9}))?$')
      .firstMatch(s);
  if (m == null) throw ParseError(s);
  final h = int.parse(m[1]!), min = int.parse(m[2]!), sec = int.parse(m[3]!);
  final n = (h * 3600 + min * 60 + sec) * 1000000000 +
      int.parse((m[4] ?? '').padRight(9, '0'));
  if (min > 59 || sec > 59 || n > FleeceTime.maxNanos) throw ParseError(s);
  return n;
}

/// Parses JSON numbers from their lexemes so an i64/u64 never passes through
/// a JavaScript number and an integral float keeps its wire type.
final class _JsonReader {
  _JsonReader(this.source);
  final String source;
  int at = 0;
  static final number =
      RegExp(r'-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?');
  Never fail() => throw FormatException('Invalid JSON', source, at);
  int get c => at < source.length ? source.codeUnitAt(at) : -1;
  void space() {
    while (c == 32 || c == 10 || c == 13 || c == 9) {
      at++;
    }
  }

  bool take(int code) {
    space();
    if (c != code) return false;
    at++;
    return true;
  }

  String string() {
    final start = at++;
    while (at < source.length) {
      final ch = source.codeUnitAt(at++);
      if (ch == 92) {
        at++;
        continue;
      }
      if (ch == 34) {
        final s = jsonDecode(source.substring(start, at)) as String;
        _utf8(s);
        return s;
      }
    }
    return fail();
  }

  Object? value(int depth) {
    space();
    if (c == 34) return string();
    if (c == 123 || c == 91) {
      if (depth >= 127) fail();
      final object = c == 123;
      at++;
      final map = <String, Object?>{}, list = <Object?>[];
      final close = object ? 125 : 93;
      if (!take(close)) {
        do {
          if (object) {
            space();
            if (c != 34) fail();
            final k = string();
            if (!take(58)) fail();
            map[k] = value(depth + 1);
          } else {
            list.add(value(depth + 1));
          }
          if (take(close)) break;
          if (!take(44)) fail();
        } while (true);
      }
      return object ? map : list;
    }
    for (final e
        in const {'true': true, 'false': false, 'null': null}.entries) {
      if (source.startsWith(e.key, at)) {
        at += e.key.length;
        return e.value;
      }
    }
    final m = number.matchAsPrefix(source, at);
    if (m == null) fail();
    final text = m[0]!;
    at = m.end;
    if (!text.contains(RegExp('[.eE]')) && text != '-0') {
      final n = BigInt.parse(text);
      if (n.bitLength < 64 || !n.isNegative && n.bitLength <= 64)
        return _nativeInteger(n);
    }
    final d = double.parse(text);
    if (!d.isFinite) fail();
    return _jsonFloat(d);
  }

  Object? parse() {
    final v = value(0);
    space();
    if (at != source.length) fail();
    return v;
  }
}

/// Parses the typed JSON spelling, preserving the entire i64/u64 range.
Object? parseFleeceJson(String text) {
  Object? json;
  try {
    json = _JsonReader(text).parse();
  } on FormatException catch (e) {
    throw JsonError(JsonErrorCode.syntax, e.message, e);
  } on ArgumentError catch (e) {
    throw JsonError(JsonErrorCode.syntax, e.toString(), e);
  }
  return fromJson(json);
}

Uint8List jsonToFleece(String text) {
  final v = parseFleeceJson(text);
  try {
    return encode(v);
  } on EncodeError catch (e) {
    throw JsonError(JsonErrorCode.encode, e.toString(), e);
  }
}

String _floatString(double d, {bool debug = false}) {
  if (d == 0) return d.isNegative ? '-0.0' : '0.0';
  final sci = d.toStringAsExponential().split('e'), exp = int.parse(sci.last);
  if (exp < (debug ? -4 : -5) || exp >= 16) {
    return sci.first + 'e' + (exp >= 0 && !debug ? '+' : '') + exp.toString();
  }
  final s = d.toString();
  if (!s.contains('e')) return s.contains('.') ? s : s + '.0';
  final sign = d.isNegative ? '-' : '',
      digits = sci.first.replaceAll(RegExp(r'[-.]'), '');
  if (exp < 0) return sign + '0.' + '0' * (-exp - 1) + digits;
  final cut = exp + 1;
  return cut >= digits.length
      ? sign + digits.padRight(cut, '0') + '.0'
      : sign + digits.substring(0, cut) + '.' + digits.substring(cut);
}

String _jsonText(Object? v) {
  if (v is BigInt) return v.toString();
  if (_wireInt(v)) return _integer(v!).toString();
  if (v is FleeceFloat64) return _floatString(v.value);
  if (v is double) return _floatString(v);
  if (v is List) return '[' + v.map(_jsonText).join(',') + ']';
  if (v is Map)
    return '{' +
        _names(v).map((k) => jsonEncode(k) + ':' + _jsonText(v[k])).join(',') +
        '}';
  return jsonEncode(v);
}

/// Writes the typed JSON spelling, including exact integers and tagged numbers.
String stringifyFleeceJson(Object? value) => _jsonText(toJson(value));

String fleeceToJson(Uint8List bytes,
    {SharedKeys? sharedKeys, Uint8List? base}) {
  try {
    return stringifyFleeceJson(
        decode(bytes, sharedKeys: sharedKeys, base: base));
  } on FormatException catch (e) {
    throw JsonError(JsonErrorCode.decode, e.message, e);
  }
}
