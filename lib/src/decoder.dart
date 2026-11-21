part of '../fleece.dart';

Object? _decodeDocument(Doc doc) {
  final root = doc._root(checked: true);
  try {
    if (!doc._isPointer(doc._end - 2) && root._size > 2) {
      _malformed('Value exceeds its inline slot', root.position);
    }
    return _OwnedReader(doc, strict: true).read(root.position, 0);
  } on DecodeError {
    // Match the validator's position, error precedence and accounting on
    // malformed input, including noncanonical slots accepted by Rust.
    doc.validate();
  }
  return root.read();
}

/// Materializes the logical subtree. Each expanded occurrence spends its own
/// budget, even if several wire slots point to the same value.
final class _OwnedReader extends _ReadRoom {
  _OwnedReader(this.doc, {this.strict = false}) : super(doc);
  bool strict;
  late final _inheritedValidator = _Validator(doc);
  final Doc doc;
  late final _keyNames = <int, String>{};
  late final _parents = <int>[];
  bool _overlapping = false;

  Object? read(int pos, int depth) {
    takeValue();
    return _read(pos, depth);
  }

  Object? _read(int pos, int depth) {
    final (buffer, offset) = doc._locate(pos);
    final tag = buffer[offset];
    if (buffer.length - offset >= 2) {
      if (tag < 16) return (tag * 256 + buffer[offset + 1]).toSigned(12);
      switch (tag) {
        case 0x30:
          return null;
        case 0x34:
          return false;
        case 0x38:
          return true;
        case 0x31 when buffer[offset + 1] == 0:
          return const FleeceNone();
        case 0x40:
          return '';
        case 0x41 when buffer[offset + 1] < 128:
          takeBytes(1);
          return String.fromCharCode(buffer[offset + 1]);
      }
    }
    final v = doc.valueAt(pos);
    return _value(v, doc._headerAt(pos, buffer, offset), depth);
  }

  int _slot(int position, int width) {
    if (!strict) return doc._slotPosition(position, width);
    final (buffer, offset) = doc._locate(position);
    final tag = buffer[offset];
    if (tag >= 128) {
      if (offset + width > buffer.length) {
        _malformed('Truncated pointer', position, DecodeErrorCode.badPointer);
      }
      return doc._pointerAt(position, width, buffer, offset, true, false);
    }
    // The encoder inlines only two-byte values. Other legal slots can hold
    // a four-byte value and need an explicit size check.
    if (tag < 16 ||
        tag == 0x30 ||
        tag == 0x34 ||
        tag == 0x38 ||
        tag == 0x40 ||
        tag == 0x41 ||
        tag == 0x50 ||
        tag == 0x51) return position;
    if (doc.valueAt(position)._size > width) {
      _malformed('Value exceeds its inline slot', position);
    }
    return position;
  }

  Object? _value(ValueRef v, _Header h, int depth) {
    switch (h.type) {
      case ValueType.nullValue:
        return null;
      case ValueType.boolean:
        return h.arg != 0;
      case ValueType.integer:
        final n = v._number(h);
        return n is BigInt && n.bitLength >= 64
            ? FleeceInt._decoded(ExtKind.u64, n)
            : n;
      case ValueType.float32:
        final (buf, off) = doc._locate(v.position);
        return FleeceFloat32.fromBits(
            ByteData.sublistView(buf).getUint32(off + 2, _le));
      case ValueType.float64:
        return v._readDouble(h);
      case ValueType.string:
        takeBytes(h.arg);
        return _checkedString(v, h);
      case ValueType.data:
        takeBytes(h.arg);
        return Uint8List.fromList(v._contents(h));
      case ValueType.array:
        _collectionDepth(v, depth, h.arg);
        takeValues(h.arg);
        final items = List<Object?>.filled(h.arg, null, growable: true);
        var slot = v.position + h.start;
        for (var i = 0; i < items.length; i++, slot += h.width) {
          items[i] = _read(_slot(slot, h.width), depth + 1);
        }
        return items;
      case ValueType.dict:
        _collectionDepth(v, depth, h.arg);
        return _dictionary(v, h, depth + 1);
      case ValueType.undefined:
        _malformed('Undefined outside an inherited dictionary', v.position,
            DecodeErrorCode.undefined);
      case ValueType.extended:
        if (h.arg == 0) return const FleeceNone();
        if (h.arg >= ExtKind.values.length) {
          _malformed('Unknown Fleece extension', v.position,
              DecodeErrorCode.unknownExt, h.arg);
        }
        final p = doc.valueAt(v.position + 2);
        final kind = ExtKind.values[h.arg];
        final payload = p._available;
        if (payload == null || payload.type == ValueType.extended) {
          _badPayload(kind, v.position);
        }
        return _extension(kind, p, payload, depth);
    }
  }

