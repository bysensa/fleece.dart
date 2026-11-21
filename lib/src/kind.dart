part of '../fleece.dart';

typedef GeometryKind = GeometryType;

/// Literal kinds include tuples and objects whose fields themselves have kinds.
final class KindLiteral {
  const KindLiteral._(this.value, [this._float = false]);
  const KindLiteral.string(String v) : this._(v);
  const KindLiteral.integer(Object v) : this._(v);
  const KindLiteral.float(double v) : this._(v, true);
  const KindLiteral.decimal(FleeceDecimal v) : this._(v);
  const KindLiteral.duration(FleeceSeconds v) : this._(v);
  const KindLiteral.array(List<Kind> v) : this._(v);
  const KindLiteral.object(Map<String, Kind> v) : this._(v);
  const KindLiteral.boolean(bool v) : this._(v);
  final bool _float;
  final Object value;
  @override
  bool operator ==(Object other) =>
      other is KindLiteral &&
      _float == other._float &&
      _equal(value, other.value);
  @override
  int get hashCode => Object.hash(_float, _valueHash(value));
}

final class Kind {
  const Kind._(this._name, [this._argument, this._max]) : _returns = null;
  final Kind? _returns;
  Kind? get returnKind => _returns;
  List<Kind>? get argumentKinds =>
      _name == 'function' ? _argument as List<Kind>? : null;
  final String _name;
  final Object? _argument;
  final Object? _max;
  String get name => _name;
  Object? get argument => _argument;
  BigInt? get maxItems => _max == null ? null : _integer(_max);
  static const any = Kind._('any'),
      none = Kind._('none'),
      nullValue = Kind._('null'),
      boolean = Kind._('bool'),
      bytes = Kind._('bytes'),
      datetime = Kind._('datetime'),
      date = Kind._('date'),
      time = Kind._('time'),
      timestamp = Kind._('timestamp'),
      interval = Kind._('interval'),
      decimal = Kind._('decimal'),
      duration = Kind._('duration'),
      f16 = Kind._('f16'),
      f32 = Kind._('f32'),
      float = Kind._('float'),
      i8 = Kind._('i8'),
      i16 = Kind._('i16'),
      i32 = Kind._('i32'),
      integer = Kind._('int'),
      u8 = Kind._('u8'),
      u16 = Kind._('u16'),
      u32 = Kind._('u32'),
      u64 = Kind._('u64'),
      number = Kind._('number'),
      object = Kind._('object'),
      string = Kind._('string'),
      uuid = Kind._('uuid'),
      regex = Kind._('regex'),
      range = Kind._('range'),
      bigDecimal = Kind._('bigdecimal');
  const Kind.table([List<String> names = const []]) : this._('table', names);
  const Kind.record([List<String> tables = const []])
      : this._('record', tables);
  const Kind.file([List<String> buckets = const []]) : this._('file', buckets);
  const Kind.geometry([List<GeometryKind> shapes = const []])
      : this._('geometry', shapes);
  const Kind.either(List<Kind> kinds) : this._('either', kinds);
  const Kind.set(Kind kind, [Object? max]) : this._('set', kind, max);
  const Kind.array(Kind kind, [Object? max]) : this._('array', kind, max);
  const Kind.function([List<Kind>? arguments, Kind? returns])
      : _name = 'function',
        _argument = arguments,
        _returns = returns,
        _max = null;
  const Kind.literal(KindLiteral literal) : this._('literal', literal);
  const Kind.enumeration(List<String> labels) : this._('enum', labels);
  const Kind.named(String name) : this._('named', name);

  @override
  bool operator ==(Object other) =>
      other is Kind &&
      _name == other._name &&
      _equal(_argument, other._argument) &&
      _equal(_max, other._max) &&
      _returns == other._returns;
  @override
  int get hashCode =>
      Object.hash(_name, _valueHash(_argument), _valueHash(_max), _returns);

  int get _size {
    final children = switch ((_name, _argument)) {
      ('array' || 'set', Kind child) => [child],
      ('either', List<Kind> kinds) => kinds,
      ('literal', KindLiteral(value: List<Kind> kinds)) => kinds,
      ('literal', KindLiteral(value: Map<String, Kind> fields)) =>
        fields.values,
      _ => const <Kind>[],
    };
    return children.fold(1, (n, k) => n + k._size);
  }

