part of '../fleece.dart';

/// Writes the bytes to append to [base] for the new root. With [external],
/// read the returned buffer separately using the same base in [Doc].
Uint8List appendDelta(Uint8List base, Object? value,
        {bool external = false, SharedKeys? sharedKeys}) =>
    _deltaOperation(() {
      final doc = Doc(base, sharedKeys: sharedKeys);
      final encoder = Encoder(
          base: base,
          external: external,
          sharedKeys: sharedKeys,
          fixedSharedKeys: true);
      encoder.writeChanged(doc.root, value);
      return encoder.finish();
    });

/// Rewrites just the reachable values and materializes inherited entries.
Uint8List compact(Doc doc) => _deltaOperation(() {
      doc.validate();
      return (Encoder(sharedKeys: doc.sharedKeys, fixedSharedKeys: true)
            ..writeCopy(doc.root))
          .finish();
    });

enum _Change { same, replace, children }

final class _Plan {
  const _Plan(this.change, [this.children = const []]);
  final _Change change;
  final List<_Plan> children;
}

const _same = _Plan(_Change.same), _replace = _Plan(_Change.replace);

_Plan _plan(Object? old, Object? next, int depth) {
  if (depth > maxDepth) {
    throw _EncoderState(
        EncodeErrorCode.tooDeep, 'Fleece nesting exceeds $maxDepth');
  }
  final List<_Plan> children;
  final bool sameLength;
  if (old is Map && next is Map) {
    children = [
      for (final key in _names(next))
        old.containsKey(key) ? _plan(old[key], next[key], depth + 1) : _replace
    ];
    sameLength = old.length == next.length;
  } else if (old is List &&
      next is List &&
      old is! Uint8List &&
      next is! Uint8List) {
    children = [
      for (var i = 0; i < next.length; i++)
        i < old.length ? _plan(old[i], next[i], depth + 1) : _replace
    ];
    sameLength = old.length == next.length;
  } else {
    return _equal(old, next) ? _same : _replace;
  }
  return sameLength && children.every((p) => p == _same)
      ? _same
      : _Plan(_Change.children, children);
}

extension DeltaEncoder on Encoder {
  /// Writes [value], reusing unchanged parts of [old] from this encoder's base.
  void writeChanged(ValueRef old, Object? value) {
    Object? previous;
    try {
      previous = old.read();
    } on FormatException {
      writeValue(value);
      return;
    }
    _changed(old, previous, value, _plan(previous, value, 0));
  }

  void _changed(ValueRef at, Object? old, Object? value, _Plan plan) {
    switch (plan.change) {
      case _Change.same:
        writeRef(at);
      case _Change.replace:
        writeValue(value);
      case _Change.children:
        if (old is Map && value is Map) {
          final dict = at.asDict!;
          final keys = _names(value);
          final deleted =
              _names(old).where((key) => !value.containsKey(key)).toList();
          final changed = plan.children.where((p) => p != _same).length;
          final inherit = 2 * (changed + deleted.length + 1) < keys.length &&
              dict._chain.length - 1 < 4;
          _begin(true, inherit ? at.position : null);
          for (var i = 0; i < keys.length; i++) {
            final child = plan.children[i];
            if (inherit && child == _same) continue;
            final key = keys[i];
            _writeKey(key, dict._keyPosition(key));
            final ref = dict[key];
            if (ref == null) {
              writeValue(value[key]);
            } else {
              _changed(ref, old[key], value[key], child);
            }
          }
          if (inherit) {
            for (final key in deleted) {
              _writeKey(key, dict._keyPosition(key));
              _word(0x3c00);
            }
          }
          endDict();
        } else {
          final array = at.asArray!;
          final items = value as List;
          beginArray();
          for (var i = 0; i < items.length; i++) {
            final ref = array.get(i);
            if (ref == null) {
              writeValue(items[i]);
            } else {
              _changed(ref, (old as List)[i], items[i], plan.children[i]);
            }
          }
          endArray();
        }
    }
  }
}

/// A present delta can contain a literal null. [diff] returns null for no change.
final class FleeceDelta {
  const FleeceDelta(this.value);
  final Object? value;
}

bool _array(Object? value) => value is List && value is! Uint8List;
Object? _replacement(Object? v) => v is Map || _array(v) ? [v] : v;

