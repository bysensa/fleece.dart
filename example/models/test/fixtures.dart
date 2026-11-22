import 'dart:typed_data' as typed;

import 'package:fleece/fleece.dart' as fl;
import 'package:fleece_model_example/note.dart' as notes;

part 'fixtures.fleece.g.dart';

@fl.FleeceModel()
class Packet {
  const Packet(
    this.bytes,
    this.id,
    this.timestamp, {
    required this.sequence,
    this.weight = 1.0,
    this.enabled = true,
    this.destinations = const {},
    this.precise,
    this.small,
    this.home,
    this.attributes = const {},
    this.cost = 0,
  });

  @fl.FleeceKey(r'$bytes[0]')
  final typed.Uint8List bytes;
  final fl.FleeceUuid id;
  final DateTime timestamp;
  final BigInt sequence;
  final double weight;
  final bool enabled;
  final Map<String, List<notes.Address?>> destinations;
  final fl.FleeceFloat64? precise;
  final fl.FleeceFloat32? small;
  final notes.Address? home;
  final Map<String, dynamic> attributes;
  final num cost;
}

@fl.FleeceModel()
class Branch {
  const Branch(this.name, {this.child});
  final String name;
  final Branch? child;
}

@fl.FleeceModel(name: 'Shipment')
class Delivery {
  static const _initialCity = 'Lyon';
  const Delivery({
    this.address = const notes.Address(_initialCity, postcode: '69000'),
  });
  final notes.Address address;
}

@fl.FleeceModel()
class CounterModel {
  CounterModel(int count) {
    this.count = count;
  }
  int count = 0;
  bool get isEven => count.isEven;
  void increment([int by = 1]) => count += by;
}

@fl.FleeceModel()
abstract class _MeterModel {
  const factory _MeterModel(int tick) = _Meter;
  int get tick;
  bool get odd;
}

class _Meter implements _MeterModel {
  const _Meter(this.tick);
  @override
  final int tick;
  @override
  bool get odd => tick.isOdd;
}