  void _collectionDepth(ValueRef v, int depth, int count) {
    final pos = v.position;
    if (depth >= maxDepth)
      _malformed('Too deeply nested', pos, DecodeErrorCode.tooDeep);
    if (count == 0) return;
    final parents = _parents;
    // Canonical child collections precede their parent. A trusted document
    // can also refer into a collection's own slots. Only such layouts need
    // an ancestor search to distinguish a cycle from an ordinary shared DAG.
    if (depth > 0 && pos >= parents[depth - 1]) _overlapping = true;
    if (_overlapping) {
      for (var i = 0; i < depth; i++) {
        if (parents[i] == pos)
          _malformed('Cyclic Fleece collection', pos, DecodeErrorCode.tooDeep);
      }
    }
    if (parents.length == depth) {
      parents.add(pos);
    } else {
      parents[depth] = pos;
    }
  }

  Map<String, Object?> _dictionary(ValueRef v, _Header h, int depth) {
    final first = v.position + h.start;
    final result = <String, Object?>{};
    if (h.arg == 0) return result;
    final dict = DictRef._(doc, first, h.width, h.arg);
    if (dict._inherits) {
      if (!strict) return _visible(dict, depth);
      // Shadowed values and parent links must pass physical validation too.
      // Charge whichever of the physical and visible expansions is larger.
      final cost = _inheritedValidator.value(v, depth - 1, null);
      final remainingValues =
          values - (cost.values - 1); // This dictionary was charged on entry.
      final remainingBytes = bytes - cost.bytes;
      if (remainingValues < 0 || remainingBytes < 0) {
        _malformed(
            'Fleece expansion limit exceeded',
            v.position,
            remainingValues < 0
                ? DecodeErrorCode.tooManyValues
                : DecodeErrorCode.tooManyBytes);
      }
      strict = false;
      try {
        return _visible(dict, depth);
      } finally {
        strict = true;
        values = math.min(values, remainingValues);
        bytes = math.min(bytes, remainingBytes);
      }
    }
    Object? previous;
    Set<int>? numbered;
    if (strict) takeValues(h.arg); // Physical dictionary keys.
    for (var i = 0, slot = first; i < h.arg; i++, slot += 2 * h.width) {
      final String key;
      final int size, child;
      try {
        final pos = _slot(slot, h.width);
        final ref = doc.valueAt(pos);
        final header = ref._header;
        final Object order;
        if (header.type == ValueType.string) {
          size = header.arg;
          key = ref._keyName(header, slot, _keyNames);
          order = key;
          if (strict &&
              numbered != null &&
              numbered.contains(doc.sharedKeys?.number(key))) {
            _malformed('Duplicate dictionary key', v.position,
                DecodeErrorCode.unsortedKeys);
          }
        } else {
          final n =
              header.type == ValueType.integer ? ref._number(header) : null;
          final name = n is int ? doc.sharedKeys?.key(n) : null;
          if (name == null) {
            if (strict)
              _malformed(
                  'Invalid dictionary key', v.position, DecodeErrorCode.badKey);
            continue;
          }
          order = n as int;
          if (strict) (numbered ??= {}).add(n);
          key = name;
          size = key.length;
        }
        if (strict) {
          if (previous != null && _compareKeys(previous, order) >= 0) {
            _malformed('Unsorted dictionary keys', v.position,
                DecodeErrorCode.unsortedKeys);
          }
          previous = order;
        }
        child = _slot(slot + h.width, h.width);
      } on FormatException {
        if (strict) rethrow;
        // As in DictRef.entries, a trusted dictionary skips unreadable slots.
        continue;
      }
      takeBytes(size);
      result[key] = read(child, depth);
    }
    return result;
  }

  Map<String, Object?> _visible(DictRef dict, int depth) {
    final result = <String, Object?>{};
    for (final (key, position, size) in dict._visibleSlots(_keyNames)) {
      takeBytes(size);
      result[key] = read(position, depth);
    }
    return result;
  }