FleeceDelta? diff(Object? old, Object? value) {
  final changes = <String, Object?>{};
  if (old is Map && value is Map) {
    for (final key in _names(value)) {
      if (!old.containsKey(key)) {
        changes[key] = _replacement(value[key]);
      } else {
        final d = diff(old[key], value[key]);
        if (d != null) changes[key] = d.value;
      }
    }
    for (final key in _names(old)) {
      if (!value.containsKey(key)) changes[key] = <Object?>[];
    }
  } else if (old is List && value is List && _array(old) && _array(value)) {
    final end = math.min(old.length, value.length);
    for (var i = 0; i < end; i++) {
      final d = diff(old[i], value[i]);
      if (d != null) changes[i.toString()] = d.value;
    }
    if (old.length != value.length) changes['$end-'] = value.sublist(end);
  } else {
    return _equal(old, value) ? null : FleeceDelta(_replacement(value));
  }
  return changes.isEmpty ? null : FleeceDelta(changes);
}

const _deleted = Object();
Never _mismatch() => throw const DeltaError(DeltaErrorCode.mismatch);
Never _badDelta() => throw const DeltaError(DeltaErrorCode.malformed);

/// Applies a structural delta, either a [FleeceDelta] or its wire value.
Object? apply(Object? old, Object? delta) {
  final result = _apply(old, delta is FleeceDelta ? delta.value : delta);
  return identical(result, _deleted) ? _mismatch() : result;
}

Object? _apply(Object? old, Object? delta) {
  if (delta is List && _array(delta)) {
    if (delta.isEmpty) return _deleted;
    if (delta.length == 1) return delta.first;
    if (delta.length == 3 &&
        delta[0] is String &&
        _equal(delta[1], 0) &&
        _equal(delta[2], 2)) {
      return old is String
          ? _patchString(old, delta[0] as String)
          : _mismatch();
    }
    return _badDelta();
  }
  if (delta is! Map) return delta;
  if (old is Map) {
    final result = Map<String, Object?>.from(old);
    for (final k in _names(delta)) {
      final v = _apply(old[k], delta[k]);
      if (identical(v, _deleted)) {
        result.remove(k);
      } else {
        result[k] = v;
      }
    }
    return result;
  }
  if (old is! List || !_array(old)) return _mismatch();
  final result = List<Object?>.of(old);
  (int, List)? tail;
  for (final k in _names(delta)) {
    final rest = k.endsWith('-');
    final text = rest ? k.substring(0, k.length - 1) : k;
    final n =
        RegExp(r'^\+?[0-9]+$').hasMatch(text) ? BigInt.tryParse(text) : null;
    if (n == null || n.bitLength > 64) _badDelta();
    final index = n > BigInt.from(old.length) ? old.length + 1 : n.toInt();
    if (rest) {
      final items = delta[k];
      if (items is! List || !_array(items)) _badDelta();
      tail = (index, items);
    } else {
      if (index >= old.length) _mismatch();
      final item = _apply(old[index], delta[k]);
      if (identical(item, _deleted)) _badDelta();
      result[index] = item;
    }
  }
  if (tail != null) {
    if (tail.$1 > result.length) _mismatch();
    result.replaceRange(tail.$1, result.length, tail.$2);
  }
  return result;
}

String _patchString(String input, String patch) {
  final old = _utf8(input), edits = _utf8(patch), out = BytesBuilder();
  var at = 0, offset = 0;
  while (offset < edits.length) {
    final start = offset;
    while (
        offset < edits.length && edits[offset] >= 48 && edits[offset] <= 57) {
      offset++;
    }
    if (start == offset || offset == edits.length) _badDelta();
    final count = BigInt.parse(String.fromCharCodes(edits, start, offset));
    if (count.bitLength > 64 || (BigInt.from(at) + count).bitLength > 64)
      _badDelta();
    final op = edits[offset++];
    if (op == 43) {
      if (count >= BigInt.from(edits.length - offset)) _badDelta();
      final end = offset + count.toInt();
      if (edits[end] != 124) _badDelta();
      out.add(Uint8List.sublistView(edits, offset, end));
      offset = end + 1;
    } else if (op == 45 || op == 61) {
      if (count > BigInt.from(old.length - at)) _mismatch();
      final end = at + count.toInt();
      if (op == 61) out.add(Uint8List.sublistView(old, at, end));
      at = end;
    } else {
      _badDelta();
    }
  }
  if (at != old.length) _mismatch();
  try {
    return _string(out.takeBytes());
  } on FormatException {
    return _mismatch();
  }
}
