// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'fixtures.dart';

// **************************************************************************
// _Generator
// **************************************************************************

typedef $PacketFleece = PacketRecord;

extension $PacketFleeceFormat on Packet {
  static final codec = fl.FleeceModelCodec<Packet, PacketRecord>(
    _writePacket,
    _readPacket,
    PacketRecord._,
  );
  typed.Uint8List toFleece({fl.SharedKeys? sharedKeys}) {
    final model = this;
    return model is PacketRecord
        ? model._$fleeceCursor.toBytes(sharedKeys: sharedKeys)
        : codec.encode(model, sharedKeys: sharedKeys);
  }
}

abstract final class _PacketFields {
  static final bytes = fl.FleeceField<typed.Uint8List>(
    "\$bytes[0]",
    fl.FleeceCodecs.bytes,
  );
  static final id = fl.FleeceField<fl.FleeceUuid>(
    "id",
    fl.FleeceCodecs.native<fl.FleeceUuid>(),
  );
  static final timestamp = fl.FleeceField<DateTime>(
    "timestamp",
    fl.FleeceCodecs.dateTime,
  );
  static final sequence = fl.FleeceField<BigInt>(
    "sequence",
    fl.FleeceCodecs.bigInteger,
  );
  static final weight = fl.FleeceField<double>(
    "weight",
    fl.FleeceCodecs.floating,
    whenMissing: ([double value = 1.0]) => value,
  );
  static final enabled = fl.FleeceField<bool>(
    "enabled",
    fl.FleeceCodecs.boolean,
    whenMissing: ([bool value = true]) => value,
  );
  static final destinations = fl.FleeceField<Map<String, List<notes.Address?>>>(
    "destinations",
    fl.FleeceCodecs.map(
      fl.FleeceCodecs.list(notes.$AddressFleeceFormat.codec.nullable()),
    ),
    whenMissing: ([Map<String, List<notes.Address?>> value = const {}]) =>
        value,
  );
  static final precise = fl.FleeceField<fl.FleeceFloat64?>(
    "precise",
    fl.FleeceCodecs.float64.nullable(),
    whenMissing: () => null,
  );
  static final small = fl.FleeceField<fl.FleeceFloat32?>(
    "small",
    fl.FleeceCodecs.float32.nullable(),
    whenMissing: () => null,
  );
  static final home = fl.FleeceField<notes.Address?>(
    "home",
    notes.$AddressFleeceFormat.codec.nullable(),
    whenMissing: () => null,
  );
  static final attributes = fl.FleeceField<Map<String, dynamic>>(
    "attributes",
    fl.FleeceCodecs.map(fl.FleeceCodecs.value),
    whenMissing: ([Map<String, dynamic> value = const {}]) => value,
  );
  static final cost = fl.FleeceField<num>(
    "cost",
    fl.FleeceCodecs.number,
    whenMissing: ([num value = 0]) => value,
  );
}

void _writePacket(fl.Encoder e, Packet value) {
  if (value is PacketRecord) {
    value._$fleeceCursor.writeTo(e);
    return;
  }
  e.beginDict();
  _PacketFields.bytes.write(e, value.bytes);
  _PacketFields.attributes.write(e, value.attributes);
  _PacketFields.cost.write(e, value.cost);
  _PacketFields.destinations.write(e, value.destinations);
  _PacketFields.enabled.write(e, value.enabled);
  _PacketFields.home.write(e, value.home);
  _PacketFields.id.write(e, value.id);
  _PacketFields.precise.write(e, value.precise);
  _PacketFields.sequence.write(e, value.sequence);
  _PacketFields.small.write(e, value.small);
  _PacketFields.timestamp.write(e, value.timestamp);
  _PacketFields.weight.write(e, value.weight);
  e.endDict();
}