  FleeceValue _extension(ExtKind kind, ValueRef p, _Header h, int depth) {
    final pos = p.position - 2;
    switch (h.type) {
      case ValueType.integer:
        takeValue();
        final n = p._number(h);
        final bits = switch (kind) {
          ExtKind.i8 || ExtKind.u8 => 8,
          ExtKind.i16 || ExtKind.u16 || ExtKind.f16 => 16,
          ExtKind.i32 || ExtKind.u32 || ExtKind.date => 32,
          ExtKind.u64 => 64,
          ExtKind.time => 47,
          _ => 0,
        };
        final signed = kind == ExtKind.i8 ||
            kind == ExtKind.i16 ||
            kind == ExtKind.i32 ||
            kind == ExtKind.date;
        final fits = n is int
            ? (signed ? n.bitLength < bits : n >= 0 && n.bitLength <= bits)
            : (!signed && !(n as BigInt).isNegative && n.bitLength <= bits);
        if (bits == 0 || !fits) _badPayload(kind, pos);
        if (kind == ExtKind.time) {
          if (n is! int || n > FleeceTime.maxNanos) _badPayload(kind, pos);
          return FleeceTime(n);
        }
        if (kind == ExtKind.date) return FleeceDate(n as int);
        if (kind == ExtKind.f16) return FleeceFloat16.fromBits(n as int);
        return FleeceInt._decoded(
            kind, n is int ? BigInt.from(n) : n as BigInt);
      case ValueType.string:
        takeValue();
        takeBytes(h.arg);
        if (kind == ExtKind.table) return FleeceTable(_checkedString(p, h));
        if (kind == ExtKind.regex) return FleeceRegex(_checkedString(p, h));
      case ValueType.data:
        takeValue();
        takeBytes(h.arg);
        final b = p._contents(h);
        switch (kind) {
          case ExtKind.decimal:
            if (b.length == 16 &&
                b[0] == 0 &&
                b[1] == 0 &&
                b[2] <= 28 &&
                b[3] & 127 == 0) {
              return FleeceDecimal(
                  _fromLittle(Uint8List.sublistView(b, 4)), b[2],
                  negative: b[3] != 0);
            }
          case ExtKind.uuid:
            if (b.length == 16) return FleeceUuid(b);
          case ExtKind.interval:
            if (b.length == 16) {
              final data = ByteData.sublistView(b);
              return FleeceInterval(
                  data.getInt32(0, _le),
                  data.getInt32(4, _le),
                  _fromLittle(Uint8List.sublistView(b, 8), signed: true));
            }
          case ExtKind.duration || ExtKind.datetime || ExtKind.timestamp:
            if (b.length == 12) {
              final nanos = ByteData.sublistView(b).getUint32(8, _le);
              if (nanos >= 1000000000) _badPayload(kind, pos);
              final secs = _fromLittle(Uint8List.sublistView(b, 0, 8),
                  signed: kind != ExtKind.duration);
              return switch (kind) {
                ExtKind.duration => FleeceDuration(secs, nanos),
                ExtKind.datetime => FleeceDatetime(secs, nanos),
                _ => FleeceTimestamp(secs, nanos)
              };
            }
          case ExtKind.vector:
            if (FleeceVector._fits(b))
              return FleeceVector._fromBytes(b, owned: true);
          default:
            break;
        }
      case ValueType.array:
        return _extensionArray(kind, p, h, depth);
      default:
        break;
    }
    _badPayload(kind, pos);
  }