  bool conforms(ValueRef value) => conformsWith(value, const {});
  bool conformsWith(ValueRef value, Map<String, Kind> named) {
    final kinds = named.values.fold(_size, (n, k) => n + k._size);
    var steps = _ReadRoom(value.doc).values * kinds;
    Map<Kind, Map<int, bool>>? seen;
    bool check(Kind k, ValueRef v, int depth) {
      if (depth > maxDepth || seen == null && --steps < 0) return false;
      final item = v.item;
      final held = item.type == ItemType.array ||
          item.type == ItemType.dict ||
          item.type == ItemType.extended && item.value != null;
      final cache = held ? seen?.putIfAbsent(k, () => <int, bool>{}) : null;
      final previous = cache?[v.position];
      if (previous != null) return previous;
      bool matches() {
        final arg = k._argument, name = k._name;
        final ext = item.extensionId;
        final p =
            item.type == ItemType.extended ? item.value as ValueRef? : null;
        bool all(ArrayRef? a) =>
            a != null &&
            (k._max == null || BigInt.from(a.length) <= k.maxItems!) &&
            a.every((it) => check(arg as Kind, it, depth + 1));
        switch (name) {
          case 'any':
            return item.type != ItemType.undefined &&
                item.type != ItemType.invalid;
          case 'null':
            return item.type == ItemType.nullValue;
          case 'bool':
            return item.type == ItemType.boolean;
          case 'bytes':
            return item.type == ItemType.data;
          case 'object':
            return item.type == ItemType.dict;
          case 'string':
            return item.type == ItemType.string;
          case 'int':
            return item.type == ItemType.integer;
          case 'float':
            return item.type == ItemType.float64;
          case 'f32':
            return item.type == ItemType.float32;
          case 'u64':
            return item.type == ItemType.unsigned || ext == ExtKind.u64.index;
          case 'number':
            return [
                  ItemType.integer,
                  ItemType.unsigned,
                  ItemType.float32,
                  ItemType.float64
                ].contains(item.type) ||
                ext != null && ext >= 1 && ext <= ExtKind.bigDecimal.index;
          case 'table':
          case 'record':
          case 'file':
            if (ext == null ||
                ExtKind.values.elementAtOrNull(ext)?.wireName != name)
              return false;
            final names = arg as List<String>;
            return names.isEmpty ||
                names.contains(name == 'table'
                    ? p?.asString
                    : p?.asArray?.get(0)?.asString);
          case 'geometry':
            if (ext != ExtKind.geometry.index) return false;
            final shapes = arg as List<GeometryType>;
            return shapes.isEmpty ||
                shapes.any((s) => s.index == p?.asArray?.get(0)?.asInt);
          case 'function':
            return false;
          case 'array':
            return all(v.asArray);
          case 'set':
            return ext == ExtKind.set.index && all(p?.asArray);
          case 'named':
            final target = named[arg];
            return target != null && check(target, v, depth + 1);
          case 'either':
            return (arg as List<Kind>).any((kind) => check(kind, v, depth + 1));
          case 'enum':
            return item.type == ItemType.string &&
                (arg as List<String>).contains(item.value);
          case 'literal':
            final literal = (arg as KindLiteral);
            final x = literal.value;
            if (literal._float)
              return item.type == ItemType.float64 && item.value == x;
            if (x is List<Kind>) {
              final a = v.asArray;
              return a != null &&
                  a.length == x.length &&
                  Iterable.generate(x.length)
                      .every((i) => check(x[i], a[i], depth + 1));
            }
            if (x is Map<String, Kind>) {
              final d = v.asDict;
              return d != null &&
                  x.length == d.length &&
                  x.entries.every((e) {
                    final f = d[e.key];
                    return f != null && check(e.value, f, depth + 1);
                  });
            }
            if (x is FleeceSeconds && x.kind != ExtKind.duration) return false;
            if (x is FleeceValue)
              return ext == x.kind.index && _equal(p?.asData, x._payload);
            if (x is BigInt || x is int)
              return item.type == ItemType.integer && _integer(x) == item.value;
            return (item.type == ItemType.string ||
                    item.type == ItemType.boolean) &&
                item.value == x;
          default:
            return ext != null &&
                ExtKind.values.elementAtOrNull(ext)?.wireName == name;
        }
      }

      final fits = matches();
      if (cache != null) cache[v.position] = fits;
      return fits;
    }

    try {
      final fits = check(this, value, 0);
      if (steps >= 0) return fits;
      // Repeated pointers or named kinds exhausted the ordinary walk. Cache
      // each collection by kind identity and position for the second pass.
      seen = HashMap.identity();
      return check(this, value, 0);
    } on FormatException {
      return false;
    }
  }
}
