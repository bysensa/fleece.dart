part of '../fleece.dart';

typedef _Cost = ({int values, int bytes, int height, int inherited});

/// The expansion budget shared by all reads or copies in a single operation.
final class _ReadRoom {
  _ReadRoom(Doc doc) : values = math.min(1 << 26, doc._end ~/ 2) {
    bytes = doc._end + SharedKeys.maxKeyLength * values;
  }
  int values;
  late int bytes;
  void takeValue() {
    if (--values < 0) _tooMany();
  }

  // Reserve array elements before allocating their output slots. Nested
  // arrays share the remainder even while an outer array is only partly full.
  void takeValues(int count) {
    values -= count;
    if (values < 0) _tooMany();
  }

  Never _tooMany() => throw const DecodeError(
      DecodeErrorCode.tooManyValues, 'The document expands to too many values');

  void takeBytes(int count) {
    bytes -= count;
    if (bytes < 0) {
      throw const DecodeError(DecodeErrorCode.tooManyBytes,
          'The document expands to too many bytes of strings and data');
    }
  }
}

final class _Validator {
  _Validator(this.doc) : maxValues = math.min(1 << 26, doc._end ~/ 2);
  final Doc doc;
  final int maxValues;
  int get maxBytes => doc._end + SharedKeys.maxKeyLength * maxValues;
  final _collections = <int, _Cost>{};
  final _strings = <int>{};
  final _visiting = <int>{};

  _Cost value(ValueRef v, int depth, int? limit) {
    final pos = v.position;
    if (pos.isOdd) _malformed('Misaligned Fleece value', pos);
    var at = v;
    var h = v._header;
    ExtKind? kind;
    if (h.type == ValueType.extended && h.arg != 0) {
      if (h.arg >= ExtKind.values.length)
        _malformed(
            'Unknown Fleece extension', pos, DecodeErrorCode.unknownExt, h.arg);
      kind = ExtKind.values[h.arg];
      at = doc.valueAt(pos + 2);
      try {
        h = at._header;
      } on FormatException {
        _malformed("Missing extension payload", pos, DecodeErrorCode.badPayload,
            kind.index);
      }
      if (h.type == ValueType.extended)
        _malformed('Nested extension payload', pos, DecodeErrorCode.badPayload,
            kind.index);
    }
    final extra = kind == null ? 0 : 1;
    if (limit != null && h.size + 2 * extra > limit) {
      _malformed('Value exceeds its inline slot', pos);
    }
    _Cost cost;
    switch (h.type) {
      case ValueType.array || ValueType.dict:
        final cached = _collections[pos];
        if (cached != null) {
          if (depth + cached.height > maxDepth)
            _malformed('Too deeply nested', pos, DecodeErrorCode.tooDeep);
          return cached;
        }
        if (depth >= maxDepth || !_visiting.add(pos))
          _malformed('Too deeply nested', pos, DecodeErrorCode.tooDeep);
        cost = _collection(at, h, depth, extra);
        _visiting.remove(pos);
        _collections[pos] = cost;
      case ValueType.undefined:
        _malformed('Undefined outside an inherited dictionary', pos,
            DecodeErrorCode.undefined);
      case ValueType.string || ValueType.data:
        if (h.type == ValueType.string && _strings.add(at.position))
          _checkedString(at, h);
        cost = (values: 1 + extra, bytes: h.arg, height: 0, inherited: 0);
      default:
        cost = (values: 1 + extra, bytes: 0, height: 0, inherited: 0);
    }
    bool fits(ExtKind k) {
      try {
        return _fits(k, at);
      } on FormatException {
        return false;
      }
    }

    if (kind != null && !fits(kind))
      _malformed(
          'Invalid $kind payload', pos, DecodeErrorCode.badPayload, kind.index);
    return cost;
  }