Packet _readPacket(fl.ValueRef ref) {
  final dict = fl.FleeceCodecs.dictionary(ref);
  return Packet(
    _PacketFields.bytes.read(dict["\$bytes[0]"]),
    _PacketFields.id.read(dict["id"]),
    _PacketFields.timestamp.read(dict["timestamp"]),
    sequence: _PacketFields.sequence.read(dict["sequence"]),
    weight: _PacketFields.weight.read(dict["weight"]),
    enabled: _PacketFields.enabled.read(dict["enabled"]),
    destinations: _PacketFields.destinations.read(dict["destinations"]),
    precise: _PacketFields.precise.read(dict["precise"]),
    small: _PacketFields.small.read(dict["small"]),
    home: _PacketFields.home.read(dict["home"]),
    attributes: _PacketFields.attributes.read(dict["attributes"]),
    cost: _PacketFields.cost.read(dict["cost"]),
  );
}

final class PacketRecord implements Packet {
  factory PacketRecord(
    typed.Uint8List bytes, {
    typed.Uint8List? base,
    fl.SharedKeys? sharedKeys,
    fl.FleeceTracking Function()? tracking,
  }) => $PacketFleeceFormat.codec.open(
    bytes,
    base: base,
    sharedKeys: sharedKeys,
    tracking: tracking,
  );
  final fl.FleeceCursor _$fleeceCursor;
  PacketRecord._(this._$fleeceCursor);
  @override
  typed.Uint8List get bytes => _$fleeceCursor.get(_PacketFields.bytes);
  set bytes(typed.Uint8List value) =>
      _$fleeceCursor.set(_PacketFields.bytes, value);
  @override
  fl.FleeceUuid get id => _$fleeceCursor.get(_PacketFields.id);
  set id(fl.FleeceUuid value) => _$fleeceCursor.set(_PacketFields.id, value);
  @override
  DateTime get timestamp => _$fleeceCursor.get(_PacketFields.timestamp);
  set timestamp(DateTime value) =>
      _$fleeceCursor.set(_PacketFields.timestamp, value);
  @override
  BigInt get sequence => _$fleeceCursor.get(_PacketFields.sequence);
  set sequence(BigInt value) =>
      _$fleeceCursor.set(_PacketFields.sequence, value);
  @override
  double get weight => _$fleeceCursor.get(_PacketFields.weight);
  set weight(double value) => _$fleeceCursor.set(_PacketFields.weight, value);
  @override
  bool get enabled => _$fleeceCursor.get(_PacketFields.enabled);
  set enabled(bool value) => _$fleeceCursor.set(_PacketFields.enabled, value);
  late final _$destinationsCursor = _$fleeceCursor.child(
    _PacketFields.destinations,
  );
  @override
  Map<String, List<notes.$AddressFleece?>> get destinations =>
      _$destinationsCursor.mapItems<List<notes.$AddressFleece?>>(
        (item0) => item0.listItems<notes.$AddressFleece?>(
          (item1) =>
              item1.optionalObject(notes.$AddressFleeceFormat.codec.bind),
        ),
      );
  set destinations(Map<String, List<notes.Address?>> value) =>
      _$fleeceCursor.set(_PacketFields.destinations, value);
  @override
  fl.FleeceFloat64? get precise => _$fleeceCursor.get(_PacketFields.precise);
  set precise(fl.FleeceFloat64? value) =>
      _$fleeceCursor.set(_PacketFields.precise, value);
  @override
  fl.FleeceFloat32? get small => _$fleeceCursor.get(_PacketFields.small);
  set small(fl.FleeceFloat32? value) =>
      _$fleeceCursor.set(_PacketFields.small, value);
  late final _$homeCursor = _$fleeceCursor.child(_PacketFields.home);
  @override
  notes.$AddressFleece? get home =>
      _$homeCursor.optionalObject(notes.$AddressFleeceFormat.codec.bind);
  set home(notes.Address? value) =>
      _$fleeceCursor.set(_PacketFields.home, value);
  @override
  Map<String, dynamic> get attributes =>
      _$fleeceCursor.get(_PacketFields.attributes);
  set attributes(Map<String, dynamic> value) =>
      _$fleeceCursor.set(_PacketFields.attributes, value);
  @override
  num get cost => _$fleeceCursor.get(_PacketFields.cost);
  set cost(num value) => _$fleeceCursor.set(_PacketFields.cost, value);
}