  FleeceValue _extensionArray(ExtKind kind, ValueRef p, _Header h, int depth) {
    // The Rust validator adds the marker to the cost returned to a parent
    // after checking this collection's budget. A root has no such parent.
    if (depth != 0) takeValue();
    if (kind == ExtKind.set) {
      return FleeceSet._owned(_value(p, h, depth) as List<Object?>);
    }
    _collectionDepth(p, depth, h.arg);
    takeValues(h.arg);
    if (kind == ExtKind.text) return _text(p, h, depth);
    final pos = p.position - 2;
    if (h.arg != (kind == ExtKind.range ? 3 : 2)) _badPayload(kind, pos);
    final start = p.position + h.start;
    final first = _read(_slot(start, h.width), depth + 1);
    final second = _slot(start + h.width, h.width);
    switch (kind) {
      case ExtKind.bigDecimal:
        if (first is int && first >= 0 && first <= FleeceBigDecimal.maxScale) {
          return FleeceBigDecimal.fromBytes(_data(second, kind, pos), first);
        }
      case ExtKind.recordId || ExtKind.file:
        if (first is String) {
          final key = _read(second, depth + 1);
          if (kind == ExtKind.file && key is String)
            return FleeceFile(first, key);
          if (kind == ExtKind.recordId) {
            final id = RecordIdKey.tryFrom(key);
            if (id != null) return FleeceRecordId(first, id);
          }
        }
      case ExtKind.range:
        if (first is int && first >= 0 && first < 16) {
          FleeceBound bound(int flag, Object? value) => switch (flag) {
                0 when value == null => const FleeceBound.unbounded(),
                1 => FleeceBound.included(value),
                2 => FleeceBound.excluded(value),
                _ => _badPayload(kind, pos)
              };
          return FleeceRange(
              bound(first & 3, _read(second, depth + 1)),
              bound(first >> 2,
                  _read(_slot(start + 2 * h.width, h.width), depth + 1)));
        }
      case ExtKind.geometry:
        if (first is! int) _badPayload(kind, pos);
        if (first == GeometryType.point.index) {
          final bytes = _data(second, kind, pos);
          if (bytes.length != 16) _badPayload(kind, pos);
          final d = ByteData.sublistView(bytes);
          return FleeceGeometry.point(
              d.getFloat64(0, _le), d.getFloat64(8, _le));
        }
        return _geometry(first, _read(second, depth + 1), pos);
      default:
        break;
    }
    _badPayload(kind, pos);
  }

  Uint8List _data(int position, ExtKind kind, int marker) {
    final v = doc.valueAt(position), h = v._header;
    if (h.type != ValueType.data) _badPayload(kind, marker);
    takeBytes(h.arg);
    return v._contents(h);
  }

  FleeceText _text(ValueRef p, _Header h, int depth) {
    final pos = p.position - 2;
    Never bad() => _badPayload(ExtKind.text, pos);
    if (h.arg == 0 || h.arg == 2) bad();
    final first = p.position + h.start;
    ValueRef field(int i) => doc.valueAt(_slot(first + i * h.width, h.width));
    final string = field(0), sh = string._header;
    if (sh.type != ValueType.string) bad();
    takeBytes(sh.arg);
    final text = _checkedString(string, sh);
    if (h.arg == 1) return FleeceText.plain(text);
    final marks = field(1), mh = marks._header;
    if (mh.type != ValueType.data || mh.arg == 0) bad();
    takeBytes(mh.arg);
    final attributes = <TextAttributes>[];
    for (var i = 2; i < h.arg; i++) {
      final item = field(i);
      final header = item._header;
      if (header.type != ValueType.dict || header.arg == 0) bad();
      final map = _value(item, header, depth + 1) as TextAttributes;
      if (map.isEmpty &&
          DictRef._(doc, item.position + header.start, header.width, header.arg)
              ._inherits) bad();
      attributes.add(map);
    }
    final builder = _TextBuilder();
    final numbers = <int, int>{};
    try {
      for (final mark in _spans(
          string._contents(sh), marks._contents(mh), attributes.length)) {
        final set = numbers[mark.set] ??= builder.intern(attributes[mark.set]);
        builder.mark(mark.start, mark.end, set);
      }
    } on FormatException {
      bad();
    }
    return FleeceText._(text, builder.sets, builder.spans);
  }

  FleeceGeometry _geometry(int type, Object? shape, int pos) {
    Never bad() => _badPayload(ExtKind.geometry, pos);
    FleeceLine points(Object? v) =>
        v is Uint8List && v.length % 16 == 0 ? _ownedPoints(v) : bad();
    List<Object?> list(Object? v) =>
        v is List<Object?> && v is! Uint8List ? v : bad();
    FleecePolygon rings(Object? v) => [for (final r in list(v)) points(r)];
    FleecePolygon polygon(Object? v) {
      final r = rings(v);
      return r.isEmpty ? bad() : r;
    }

    switch (type) {
      case 1:
        return FleeceGeometry.line(points(shape));
      case 2:
        return FleeceGeometry.polygon(polygon(shape));
      case 3:
        return FleeceGeometry.multiPoint(points(shape));
      case 4:
        return FleeceGeometry.multiLine(rings(shape));
      case 5:
        return FleeceGeometry.multiPolygon(
            [for (final p in list(shape)) polygon(p)]);
      case 6:
        return FleeceGeometry.collection(
            [for (final g in list(shape)) g is FleeceGeometry ? g : bad()]);
      default:
        bad();
    }
  }
}

Never _badPayload(ExtKind kind, int pos) => _malformed(
    'Invalid $kind payload', pos, DecodeErrorCode.badPayload, kind.index);