  _Cost _collection(ValueRef v, _Header h, int depth, int extra) {
    final first = v.position + h.start;
    final dict = h.type == ValueType.dict;
    final slots = h.arg * (dict ? 2 : 1);
    var values = 1, bytes = 0, height = 1, inherited = 0;
    var inherits = false;
    Object? previous;
    Set<int>? numbered;
    for (var i = 0; i < slots; i++) {
      final addr = first + i * h.width;
      final indirect = doc._isPointer(addr);
      final item = doc.valueAt(indirect
          ? doc._pointerTarget(addr, h.width,
              checkExternal: true, allowPointer: false)
          : addr);
      final limit = indirect ? null : h.width;
      if (dict && i.isEven) {
        final key = item._available;
        if (key == null) {
          if (indirect)
            _malformed(
                'Invalid dictionary key', v.position, DecodeErrorCode.badKey);
          _malformed('Malformed inline dictionary key', addr);
        }
        if (limit != null && key.size > limit)
          _malformed('Key exceeds its inline slot', addr);
        final Object current;
        if (key.type == ValueType.string) {
          final text = item._contents(key);
          current = text;
          // A short key can be shared by thousands of dictionaries. Decode it
          // again only when its name is needed to check a mixed-key collision.
          if (numbered != null || _strings.add(item.position)) {
            final name = _checkedString(item, key);
            if (numbered?.contains(doc.sharedKeys?.number(name)) == true) {
              _malformed(
                  'Duplicate key', v.position, DecodeErrorCode.unsortedKeys);
            }
          }
          bytes += text.length;
        } else {
          final integer = item.asI64;
          if (integer == null)
            _malformed(
                'Invalid dictionary key', v.position, DecodeErrorCode.badKey);
          if (integer < BigInt.from(_parentKey) ||
              integer > BigInt.from(SharedKeys.maxKeys - 1)) {
            _malformed(
                'Missing shared key $integer',
                v.position,
                DecodeErrorCode.missingSharedKey,
                null,
                _nativeInteger(integer));
          }
          final number = integer.toInt();
          current = number;
          if (i == 0 && number == _parentKey) {
            inherits = true;
          } else {
            final name = doc.sharedKeys?.key(number);
            if (name == null)
              _malformed('Missing shared key $number', v.position,
                  DecodeErrorCode.missingSharedKey, null, number);
            (numbered ??= <int>{}).add(number);
            bytes += name.length; // Every shared key is ASCII.
          }
        }
        if (previous != null && _compareKeys(previous, current) >= 0) {
          _malformed('Unsorted or duplicate dictionary key', v.position,
              DecodeErrorCode.unsortedKeys);
        }
        previous = current;
        values++;
        continue;
      }
      if (inherits && i > 1 && item.type == ValueType.undefined) {
        values++;
        continue;
      }
      final child = value(item, depth + 1, limit);
      if (inherits && i == 1) {
        if (item.type != ValueType.dict)
          _malformed(
              'Invalid dictionary parent', v.position, DecodeErrorCode.badKey);
        inherited = child.inherited + 1;
        if (inherited > maxInherited)
          _malformed(
              'Too many dictionary parents', addr, DecodeErrorCode.tooDeep);
      }
      values += child.values;
      bytes += child.bytes;
      height = math.max(height, 1 + child.height);
    }
    if (inherits) {
      final dictionary = v.asDict!;
      final parent = dictionary._parent;
      if (parent != null) {
        for (final own in dictionary._own) {
          final hidden = parent._lookup(own.key);
          if (hidden == null || hidden.type == ValueType.undefined) continue;
          final child = value(hidden, depth + 1, null);
          values -= 1 + child.values;
          bytes -= _utf8(own.key).length + child.bytes;
        }
      }
    }
    if (values > maxValues || bytes > maxBytes)
      _malformed(
          'Fleece expansion limit exceeded',
          v.position,
          values > maxValues
              ? DecodeErrorCode.tooManyValues
              : DecodeErrorCode.tooManyBytes);
    return (
      values: values + extra,
      bytes: bytes,
      height: height,
      inherited: inherited
    );
  }
}

bool _sized(ValueRef v, int bits, {bool signed = true}) {
  final h = v._available;
  if (h == null || h.type != ValueType.integer) return false;
  if (h.arg < 16) {
    final n = v._smallInt(h);
    return signed ? n.bitLength < bits : n >= 0 && n.bitLength <= bits;
  }
  final n = v._integerAt(h);
  return signed ? n.bitLength < bits : !n.isNegative && n.bitLength <= bits;
}

bool _rangeFits(ArrayRef? items) {
  if (items == null || items.length != 3) return false;
  final flags = items[0].asInt;
  if (flags == null || flags < 0 || flags >= 16) return false;
  bool bound(int f, ValueRef v) => f == 0 ? v.isNull : f == 1 || f == 2;
  return bound(flags & 3, items[1]) && bound(flags >> 2, items[2]);
}