extension PacketRecordOperations on PacketRecord {
  Packet toModel() => _$fleeceCursor.read($PacketFleeceFormat.codec);
  fl.$FleeceResult<R> transaction<R>(
    fl.$FleeceResult<R> Function(PacketRecord) edit,
  ) => _$fleeceCursor.transaction<PacketRecord, R>(
    $PacketFleeceFormat.codec.bind,
    edit,
  );
  PacketRecord beginTransaction() =>
      _$fleeceCursor.beginTransaction($PacketFleeceFormat.codec.bind);
  void commit() => _$fleeceCursor.commit();
  void rollback() => _$fleeceCursor.rollback();
  bool get isActive => _$fleeceCursor.isActive;
  typed.Uint8List? get sharedKeyState => _$fleeceCursor.sharedKeyState;
  void dispose() => _$fleeceCursor.dispose();
}

typedef $BranchFleece = BranchRecord;

extension $BranchFleeceFormat on Branch {
  static final codec = fl.FleeceModelCodec<Branch, BranchRecord>(
    _writeBranch,
    _readBranch,
    BranchRecord._,
  );
  typed.Uint8List toFleece({fl.SharedKeys? sharedKeys}) {
    final model = this;
    return model is BranchRecord
        ? model._$fleeceCursor.toBytes(sharedKeys: sharedKeys)
        : codec.encode(model, sharedKeys: sharedKeys);
  }
}

abstract final class _BranchFields {
  static final name = fl.FleeceField<String>("name", fl.FleeceCodecs.string);
  static final child = fl.FleeceField<Branch?>(
    "child",
    $BranchFleeceFormat.codec.nullable(),
    whenMissing: () => null,
  );
}

void _writeBranch(fl.Encoder e, Branch value) {
  if (value is BranchRecord) {
    value._$fleeceCursor.writeTo(e);
    return;
  }
  e.beginDict();
  _BranchFields.child.write(e, value.child);
  _BranchFields.name.write(e, value.name);
  e.endDict();
}

Branch _readBranch(fl.ValueRef ref) {
  final dict = fl.FleeceCodecs.dictionary(ref);
  return Branch(
    _BranchFields.name.read(dict["name"]),
    child: _BranchFields.child.read(dict["child"]),
  );
}

final class BranchRecord implements Branch {
  factory BranchRecord(
    typed.Uint8List bytes, {
    typed.Uint8List? base,
    fl.SharedKeys? sharedKeys,
    fl.FleeceTracking Function()? tracking,
  }) => $BranchFleeceFormat.codec.open(
    bytes,
    base: base,
    sharedKeys: sharedKeys,
    tracking: tracking,
  );
  final fl.FleeceCursor _$fleeceCursor;
  BranchRecord._(this._$fleeceCursor);
  @override
  String get name => _$fleeceCursor.get(_BranchFields.name);
  set name(String value) => _$fleeceCursor.set(_BranchFields.name, value);
  late final _$childCursor = _$fleeceCursor.child(_BranchFields.child);
  @override
  BranchRecord? get child =>
      _$childCursor.optionalObject($BranchFleeceFormat.codec.bind);
  set child(Branch? value) => _$fleeceCursor.set(_BranchFields.child, value);
}

extension BranchRecordOperations on BranchRecord {
  Branch toModel() => _$fleeceCursor.read($BranchFleeceFormat.codec);
  fl.$FleeceResult<R> transaction<R>(
    fl.$FleeceResult<R> Function(BranchRecord) edit,
  ) => _$fleeceCursor.transaction<BranchRecord, R>(
    $BranchFleeceFormat.codec.bind,
    edit,
  );
  BranchRecord beginTransaction() =>
      _$fleeceCursor.beginTransaction($BranchFleeceFormat.codec.bind);
  void commit() => _$fleeceCursor.commit();
  void rollback() => _$fleeceCursor.rollback();
  bool get isActive => _$fleeceCursor.isActive;
  typed.Uint8List? get sharedKeyState => _$fleeceCursor.sharedKeyState;
  void dispose() => _$fleeceCursor.dispose();
}

typedef $DeliveryFleece = Shipment;

extension $DeliveryFleeceFormat on Delivery {
  static final codec = fl.FleeceModelCodec<Delivery, Shipment>(
    _writeDelivery,
    _readDelivery,
    Shipment._,
  );
  typed.Uint8List toFleece({fl.SharedKeys? sharedKeys}) {
    final model = this;
    return model is Shipment
        ? model._$fleeceCursor.toBytes(sharedKeys: sharedKeys)
        : codec.encode(model, sharedKeys: sharedKeys);
  }
}

