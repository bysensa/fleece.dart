part of '../fleece.dart';

final class KeyPathError extends FormatException {
  const KeyPathError(int at) : super('Malformed key path', null, at);
  int get at => offset!;
}

/// A compiled path. Indexes count from the end when negative. A backslash
/// quotes the next character of a field name. Error offsets are UTF-8 bytes.
final class KeyPath {
  KeyPath._(this._steps);
  final List<Object> _steps;
  @override
  bool operator ==(Object other) =>
      other is KeyPath && _equal(_steps, other._steps);
  @override
  int get hashCode => Object.hashAll(_steps);
  factory KeyPath.parse(String path) {
    final bytes = _utf8(path);
    var at = path.startsWith(r'$.')
        ? 2
        : path == r'$' || path.startsWith(r'$[')
            ? 1
            : 0;
    var after = false;
    final steps = <Object>[];
    while (at < bytes.length) {
      if (bytes[at] == 91) {
        final end = bytes.indexOf(93, at + 1);
        if (end < 0) throw KeyPathError(at);
        final index = String.fromCharCodes(bytes, at + 1, end);
        final n = RegExp(r'^[+-]?[0-9]+$').hasMatch(index)
            ? BigInt.tryParse(index)
            : null;
        if (n == null || n.bitLength >= 64) throw KeyPathError(at);
        steps.add(n);
        at = end + 1;
      } else if (bytes[at] == 46 && after) {
        at++;
        if (at == bytes.length || bytes[at] == 46 || bytes[at] == 91)
          throw KeyPathError(at);
        after = false;
        continue;
      } else {
        if (after || bytes[at] == 46) throw KeyPathError(at);
        final key = <int>[];
        while (at < bytes.length && bytes[at] != 46 && bytes[at] != 91) {
          if (bytes[at] == 92 && ++at == bytes.length)
            throw KeyPathError(at - 1);
          key.add(bytes[at++]);
        }
        steps.add(_string(Uint8List.fromList(key)));
      }
      after = true;
    }
    return KeyPath._(steps);
  }

  ValueRef? eval(ValueRef root) {
    ValueRef? value = root;
    for (final step in _steps) {
      if (step is String) {
        value = value?.asDict?[step];
      } else {
        final array = value?.asArray;
        if (array == null) return null;
        final index = _index(step as BigInt, array.length);
        value = index == null ? null : array.get(index);
      }
      if (value == null) break;
    }
    return value;
  }
}

int? _index(BigInt n, int length) {
  final end = BigInt.from(length);
  final index = n.isNegative ? end + n : n;
  return index.isNegative || index > end ? null : index.toInt();
}

enum DeltaErrorCode { malformed, mismatch, decode, encode }

final class DeltaError extends FormatException {
  const DeltaError(this.code, [this.cause]) : super('Invalid Fleece delta');
  final DeltaErrorCode code;
  final Object? cause;
  @override
  String toString() =>
      'DeltaError.' + code.name + (cause == null ? '' : ' ($cause)');
}

T _deltaOperation<T>(T Function() run) {
  try {
    return run();
  } on EncodeError catch (cause) {
    throw DeltaError(DeltaErrorCode.encode, cause);
  } on DecodeError catch (cause) {
    throw DeltaError(DeltaErrorCode.decode, cause);
  }
}

const _remove = _PatchNode.remove();

final class _PatchNode {
  _PatchNode.inside()
      : value = null,
        children = <Object, _PatchNode>{};
  const _PatchNode.set(this.value) : children = null;
  const _PatchNode.remove()
      : value = null,
        children = null;
  final Object? value;
  final Map<Object, _PatchNode>? children;
}

final class Patch {
  var _root = _PatchNode.inside();
  bool get isEmpty => _root.children?.isEmpty == true;
  Patch set(KeyPath path, Object? value) => _put(path, _PatchNode.set(value));
  Patch remove(KeyPath path) => _put(path, _remove);
  Patch _put(KeyPath path, _PatchNode change) {
    if (path._steps.isEmpty) {
      _root = change;
    } else {
      if (_root.children == null) _root = _PatchNode.inside();
      var node = _root;
      for (var i = 0; i < path._steps.length - 1; i++) {
        final step = path._steps[i];
        final child = node.children![step];
        node = child?.children != null
            ? child!
            : (node.children![step] = _PatchNode.inside());
      }
      node.children![path._steps.last] = change;
    }
    return this;
  }
}

Uint8List update(Doc doc, Patch patch) => _deltaOperation(() =>
    (Encoder(sharedKeys: doc.sharedKeys, fixedSharedKeys: true)
          ..writeUpdated(doc.root, patch))
        .finish());

Uint8List? extract(Doc doc, KeyPath path) => _deltaOperation(() {
      final value = path.eval(doc.root);
      if (value == null) return null;
      return (Encoder(sharedKeys: doc.sharedKeys, fixedSharedKeys: true)
            ..writeCopy(value))
          .finish();
    });

extension UpdateEncoder on Encoder {
  void writeUpdated(ValueRef value, Patch patch) => _deltaOperation(() {
        // A changed branch may discard an invalid subtree. Charge only copied
        // subtrees, against one shared budget for the whole edit.
        final room = _ReadRoom(value.doc);
        void copy(ValueRef v) => _copyWithRoom(v, room);

        void visit(ValueRef? at, _PatchNode node) {
          final children = node.children;
          if (children == null) {
            if (identical(node, _remove))
              throw const DeltaError(DeltaErrorCode.mismatch);
            writeValue(node.value);
            return;
          }
          if (children.isEmpty && at != null) {
            copy(at);
            return;
          }
          final dict = at?.asDict;
          if ((dict != null || at == null) &&
              children.keys.every((k) => k is String)) {
            beginDict();
            if (dict != null) {
              if (!dict._gaveAll) _mismatch();
              for (final e in dict.entries) {
                final change = children[e.key];
                if (identical(change, _remove)) continue;
                writeKey(e.key);
                if (change == null) {
                  copy(e.value);
                } else {
                  visit(e.value, change);
                }
              }
            }
            for (final key in _names(children)) {
              final change = children[key]!;
              if (dict?[key] == null && !identical(change, _remove)) {
                writeKey(key);
                visit(null, change);
              }
            }
            endDict();
            return;
          }
          final array = at?.asArray;
          if (array == null || children.keys.any((k) => k is! BigInt))
            throw const DeltaError(DeltaErrorCode.mismatch);
          final changes = <int, _PatchNode>{};
          for (final n in children.keys.cast<BigInt>().toList()..sort()) {
            final i = _index(n, array.length);
            if (i == null) throw const DeltaError(DeltaErrorCode.mismatch);
            changes[i] = children[n]!;
          }
          beginArray();
          for (var i = 0; i < array.length; i++) {
            final change = changes[i];
            if (change == null) {
              copy(array.get(i) ?? value.doc.valueAt(-1));
            } else if (!identical(change, _remove)) {
              visit(array[i], change);
            }
          }
          final tail = changes[array.length];
          if (tail != null && !identical(tail, _remove)) visit(null, tail);
          endArray();
        }

        visit(value, patch._root);
      });
}
