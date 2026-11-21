import 'dart:typed_data';

import 'package:fleece/fleece.dart';
import 'package:geobase/geobase.dart' as geo;
import 'package:test/test.dart';

typedef User = ({String name, int age, FleeceUuid id});

void main() {
  test('lib example reads a single field and an owned document', () {
    final user = {
      'name': 'Milou',
      'id': FleeceUuid(Uint8List.fromList(List.filled(16, 7))),
      'age': FleeceInt.u8(9),
    };
    final bytes = encode(user);
    expect(Doc(bytes).root.asDict!['name']!.asString, 'Milou');
    expect(decode(bytes), user);
  });

  test('store example increments visits and indexes the name', () {
    final d = Doc.trusted(encode({'name': 'Milou', 'visits': 41}));
    final visits = d.root.asDict!['visits']!.asInt!;
    final b = update(d, Patch()..set(KeyPath.parse('visits'), visits + 1));
    expect(decode(b), {'name': 'Milou', 'visits': 42});
    expect(encodeKey('Milou')[1], lessThan(encodeKey('Tintin')[1]));
  });

  test('encoder example writes a dictionary', () {
    final b = (Encoder()
          ..beginDict()
          ..writeKey('foo')
          ..writeInt(123)
          ..endDict())
        .finish();
    expect(Doc(b).root.asDict!['foo']!.asI64, BigInt.from(123));
  });

  test('compaction example keeps only the second version', () {
    final first = encode('the first version');
    final d = Doc(Uint8List.fromList(
        [...first, ...appendDelta(first, 'the second version')]));
    expect(d.liveBytes, lessThan(d.bytes.length));
    final b = compact(d);
    expect(decode(b), 'the second version');
    expect(Doc(b).liveBytes, b.length);
  });

  test('patch example changes age, creates coat and removes a tag', () {
    final d = Doc(encode({
      'name': 'Milou',
      'age': 9,
      'tags': ['dog']
    }));
    final b = update(
        d,
        Patch()
          ..set(KeyPath.parse('age'), 10)
          ..set(KeyPath.parse('coat.colour'), 'white')
          ..remove(KeyPath.parse('tags[0]')));
    expect(decode(b), {
      'name': 'Milou',
      'age': 10,
      'tags': [],
      'coat': {'colour': 'white'}
    });
  });

  test('geo example reads a square and measures its area', () {
    final square = geo.Polygon([
      geo.PositionSeries.view([0, 0, 4, 0, 4, 4, 0, 4, 0, 0])
    ]);
    final stored =
        Doc(encode(geometryFromGeo(square))).root.asGeo! as geo.Polygon;
    expect(stored.area2D(), 16);
    expect(stored.isPointInPolygon2D((1.0, 1.0).toGeoPosition()), isTrue);
    expect(stored.toFleecePolygon(), square.toFleecePolygon());
  });

  test('serde example reads an application record with a typed UUID', () {
    final a = FleeceAdapter<User>(
      (u) => {'name': u.name, 'age': u.age, 'id': u.id},
      (r) => (
        name: r['name'].string,
        age: r['age'].integer(bits: 8, signed: false).toInt(),
        id: r['id'].typed<FleeceUuid>()
      ),
    );
    final u = (
      name: 'Milou',
      age: 9,
      id: FleeceUuid(Uint8List.fromList(List.filled(16, 7)))
    );
    expect(fromSlice(toVec(u, adapter: a), a), u);
  });
}