bool _keyFits(ValueRef key) {
  switch (key.type) {
    case ValueType.integer:
      return _sized(key, 64);
    case ValueType.string || ValueType.array || ValueType.dict:
      return true;
    case ValueType.extended:
      if (key.extKind == ExtKind.uuid) return true;
      if (key.extKind != ExtKind.range) return false;
      final bounds = key.payload!.asArray!;
      final flags = bounds[0].asInt!;
      return (flags & 3 == 0 || _keyFits(bounds[1])) &&
          (flags >> 2 == 0 || _keyFits(bounds[2]));
    default:
      return false;
  }
}

bool _geometryFits(ArrayRef? pair) {
  if (pair == null || pair.length != 2) return false;
  final shape = pair[1];
  bool points(ValueRef v) =>
      v.type == ValueType.data && v._header.arg % 16 == 0;
  bool rings(ValueRef v) => v.asArray?.every(points) ?? false;
  bool polygon(ValueRef v) => v.asArray?.isNotEmpty == true && rings(v);
  return switch (pair[0].asInt) {
    0 => shape.asData?.length == 16,
    1 || 3 => points(shape),
    2 => polygon(shape),
    4 => rings(shape),
    5 => shape.asArray?.every(polygon) ?? false,
    6 => shape.asArray?.every((v) => v.extKind == ExtKind.geometry) ?? false,
    _ => false,
  };
}

bool _textFits(ArrayRef? items) {
  if (items == null ||
      items.length == 0 ||
      items.length == 2 ||
      items[0].type != ValueType.string) return false;
  if (items.length == 1) return true;
  final marks = items[1].asData;
  if (marks == null || marks.isEmpty) return false;
  final first = items[0];
  for (final _
      in _spans(first._contents(first._header), marks, items.length - 2)) {}
  return items.skip(2).every((v) => (v.asDict?.length ?? 0) > 0);
}

bool _fits(ExtKind kind, ValueRef p) {
  switch (kind) {
    case ExtKind.none:
      return false;
    case ExtKind.i8:
      return _sized(p, 8);
    case ExtKind.u8:
      return _sized(p, 8, signed: false);
    case ExtKind.i16:
      return _sized(p, 16);
    case ExtKind.u16 || ExtKind.f16:
      return _sized(p, 16, signed: false);
    case ExtKind.i32 || ExtKind.date:
      return _sized(p, 32);
    case ExtKind.u32:
      return _sized(p, 32, signed: false);
    case ExtKind.u64:
      return _sized(p, 64, signed: false);
    case ExtKind.decimal:
      final b = p.asData;
      return b != null &&
          b.length == 16 &&
          b[0] == 0 &&
          b[1] == 0 &&
          b[2] <= 28 &&
          b[3] & 127 == 0;
    case ExtKind.bigDecimal:
      final a = p.asArray;
      if (a == null || a.length != 2 || a[1].type != ValueType.data)
        return false;
      final scale = a[0].asInt;
      return scale != null && scale >= 0 && scale <= 294910;
    case ExtKind.duration || ExtKind.datetime || ExtKind.timestamp:
      final b = p.asData;
      return b?.length == 12 &&
          ByteData.sublistView(b!).getUint32(8, _le) < 1000000000;
    case ExtKind.uuid || ExtKind.interval:
      return p.asData?.length == 16;
    case ExtKind.time:
      final n = p.asInt;
      return n != null && n >= 0 && n <= 86400000000000;
    case ExtKind.table || ExtKind.regex:
      return p.type == ValueType.string;
    case ExtKind.recordId || ExtKind.file:
      final a = p.asArray;
      return a != null &&
          a.length == 2 &&
          a[0].type == ValueType.string &&
          (kind == ExtKind.recordId
              ? _keyFits(a[1])
              : a[1].type == ValueType.string);
    case ExtKind.range:
      return _rangeFits(p.asArray);
    case ExtKind.set:
      return p.type == ValueType.array;
    case ExtKind.geometry:
      return _geometryFits(p.asArray);
    case ExtKind.vector:
      final b = p.asData;
      return b != null && FleeceVector._fits(b);
    case ExtKind.text:
      return _textFits(p.asArray);
  }
}

String _checkedString(ValueRef v, _Header h) {
  try {
    return _string(v._contents(h));
  } on FormatException {
    _malformed('Invalid UTF-8', v.position, DecodeErrorCode.invalidUtf8);
  }
}
