import 'dart:typed_data';
import 'package:fleece/fleece.dart';
import 'package:test/test.dart';

void pointer(List<int> b, int target, [bool wide = false]) {
  final units = (b.length - target) ~/ 2;
  if (wide) {
    b.addAll([
      128 | (units >>> 24),
      units >>> 16 & 255,
      units >>> 8 & 255,
      units & 255
    ]);
  } else {
    b.addAll([128 | (units >> 8), units & 255]);
  }
}

Uint8List held(int levels, int width) {
  final b = encode(['some string']).toList()
    ..removeLast()
    ..removeLast();
  var last = b.length - 4;
  for (var i = 0; i < levels; i++) {
    final at = b.length;
    b.addAll([96, width]);
    for (var k = 0; k < width; k++) {
      pointer(b, last);
    }
    last = at;
  }
  pointer(b, last);
  return Uint8List.fromList(b);
}

Uint8List stringUsed(int length, int uses) {
  final b = encode('x' * length).toList()
    ..removeLast()
    ..removeLast();
  final at = b.length;
  b.addAll([104 | (uses >> 8), uses & 255]);
  for (var i = 0; i < uses; i++) {
    pointer(b, 0, true);
  }
  pointer(b, at, true);
  b.addAll([128, 2]);
  return Uint8List.fromList(b);
}

int putText(List<int> b, String s) {
  final at = b.length;
  b.add(64 + s.length);
  b.addAll(s.codeUnits);
  if (b.length.isOdd) b.add(0);
  return at;
}

int dictionary(
    List<int> b, String prefix, int count, int? parent, bool inherit) {
  final keys = [
    for (var i = 0; i < count; i++)
      putText(b, prefix + i.toString().padLeft(4, '0'))
  ];
  final link = parent != null && !inherit ? putText(b, 'j') : null;
  final at = b.length, n = count + (parent == null ? 0 : 1);
  b.addAll([120 | n >> 8, n & 255]);
  if (parent != null) {
    if (link == null) {
      b.addAll([8, 0, 0, 0]);
    } else {
      pointer(b, link, true);
    }
    pointer(b, parent, true);
  }
  for (var i = 0; i < count; i++) {
    pointer(b, keys[i], true);
    b.addAll([0, i % 100, 0, 0]);
  }
  return at;
}

Uint8List dictionaries(int levels, int entries, bool inherit,
    {int children = 0, int own = 0}) {
  final b = <int>[];
  int? parent;
  for (var i = 0; i < levels; i++) {
    parent = dictionary(b, 'k' + i.toString().padLeft(3, '0'), entries, parent,
        children != 0 || inherit);
  }
  var root = parent!;
  if (children != 0) {
    final targets = [
      for (var i = 0; i < children; i++)
        dictionary(b, 's' + i.toString().padLeft(5, '0'), own,
            inherit ? parent : null, true),
      parent
    ];
    root = b.length;
    b.addAll([104, targets.length]);
    for (final t in targets) {
      pointer(b, t, true);
    }
  }
  pointer(b, root, true);
  b.addAll([128, 2]);
  return Uint8List.fromList(b);
}

int keyed(List<int> b, int? parent, List<(Object, int)> entries) {
  entries.sort((a, b) {
    final x = a.$1, y = b.$1;
    if (x is int && y is int) return x.compareTo(y);
    if (x is String && y is String) return x.compareTo(y);
    return x is int ? -1 : 1;
  });
  final keys = [
    for (final (k, _) in entries) k is String ? putText(b, k) : null
  ];
  final at = b.length;
  b.addAll([112, entries.length + (parent == null ? 0 : 1)]);
  if (parent != null) {
    b.addAll([8, 0]);
    pointer(b, parent);
  }
  for (var i = 0; i < entries.length; i++) {
    final (k, v) = entries[i];
    final p = keys[i];
    if (p == null) {
      b.addAll([0, k as int]);
    } else {
      pointer(b, p);
    }
    b.addAll([0, v]);
  }
  return at;
}

Matcher refused(DecodeErrorCode code) =>
    throwsA(isA<DecodeError>().having((e) => e.code, 'code', code));