abstract final class _DeliveryFields {
  static const _initialCity = Delivery._initialCity;
  static final address = fl.FleeceField<notes.Address>(
    "address",
    notes.$AddressFleeceFormat.codec,
    whenMissing:
        ([
          notes.Address value = const notes.Address(
            _initialCity,
            postcode: '69000',
          ),
        ]) => value,
  );
}

void _writeDelivery(fl.Encoder e, Delivery value) {
  if (value is Shipment) {
    value._$fleeceCursor.writeTo(e);
    return;
  }
  e.beginDict();
  _DeliveryFields.address.write(e, value.address);
  e.endDict();
}

Delivery _readDelivery(fl.ValueRef ref) {
  final dict = fl.FleeceCodecs.dictionary(ref);
  return Delivery(address: _DeliveryFields.address.read(dict["address"]));
}

final class Shipment implements Delivery {
  factory Shipment(
    typed.Uint8List bytes, {
    typed.Uint8List? base,
    fl.SharedKeys? sharedKeys,
    fl.FleeceTracking Function()? tracking,
  }) => $DeliveryFleeceFormat.codec.open(
    bytes,
    base: base,
    sharedKeys: sharedKeys,
    tracking: tracking,
  );
  final fl.FleeceCursor _$fleeceCursor;
  Shipment._(this._$fleeceCursor);
  late final _$addressCursor = _$fleeceCursor.child(_DeliveryFields.address);
  @override
  notes.$AddressFleece get address =>
      _$addressCursor.object(notes.$AddressFleeceFormat.codec.bind);
  set address(notes.Address value) =>
      _$fleeceCursor.set(_DeliveryFields.address, value);
}

extension ShipmentOperations on Shipment {
  Delivery toModel() => _$fleeceCursor.read($DeliveryFleeceFormat.codec);
  fl.$FleeceResult<R> transaction<R>(
    fl.$FleeceResult<R> Function(Shipment) edit,
  ) => _$fleeceCursor.transaction<Shipment, R>(
    $DeliveryFleeceFormat.codec.bind,
    edit,
  );
  Shipment beginTransaction() =>
      _$fleeceCursor.beginTransaction($DeliveryFleeceFormat.codec.bind);
  void commit() => _$fleeceCursor.commit();
  void rollback() => _$fleeceCursor.rollback();
  bool get isActive => _$fleeceCursor.isActive;
  typed.Uint8List? get sharedKeyState => _$fleeceCursor.sharedKeyState;
  void dispose() => _$fleeceCursor.dispose();
}

typedef $CounterModelFleece = CounterRecord;

extension $CounterModelFleeceFormat on CounterModel {
  static final codec = fl.FleeceModelCodec<CounterModel, CounterRecord>(
    _writeCounterModel,
    _readCounterModel,
    CounterRecord._,
  );
  typed.Uint8List toFleece({fl.SharedKeys? sharedKeys}) {
    final model = this;
    return model is CounterRecord
        ? model._$fleeceCursor.toBytes(sharedKeys: sharedKeys)
        : codec.encode(model, sharedKeys: sharedKeys);
  }
}

abstract final class _CounterModelFields {
  static final count = fl.FleeceField<int>("count", fl.FleeceCodecs.integer);
}

void _writeCounterModel(fl.Encoder e, CounterModel value) {
  if (value is CounterRecord) {
    value._$fleeceCursor.writeTo(e);
    return;
  }
  e.beginDict();
  _CounterModelFields.count.write(e, value.count);
  e.endDict();
}

CounterModel _readCounterModel(fl.ValueRef ref) {
  final dict = fl.FleeceCodecs.dictionary(ref);
  return CounterModel(_CounterModelFields.count.read(dict["count"]));
}

