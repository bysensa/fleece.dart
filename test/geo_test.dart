import 'dart:math';
import 'dart:typed_data';
import 'package:fleece/fleece.dart';
import 'package:geobase/geobase.dart' as geo;
import 'package:test/test.dart';

final square = FleeceGeometry.polygon([
  [(0, 0), (4, 0), (4, 4), (0, 4), (0, 0)],
  [(2, 2), (3, 2), (3, 3), (2, 3), (2, 2)]
]);
void main() {
  test('point, coordinate and polygon conversions preserve XY', () {
    const p = (1.0, -2.75);
    expect(p.toGeoPosition().toFleecePoint(), p);
    expect(p.toGeoPoint().toFleecePoint(), p);
    expect(square.coordinates.toGeoPolygon().toFleecePolygon(),
        square.coordinates);
  });
  test('every geobase geometry converts both ways including nested collections',
      () {
    final line = <FleecePoint>[(0, 0), (1, 2), (-3.5, 0.25)];
    final shapes = <FleeceGeometry>[
      FleeceGeometry.point(1.5, -2),
      FleeceGeometry.line(line),
      FleeceGeometry.line([]),
      square,
      FleeceGeometry.multiPoint(line),
      FleeceGeometry.multiLine([line, line]),
      FleeceGeometry.multiPolygon([square.coordinates, square.coordinates])
    ];
    final c = FleeceGeometry.collection(shapes);
    for (final g in [
      ...shapes,
      c,
      FleeceGeometry.collection([c])
    ]) {
      expect(geometryFromGeo(g.toGeo()), g);
      expect(geometryFromGeo(Doc(encode(g)).root.asGeo!), g);
      expect(decode(encode(g)), g);
    }
  });
  test('segments, boxes and triangles become line strings and polygons', () {
    expect(geometryFromSegment((0, 0), (3, 4)),
        FleeceGeometry.line([(0, 0), (3, 4)]));
    final r =
        geometryFromBox(geo.Box.view([0, 0, 2, 1])).toGeo() as geo.Polygon;
    final t =
        geometryFromTriangle((0, 0), (2, 0), (0, 2)).toGeo() as geo.Polygon;
    expect(r.exterior!.positionCount, 5);
    expect(r.area2D(), 2);
    expect(t.exterior!.positionCount, 4);
    expect(t.area2D(), 2);
  });
  test('geobase algorithms operate on a selected document field', () {
    final d = Doc(encode({
      'name': 'Moulinsart',
      'grounds': square,
      'gate': FleeceGeometry.point(1, 1)
    })).root.asDict!;
    final grounds = d['grounds']!.asGeo! as geo.Polygon,
        gate = d['gate']!.asGeo! as geo.Point;
    expect(grounds.area2D(), 15);
    final bounds = grounds.calculateBounds()!;
    expect([bounds.minX, bounds.minY, bounds.maxX, bounds.maxY], [0, 0, 4, 4]);
    expect(grounds.isPointInPolygon2D(gate.position), isTrue);
    for (final p in [
      [2.5, 2.5],
      [9.0, 9.0]
    ]) expect(grounds.isPointInPolygon2D(geo.Position.view(p)), isFalse);
    expect(grounds.centroid2D()!.x, inExclusiveRange(1.9, 2));
    expect(d['name']!.asGeo, isNull);
    expect(d['gate']!.asGeometry, FleeceGeometry.point(1, 1));
  });
  test('conversion closes exterior and interior polygon rings', () {
    final open = <FleecePoint>[(0, 0), (1, 0), (1, 1)],
        closed = <FleecePoint>[...open, open.first];
    expect(geometryFromGeo(FleeceGeometry.polygon([open, open]).toGeo()),
        FleeceGeometry.polygon([closed, closed]));
  });
  test('coordinate buffers can be handed across both APIs without copying', () {
    final xy = List.generate(2000, (i) => i.isEven ? i / 2 : 0.5);
    final series = geo.PositionSeries.view(xy), line = geo.LineString(series);
    expect(
        identical(
            (geometryFromGeo(line).toGeo() as geo.LineString).chain, series),
        isTrue);
    final multi = geo.MultiLineString([series, series, series]);
    expect(
        identical(
            (geometryFromGeo(multi).toGeo() as geo.MultiLineString).chains[1],
            series),
        isTrue);
    final ring = geo.PositionSeries.view([...xy, xy[0], xy[1]]);
    expect(
        identical(
            (geometryFromGeo(geo.Polygon([ring])).toGeo() as geo.Polygon)
                .exterior,
            ring),
        isTrue);
  });
  test('decoded rings own their coordinates even with unaligned input', () {
    final encoded = encode(square);
    final source = Uint8List(encoded.length + 1)..setAll(1, encoded);
    final value = Doc(Uint8List.sublistView(source, 1)).root.asGeometry!;
    final rings = value.coordinates as FleecePolygon;
    final polygon = value.toGeo() as geo.Polygon;
    source.fillRange(0, source.length, 0);
    expect(rings, square.coordinates);
    expect(polygon.area2D(), 15);
    expect(() => rings.first[0] = (5, 6), throwsUnsupportedError);
    expect(() => rings.first.clear(), throwsUnsupportedError);
    final xy = polygon.exterior!.values;
    if (xy is List<double>) {
      expect(() => xy[0] = 5, throwsUnsupportedError);
    }
    expect(encode(value), encoded);
  });
  test('generated closed shapes round trip through geobase and Fleece', () {
    final r = Random(2026);
    for (var i = 0; i < 256; i++) {
      final p = <FleecePoint>[
        for (var j = 0; j < r.nextInt(6); j++)
          (r.nextDouble() * 360 - 180, r.nextDouble() * 180 - 90)
      ];
      final ring = [...p, if (p.isNotEmpty) p.first];
      final g = FleeceGeometry.collection([
        FleeceGeometry.line(p),
        FleeceGeometry.polygon([ring]),
        FleeceGeometry.multiPolygon([
          [ring, ring]
        ])
      ]);
      expect(geometryFromGeo(g.toGeo()), g);
      expect(geometryFromGeo(Doc(encode(g)).root.asGeo!), g);
    }
  });
}