void main() {
  test('one long string under many pointers is refused', () {
    final b = stringUsed(4000, 2000);
    expect(b.length, lessThan(12100));
    expect(() => Doc(b), refused(DecodeErrorCode.tooManyBytes));
    expect(Doc.trusted(b).root.read, refused(DecodeErrorCode.tooManyBytes));
    final big = List.filled(200, 'x' * 4000),
        small = List.filled(2000, 'fifteen bytes..');
    expect(encode(big).length, greaterThan(800000));
    expect(decode(encode(big)), big);
    expect(encode(small).length, lessThan(4100));
    expect(decode(encode(small)), small);
    expect(Doc(stringUsed(4000, 2)).root.asArray!.length, 2);
  });
  test('documents written by incremental changes stay within the room', () {
    String key(int i) =>
        'a key long enough not to be written once ' +
        i.toString().padLeft(3, '0');
    String text(int turn, int i) =>
        turn.toString().padLeft(4, '0') +
        ' ' +
        i.toString().padLeft(3, '0') +
        ' ' +
        'long text ' * 8;
    Map<String, Object?> fields(int turn) =>
        {for (var i = 0; i < 40; i++) key(i): text(turn, i)};
    var inner = fields(0);
    Map<String, Object?> outer() => {
          for (var i = 0; i < 8; i++) key(100 + i): List.filled(3, text(0, i)),
          key(200): inner
        };
    var b = encode(outer());
    for (var turn = 1; turn < 60; turn++) {
      if (turn % 7 == 0) {
        inner = fields(turn);
      } else if (turn % 7 == 1) {
        inner.remove(key(turn % 40));
      } else {
        inner[key(turn % 40)] = text(turn, 0);
      }
      b = Uint8List.fromList([...b, ...appendDelta(b, outer())]);
      expect(decode(b), outer());
    }
    expect(decode(compact(Doc(b))), outer());
  });
  test('untrusted shared subtrees end every walk and do not expand Kind checks',
      () {
    final b = held(60, 2), d = Doc.trusted(b);
    expect(b.length, lessThan(400));
    expect(d.validate, refused(DecodeErrorCode.tooManyValues));
    expect(d.root.read, refused(DecodeErrorCode.tooManyValues));
    expect(() => compact(d), throwsFormatException);
    expect(() => Encoder().writeCopy(d.root), throwsA(isA<EncodeError>()));
    expect(() => extract(d, KeyPath.parse('[0]')), throwsA(anything));
    expect(() => update(d, Patch()..set(KeyPath.parse('[0]'), 1)),
        throwsA(anything));
    expect(dump(d).length, lessThan(4000));
    expect(d.liveBytes, lessThanOrEqualTo(b.length));
    var k = const Kind.array(Kind.string);
    for (var i = 0; i < 60; i++) {
      k = Kind.array(k);
    }
    expect(k.conforms(d.root), isTrue);
    expect(Kind.array(k).conforms(d.root), isFalse);
  });
  test('application and owned serde walks stop at expansion limits', () {
    final owned = FleeceAdapter<Object?>((v) => v, (r) => r.value);
    for (final (b, code) in [
      (held(60, 2), DecodeErrorCode.tooManyValues),
      (stringUsed(4000, 2000), DecodeErrorCode.tooManyBytes)
    ]) {
      final root = Doc.trusted(b).root;
      expect(() => fromRef(root, owned), throwsA(isA<SerdeError>()));
      Object readTree(SerdeReader r) =>
          r.ref.asArray == null ? r.string : r.sequence.map(readTree).toList();
      expect(
          () => fromRef(root, FleeceAdapter<Object?>((v) => v, readTree)),
          throwsA(isA<SerdeError>()
              .having((e) => (e.cause as DecodeError).code, 'code', code)));
    }
  });
  test('a dictionary inherits through at most MAX_INHERITED parents', () {
    final d = Doc(dictionaries(maxInherited + 1, 3, true)).root.asDict!;
    expect(d.length, 3 * (maxInherited + 1));
    expect(d['k0000002']!.asInt, 2);
    expect(() => Doc(dictionaries(maxInherited + 2, 3, true)),
        refused(DecodeErrorCode.tooDeep));
    expect(Doc(dictionaries(100, 3, false)).root.asDict, isNotNull);
  });
  test('a numbered and a spelled key are the same across inheritance', () {
    String name(int i) => 'k' + i.toString().padLeft(2, '0');
    final keys = SharedKeys();
    for (var i = 0; i < 40; i++) {
      keys.add(name(i));
    }
    final twice = <int>[];
    final at = keyed(twice, null, [(7, 1), ('k07', 2)]);
    pointer(twice, at);
    expect(() => Doc(Uint8List.fromList(twice), sharedKeys: keys),
        refused(DecodeErrorCode.unsortedKeys));
    final b = <int>[];
    final parent = keyed(
        b, null, [for (var i = 0; i < 40; i++) (i.isEven ? i : name(i), i)]);
    final root = keyed(b, parent, [
      for (var i = 0; i < 40; i++)
        if (i % 5 != 0) (i % 4 < 2 ? i : name(i), 100 + i)
    ]);
    pointer(b, root);
    expect(decode(Uint8List.fromList(b), sharedKeys: keys),
        {for (var i = 0; i < 40; i++) name(i): i % 5 == 0 ? i : 100 + i});
  });
  test('cost of inherited dictionaries and shared parents', () {
    void measure(String name, Uint8List b) {
      final watch = Stopwatch()..start();
      final d = Doc(b);
      for (var i = 0; i < 1000; i++) {
        d.root.asDict?['absent'];
      }
      print('$name: ' + watch.elapsed.toString());
    }

    for (final (levels, entries) in [
      (1, 3600),
      (5, 720),
      (9, 400),
      (17, 211)
    ]) {
      for (final inherit in [true, false]) {
        measure('$levels x $entries, inherit=$inherit',
            dictionaries(levels, entries, inherit));
      }
    }
    for (final (l, e, c, o) in [
      (16, 64, 20, 256),
      (16, 16, 24, 64),
      (4, 64, 20, 64)
    ]) {
      for (final inherit in [true, false]) {
        measure('$c x $o over $l x $e, inherit=$inherit',
            dictionaries(l, e, inherit, children: c, own: o));
      }
    }
  },
      skip:
          'Timing benchmark. Run with dart test --run-skipped test/limits_test.dart');
}
