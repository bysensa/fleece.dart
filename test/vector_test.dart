import 'dart:math' as math;
import 'dart:typed_data';
import 'package:fleece/fleece.dart';
import 'package:test/test.dart';

List<double> unit(int n, int seed) {
  var s = (BigInt.from(seed) * BigInt.parse('9e3779b97f4a7c15', radix: 16))
          .toUnsigned(64) |
      BigInt.one;
  final xs = List.generate(n, (_) {
    s = (s ^ (s << 13)).toUnsigned(64);
    s ^= s >> 7;
    s = (s ^ (s << 17)).toUnsigned(64);
    return (s >> 40).toInt() / 8388608 - 1.0;
  });
  final norm = math.sqrt(xs.fold(0.0, (n, x) => n + x * x));
  return Float32List.fromList([for (final x in xs) x / norm]);
}

(double, double, double) reference(List<double> a, List<double> b) {
  double dot = 0, l2 = 0, aa = 0, bb = 0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    final d = a[i] - b[i];
    l2 += d * d;
    aa += a[i] * a[i];
    bb += b[i] * b[i];
  }
  return (dot, l2, aa * bb == 0 ? 0 : dot / math.sqrt(aa * bb));
}

VectorRef view(FleeceVector v) => Doc(encode(v)).root.asVector!;
void main() {
  test('float vector equality treats both signs of zero like Rust', () {
    for (final make in [FleeceVector.f32, FleeceVector.f64]) {
      expect(diff(make([0.0]), make([-0.0])), isNull);
      expect(diff(make([double.nan]), make([double.nan])), isNotNull);
    }
  });
  test('a vector takes packed elements and its header', () {
    final x = unit(768, 1);
    for (final v in [
      FleeceVector.f32(x),
      FleeceVector.quantizedF16(x),
      FleeceVector.quantizedI8(x),
      FleeceVector.quantizedBits(x)
    ]) expect(encode(v).length, 768 * v.element.bits ~/ 8 + 8);
    expect(
        encode(x.map(FleeceFloat64.new).toList()).length, greaterThan(768 * 8));
  });
  test('distances in place agree with scalar f64 calculations', () {
    for (final n in [1, 7, 8, 9, 128, 768, 771]) {
      final a = unit(n, 3), b = unit(n, 4);
      final (dot, l2, cos) = reference(a, b);
      for (final v in [view(FleeceVector.f32(a)), view(FleeceVector.f64(a))]) {
        expect(v.dot(b), closeTo(dot, 1e-5));
        expect(v.l2Squared(b), closeTo(l2, 1e-5));
        expect(v.cosine(b), closeTo(cos, 1e-5));
        expect(v.toF32(), a);
        expect(v.get(n - 1), a.last);
        expect(v.get(n), isNull);
        expect(v.dot(b.sublist(1)), isNull);
      }
    }
  });
  test('all encodings preserve Rust f32 lane and tail rounding', () {
    final scratch = Float32List(1);
    double round(double x) {
      scratch[0] = x;
      return scratch[0];
    }

    int bits(double x) => (ByteData(4)..setFloat32(0, x)).getUint32(0);
    // Independent scalar reference: finish each of the eight lanes before
    // visiting the next. Rust adds the last partial block after the reduction.
    double sum(int n, double Function(int) term) {
      final end = n - n % 8;
      var total = 0.0;
      for (var lane = 0; lane < 8; lane++) {
        var subtotal = 0.0;
        for (var i = lane; i < end; i += 8) {
          subtotal = round(subtotal + round(term(i)));
        }
        total = round(total + subtotal);
      }
      for (var i = end; i < n; i++) {
        total = round(total + round(term(i)));
      }
      return total;
    }

    for (final n in [0, 1, 4, 7, 8, 9, 15, 16, 17, 63, 129]) {
      final input = List.generate(n, (i) => math.sin(i + 0.13));
      final wide = List.generate(n, (i) => math.cos(i + 0.71));
      final shifted = Float32List(n + 1)..setAll(1, wide);
      for (final vector in [
        FleeceVector.f32(input),
        FleeceVector.f64(input),
        FleeceVector.quantizedF16(input),
        FleeceVector.quantizedI8(input),
        FleeceVector.quantizedBits(input),
      ]) {
        final packed = encode(vector);
        final buffer = Uint8List(packed.length + 1)..setAll(1, packed);
        final borrowed = Doc(Uint8List.sublistView(buffer, 1)).root.asVector!;
        for (final v in [vector, borrowed]) {
          for (final q in [
            wide,
            Float32List.fromList(wide),
            Float32List.sublistView(shifted, 1)
          ]) {
            final dot = sum(n, (i) => v[i] * round(q[i]));
            final aa = sum(n, (i) => v[i] * v[i]);
            final bb = sum(n, (i) => round(q[i]) * round(q[i]));
            final lengths = round(math.sqrt(round(aa * bb)));
            final distance = sum(n, (i) {
              final d = round(v[i] - round(q[i]));
              return d * d;
            });
            expect(bits(v.dot(q)!), bits(dot));
            expect(bits(v.l2Squared(q)!), bits(distance));
            expect(bits(v.cosine(q)!),
                bits(lengths > 0 ? round(dot / lengths) : 0));
          }
        }
      }
    }
  });
  test('smaller elements retain the ranking of unit vectors', () {
    final a = unit(768, 5), b = unit(768, 6);
    final (dot, l2, cos) = reference(a, b);
    final h = view(FleeceVector.quantizedF16(a)),
        i = view(FleeceVector.quantizedI8(a)),
        bits = view(FleeceVector.quantizedBits(a));
    expect(h.dot(b), closeTo(dot, 1e-4));
    expect(h.l2Squared(b), closeTo(l2, 1e-4));
    expect(h.cosine(b), closeTo(cos, 1e-4));
    expect(h.dot(h.toF32()), closeTo(1, 0.002));
    expect(i.dot(b), closeTo(dot, 5e-3));
    expect(i.cosine(b), closeTo(cos, 5e-3));
    expect(bits.hamming(bits), 0);
    expect(bits.hamming(view(FleeceVector.quantizedBits(b))),
        inInclusiveRange(300, 469));
    expect(bits.dot(a), greaterThan(bits.dot(b)!));
    expect(i.hamming(bits), isNull);
  });
  test('prefix is a shorter embedding including partial bit bytes', () {
    final a = unit(768, 7), b = unit(768, 8), v = view(FleeceVector.f32(a));
    for (final n in [128, 256, 512, 768]) {
      final q = b.sublist(0, n);
      final (dot, _, cos) = reference(a.sublist(0, n), q);
      final p = v.prefix(n)!;
      expect(p.toF32(), a.take(n));
      expect(p.dot(q), closeTo(dot, 1e-5));
      expect(p.cosine(q), closeTo(cos, 1e-5));
    }
    expect(v.prefix(769), isNull);
    final one = view(FleeceVector.quantizedBits(a)),
        two = view(FleeceVector.quantizedBits(b));
    for (final n in [1, 7, 8, 13, 100, 768]) {
      final p = one.prefix(n)!;
      expect(p.toVector(), FleeceVector.quantizedBits(a.sublist(0, n)));
      expect(
          p.hamming(two.prefix(n)!),
          [
            for (var i = 0; i < n; i++)
              if ((a[i] > 0) != (b[i] > 0)) i
          ].length);
    }
  });
  test('vector read in a document beside other fields', () {
    final a = unit(256, 9),
        v = FleeceVector.quantizedF16(a),
        value = {'title': 'Tintin in Tibet', 'embedding': v};
    final bytes = encode(value), d = Doc(bytes).root.asDict!;
    expect(d['embedding']!.asVector!.dot(a), closeTo(1, 1e-3));
    expect(d['title']!.asVector, isNull);
    expect(decode(bytes), value);
  });
  test('generated vectors read back and measure as their values', () {
    final r = math.Random(141);
    for (var j = 0; j < 256; j++) {
      final n = r.nextInt(80),
          a = List.generate(n, (_) => r.nextDouble() * 2 - 1),
          q = Float32List.fromList(
              List.generate(n, (_) => r.nextDouble() * 2 - 1));
      final raw = [
        FleeceVector.f32(a),
        FleeceVector.f64(a),
        FleeceVector.quantizedF16(a),
        FleeceVector.quantizedI8(a),
        FleeceVector.quantizedBits(a)
      ][j % 5];
      final v = view(raw);
      final (dot, l2, cos) = reference(raw.toF32(), q);
      expect(v.toVector(), raw);
      expect(v.dot(q), closeTo(dot, 1e-4));
      expect(v.l2Squared(q), closeTo(l2, 1e-4));
      expect(v.cosine(q), closeTo(cos, 1e-4));
    }
  });
}