final class CounterRecord extends CounterModel {
  factory CounterRecord(
    typed.Uint8List bytes, {
    typed.Uint8List? base,
    fl.SharedKeys? sharedKeys,
    fl.FleeceTracking Function()? tracking,
  }) => $CounterModelFleeceFormat.codec.open(
    bytes,
    base: base,
    sharedKeys: sharedKeys,
    tracking: tracking,
  );
  final fl.FleeceCursor _$fleeceCursor;
  CounterRecord._(this._$fleeceCursor)
    : super(_$fleeceCursor.initial(_CounterModelFields.count));
  @override
  int get count => _$fleeceCursor.get(_CounterModelFields.count);
  set count(int value) => _$fleeceCursor.set(_CounterModelFields.count, value);
}

extension CounterRecordOperations on CounterRecord {
  CounterModel toModel() =>
      _$fleeceCursor.read($CounterModelFleeceFormat.codec);
  fl.$FleeceResult<R> transaction<R>(
    fl.$FleeceResult<R> Function(CounterRecord) edit,
  ) => _$fleeceCursor.transaction<CounterRecord, R>(
    $CounterModelFleeceFormat.codec.bind,
    edit,
  );
  CounterRecord beginTransaction() =>
      _$fleeceCursor.beginTransaction($CounterModelFleeceFormat.codec.bind);
  void commit() => _$fleeceCursor.commit();
  void rollback() => _$fleeceCursor.rollback();
  bool get isActive => _$fleeceCursor.isActive;
  typed.Uint8List? get sharedKeyState => _$fleeceCursor.sharedKeyState;
  void dispose() => _$fleeceCursor.dispose();
}

typedef $_MeterModelFleece = MeterRecord;

extension $_MeterModelFleeceFormat on _MeterModel {
  static final codec = fl.FleeceModelCodec<_MeterModel, MeterRecord>(
    _write_MeterModel,
    _read_MeterModel,
    MeterRecord._,
  );
  typed.Uint8List toFleece({fl.SharedKeys? sharedKeys}) {
    final model = this;
    return model is MeterRecord
        ? model._$fleeceCursor.toBytes(sharedKeys: sharedKeys)
        : codec.encode(model, sharedKeys: sharedKeys);
  }
}

abstract final class __MeterModelFields {
  static final tick = fl.FleeceField<int>("tick", fl.FleeceCodecs.integer);
}

void _write_MeterModel(fl.Encoder e, _MeterModel value) {
  if (value is MeterRecord) {
    value._$fleeceCursor.writeTo(e);
    return;
  }
  e.beginDict();
  __MeterModelFields.tick.write(e, value.tick);
  e.endDict();
}

_MeterModel _read_MeterModel(fl.ValueRef ref) {
  final dict = fl.FleeceCodecs.dictionary(ref);
  return _MeterModel(__MeterModelFields.tick.read(dict["tick"]));
}

final class MeterRecord extends _Meter {
  factory MeterRecord(
    typed.Uint8List bytes, {
    typed.Uint8List? base,
    fl.SharedKeys? sharedKeys,
    fl.FleeceTracking Function()? tracking,
  }) => $_MeterModelFleeceFormat.codec.open(
    bytes,
    base: base,
    sharedKeys: sharedKeys,
    tracking: tracking,
  );
  final fl.FleeceCursor _$fleeceCursor;
  MeterRecord._(this._$fleeceCursor)
    : super(_$fleeceCursor.initial(__MeterModelFields.tick));
  @override
  int get tick => _$fleeceCursor.get(__MeterModelFields.tick);
  set tick(int value) => _$fleeceCursor.set(__MeterModelFields.tick, value);
}

extension MeterRecordOperations on MeterRecord {
  _MeterModel toModel() => _$fleeceCursor.read($_MeterModelFleeceFormat.codec);
  fl.$FleeceResult<R> transaction<R>(
    fl.$FleeceResult<R> Function(MeterRecord) edit,
  ) => _$fleeceCursor.transaction<MeterRecord, R>(
    $_MeterModelFleeceFormat.codec.bind,
    edit,
  );
  MeterRecord beginTransaction() =>
      _$fleeceCursor.beginTransaction($_MeterModelFleeceFormat.codec.bind);
  void commit() => _$fleeceCursor.commit();
  void rollback() => _$fleeceCursor.rollback();
  bool get isActive => _$fleeceCursor.isActive;
  typed.Uint8List? get sharedKeyState => _$fleeceCursor.sharedKeyState;
  void dispose() => _$fleeceCursor.dispose();
}
