part of '../fleece.dart';

// Read-only coordinate views adapt the two layouts without duplicating a
// line's points. geobase retains the List passed to PositionSeries.view.
final class _XYValues extends ListBase<double> {
  _XYValues(this.points);
  final FleeceLine points;
  @override
  int get length => 2 * points.length;
  @override
  double operator [](int i) => i.isEven ? points[i ~/ 2].$1 : points[i ~/ 2].$2;
  @override
  set length(int _) => throw UnsupportedError('Read-only coordinates');
  @override
  void operator []=(int i, double v) =>
      throw UnsupportedError('Read-only coordinates');
}

final class _GeoPoints extends ListBase<FleecePoint> {
  _GeoPoints(this.series);
  final geo.PositionSeries series;
  @override
  int get length => series.positionCount;
  @override
  FleecePoint operator [](int i) => (series.x(i), series.y(i));
  @override
  set length(int _) => throw UnsupportedError('Read-only coordinates');
  @override
  void operator []=(int i, FleecePoint v) =>
      throw UnsupportedError('Read-only coordinates');
}

FleeceLine _closed(FleeceLine line) => line.isEmpty || line.first == line.last
    ? line
    : List.unmodifiable([...line, line.first]);
geo.PositionSeries _series(FleeceLine line) {
  if (line is _PackedPoints) return geo.PositionSeries.view(line.xy);
  if (line is _GeoPoints && line.series.coordType == geo.Coords.xy) {
    return line.series;
  }
  return geo.PositionSeries.view(_XYValues(line));
}

geo.Position _position(FleecePoint p) => geo.Position.create(x: p.$1, y: p.$2);

extension FleecePointConversion on FleecePoint {
  geo.Position toGeoPosition() => _position(this);
  geo.Point toGeoPoint() => geo.Point(toGeoPosition());
}

extension PositionConversion on geo.Position {
  FleecePoint toFleecePoint() => (x, y);
}

extension GeoPointConversion on geo.Point {
  FleecePoint toFleecePoint() => position.toFleecePoint();
}

extension FleecePolygonConversion on FleecePolygon {
  geo.Polygon toGeoPolygon() =>
      geo.Polygon([for (final ring in this) _series(_closed(ring))]);
}

extension GeoPolygonConversion on geo.Polygon {
  FleecePolygon toFleecePolygon() => _polygonFromGeo(rings);
}

FleecePolygon _polygonFromGeo(List<geo.PositionSeries> rings) =>
    List.unmodifiable(rings.isEmpty
        ? [<FleecePoint>[]]
        : [for (final r in rings) _closed(_GeoPoints(r))]);

/// A one-position line is a valid Fleece geometry. geobase's general
/// LineString constructor requires at least two positions for a nonempty line.
final class _SinglePositionLine extends geo.LineString {
  _SinglePositionLine(this.chain) : super(geo.PositionSeries.empty());
  @override
  final geo.PositionSeries chain;
  @override
  bool get isEmptyByGeometry => false;
}

extension GeoConversion on FleeceGeometry {
  geo.Geometry toGeo() {
    final c = coordinates;
    switch (type) {
      case GeometryType.point:
        return geo.Point(_position(c as FleecePoint));
      case GeometryType.line:
        final s = _series(c as FleeceLine);
        return s.positionCount == 1
            ? _SinglePositionLine(s)
            : geo.LineString(s);
      case GeometryType.multiPoint:
        return geo.MultiPoint.from((c as FleeceLine).map(_position));
      case GeometryType.polygon:
        return (c as FleecePolygon).toGeoPolygon();
      case GeometryType.multiLine:
        return geo.MultiLineString(
            [for (final r in c as List<FleeceLine>) _series(r)]);
      case GeometryType.multiPolygon:
        return geo.MultiPolygon(
            [for (final p in c as List<FleecePolygon>) p.toGeoPolygon().rings]);
      case GeometryType.collection:
        return geo.GeometryCollection(
            [for (final g in c as List<FleeceGeometry>) g.toGeo()]);
    }
  }
}

/// Views XY coordinates of a geobase geometry. Keep its backing lists stable.
FleeceGeometry geometryFromGeo(geo.Geometry shape) {
  switch (shape) {
    case geo.Point():
      return FleeceGeometry.point(shape.position.x, shape.position.y);
    case geo.LineString():
      return FleeceGeometry<FleeceLine>._(
          GeometryType.line, _GeoPoints(shape.chain), _points);
    case geo.MultiPoint():
      return FleeceGeometry.multiPoint(
          [for (final p in shape.positions) (p.x, p.y)]);
    case geo.Polygon():
      return FleeceGeometry<FleecePolygon>._(GeometryType.polygon,
          shape.toFleecePolygon(), FleeceGeometry._packRings);
    case geo.MultiLineString():
      final lines =
          List<FleeceLine>.unmodifiable(shape.chains.map(_GeoPoints.new));
      return FleeceGeometry<FleecePolygon>._(
          GeometryType.multiLine, lines, FleeceGeometry._packRings);
    case geo.MultiPolygon():
      final polys = List<FleecePolygon>.unmodifiable(
          shape.ringArrays.map(_polygonFromGeo));
      return FleeceGeometry<List<FleecePolygon>>._(GeometryType.multiPolygon,
          polys, (parts) => parts.map(FleeceGeometry._packRings).toList());
    case geo.GeometryCollection():
      return FleeceGeometry.collection(
          shape.geometries.map(geometryFromGeo).toList());
    default:
      throw ArgumentError.value(shape, 'geometry');
  }
}

FleeceGeometry geometryFromSegment(FleecePoint a, FleecePoint b) =>
    FleeceGeometry.line([a, b]);
FleeceGeometry geometryFromBox(geo.Box b) => FleeceGeometry.polygon([
      [
        (b.maxX, b.minY),
        (b.maxX, b.maxY),
        (b.minX, b.maxY),
        (b.minX, b.minY),
        (b.maxX, b.minY)
      ]
    ]);
FleeceGeometry geometryFromTriangle(
    FleecePoint a, FleecePoint b, FleecePoint c) {
  final cross = (b.$1 - a.$1) * (c.$2 - a.$2) - (b.$2 - a.$2) * (c.$1 - a.$1);
  return FleeceGeometry.polygon([
    cross < 0 ? [c, b, a, c] : [a, b, c, a]
  ]);
}

extension GeometryReader on ValueRef {
  FleeceGeometry? get asGeometry {
    if (item.extensionId != ExtKind.geometry.index) return null;
    try {
      return read() as FleeceGeometry;
    } on FormatException {
      return null;
    }
  }

  geo.Geometry? get asGeo => asGeometry?.toGeo();
}
