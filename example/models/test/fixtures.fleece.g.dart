// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'fixtures.dart';

// **************************************************************************
// _Generator
// **************************************************************************

typedef $PacketFleece = PacketRecord;

extension $PacketFleeceFormat on Packet {
  static final codec = _PacketFields().modelCodec;
  typed.Uint8List toFleece({fl.SharedKeys? sharedKeys}) {
    final model = this;
    return model is PacketRecord
        ? model._$fleeceCursor.toBytes(sharedKeys: sharedKeys)
        : $PacketFleeceFormat.codec.encode(model, sharedKeys: sharedKeys);
  }
}

final class _PacketFields {
  late final modelCodec = fl.FleeceModelCodec<Packet, PacketRecord>(
    _write,
    _read,
    (cursor) => PacketRecord._(cursor, this),
  );
  late final field$bytes = fl.FleeceField<typed.Uint8List>(
    "\$bytes[0]",
    fl.FleeceCodecs.bytes,
  );
  late final field$id = fl.FleeceField<fl.FleeceUuid>("id", _codec$0);
  late final field$timestamp = fl.FleeceField<DateTime>(
    "timestamp",
    fl.FleeceCodecs.dateTime,
  );
  late final field$sequence = fl.FleeceField<BigInt>(
    "sequence",
    fl.FleeceCodecs.bigInteger,
  );
  late final field$weight = fl.FleeceField<double>(
    "weight",
    fl.FleeceCodecs.floating,
    whenMissing: ([double value = 1.0]) => value,
  );
  late final field$enabled = fl.FleeceField<bool>(
    "enabled",
    fl.FleeceCodecs.boolean,
    whenMissing: ([bool value = true]) => value,
  );
  late final field$destinations =
      fl.FleeceField<Map<String, List<notes.Address?>>>(
        "destinations",
        _codec$3,
        whenMissing: ([Map<String, List<notes.Address?>> value = const {}]) =>
            value,
      );
  fl.FleeceMap<
    List<notes.Address?>,
    fl.FleeceList<notes.Address?, notes.$AddressFleece?>
  >
  bind$destinations(fl.FleeceCursor cursor) =>
      cursor.map<
        List<notes.Address?>,
        fl.FleeceList<notes.Address?, notes.$AddressFleece?>
      >(
        _codec$2,
        (item0) => item0.list<notes.Address?, notes.$AddressFleece?>(
          _codec$1,
          (item1) =>
              item1.optionalObject(notes.$AddressFleeceFormat.codec.bind),
        ),
      );
  late final field$precise = fl.FleeceField<fl.FleeceFloat64?>(
    "precise",
    _codec$4,
    whenMissing: () => null,
  );
  late final field$small = fl.FleeceField<fl.FleeceFloat32?>(
    "small",
    _codec$5,
    whenMissing: () => null,
  );
  late final field$home = fl.FleeceField<notes.Address?>(
    "home",
    _codec$1,
    whenMissing: () => null,
  );
  notes.$AddressFleece? bind$home(fl.FleeceCursor cursor) =>
      cursor.optionalObject(notes.$AddressFleeceFormat.codec.bind);
  late final field$attributes = fl.FleeceField<Map<String, dynamic>>(
    "attributes",
    _codec$6,
    whenMissing: ([Map<String, dynamic> value = const {}]) => value,
  );
  fl.FleeceMap<dynamic, dynamic> bind$attributes(fl.FleeceCursor cursor) =>
      cursor.map<dynamic, dynamic>(fl.FleeceCodecs.value);
  late final field$cost = fl.FleeceField<num>(
    "cost",
    fl.FleeceCodecs.number,
    whenMissing: ([num value = 0]) => value,
  );
  void _write(fl.Encoder e, Packet value) {
    if (value is PacketRecord) {
      value._$fleeceCursor.writeTo(e);
      return;
    }
    e.beginDict();
    field$bytes.write(e, value.bytes);
    field$attributes.write(e, value.attributes);
    field$cost.write(e, value.cost);
    field$destinations.write(e, value.destinations);
    field$enabled.write(e, value.enabled);
    field$home.write(e, value.home);
    field$id.write(e, value.id);
    field$precise.write(e, value.precise);
    field$sequence.write(e, value.sequence);
    field$small.write(e, value.small);
    field$timestamp.write(e, value.timestamp);
    field$weight.write(e, value.weight);
    e.endDict();
  }

  Packet _read(fl.ValueRef ref) {
    final dict = fl.FleeceCodecs.dictionary(ref);
    return Packet(
      field$bytes.read(dict["\$bytes[0]"]),
      field$id.read(dict["id"]),
      field$timestamp.read(dict["timestamp"]),
      sequence: field$sequence.read(dict["sequence"]),
      weight: field$weight.read(dict["weight"]),
      enabled: field$enabled.read(dict["enabled"]),
      destinations: field$destinations.read(dict["destinations"]),
      precise: field$precise.read(dict["precise"]),
      small: field$small.read(dict["small"]),
      home: field$home.read(dict["home"]),
      attributes: field$attributes.read(dict["attributes"]),
      cost: field$cost.read(dict["cost"]),
    );
  }

  late final _codec$0 = fl.FleeceCodecs.native<fl.FleeceUuid>();
  late final _codec$1 = notes.$AddressFleeceFormat.codec.nullable();
  late final _codec$2 = fl.FleeceCodecs.list(_codec$1);
  late final _codec$3 = fl.FleeceCodecs.map(_codec$2);
  late final _codec$4 = fl.FleeceCodecs.float64.nullable();
  late final _codec$5 = fl.FleeceCodecs.float32.nullable();
  late final _codec$6 = fl.FleeceCodecs.map(fl.FleeceCodecs.value);
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
  final _PacketFields _$fleeceFields;
  final fl.FleeceCursor _$fleeceCursor;
  static final codec = $PacketFleeceFormat.codec;
  PacketRecord._(this._$fleeceCursor, this._$fleeceFields);
  @override
  typed.Uint8List get bytes => _$fleeceCursor.get(_$fleeceFields.field$bytes);
  set bytes(typed.Uint8List value) =>
      _$fleeceCursor.set(_$fleeceFields.field$bytes, value);
  @override
  fl.FleeceUuid get id => _$fleeceCursor.get(_$fleeceFields.field$id);
  set id(fl.FleeceUuid value) =>
      _$fleeceCursor.set(_$fleeceFields.field$id, value);
  @override
  DateTime get timestamp => _$fleeceCursor.get(_$fleeceFields.field$timestamp);
  set timestamp(DateTime value) =>
      _$fleeceCursor.set(_$fleeceFields.field$timestamp, value);
  @override
  BigInt get sequence => _$fleeceCursor.get(_$fleeceFields.field$sequence);
  set sequence(BigInt value) =>
      _$fleeceCursor.set(_$fleeceFields.field$sequence, value);
  @override
  double get weight => _$fleeceCursor.get(_$fleeceFields.field$weight);
  set weight(double value) =>
      _$fleeceCursor.set(_$fleeceFields.field$weight, value);
  @override
  bool get enabled => _$fleeceCursor.get(_$fleeceFields.field$enabled);
  set enabled(bool value) =>
      _$fleeceCursor.set(_$fleeceFields.field$enabled, value);
  late final _$destinationsCursor = _$fleeceCursor.child(
    _$fleeceFields.field$destinations,
  );
  @override
  fl.FleeceMap<
    List<notes.Address?>,
    fl.FleeceList<notes.Address?, notes.$AddressFleece?>
  >
  get destinations => _$fleeceFields.bind$destinations(_$destinationsCursor);
  set destinations(Map<String, List<notes.Address?>> value) =>
      _$fleeceCursor.set(_$fleeceFields.field$destinations, value);
  @override
  fl.FleeceFloat64? get precise =>
      _$fleeceCursor.get(_$fleeceFields.field$precise);
  set precise(fl.FleeceFloat64? value) =>
      _$fleeceCursor.set(_$fleeceFields.field$precise, value);
  @override
  fl.FleeceFloat32? get small => _$fleeceCursor.get(_$fleeceFields.field$small);
  set small(fl.FleeceFloat32? value) =>
      _$fleeceCursor.set(_$fleeceFields.field$small, value);
  late final _$homeCursor = _$fleeceCursor.child(_$fleeceFields.field$home);
  @override
  notes.$AddressFleece? get home => _$fleeceFields.bind$home(_$homeCursor);
  set home(notes.Address? value) =>
      _$fleeceCursor.set(_$fleeceFields.field$home, value);
  late final _$attributesCursor = _$fleeceCursor.child(
    _$fleeceFields.field$attributes,
  );
  @override
  fl.FleeceMap<dynamic, dynamic> get attributes =>
      _$fleeceFields.bind$attributes(_$attributesCursor);
  set attributes(Map<String, dynamic> value) =>
      _$fleeceCursor.set(_$fleeceFields.field$attributes, value);
  @override
  num get cost => _$fleeceCursor.get(_$fleeceFields.field$cost);
  set cost(num value) => _$fleeceCursor.set(_$fleeceFields.field$cost, value);
}

extension PacketRecordOperations on PacketRecord {
  Packet toModel() => _$fleeceCursor.read(_$fleeceFields.modelCodec);
  fl.$FleeceResult<R> transaction<R>(
    fl.$FleeceResult<R> Function(PacketRecord) edit,
  ) => _$fleeceCursor.transaction<PacketRecord, R>(
    _$fleeceFields.modelCodec.bind,
    edit,
  );
  PacketRecord beginTransaction() =>
      _$fleeceCursor.beginTransaction(_$fleeceFields.modelCodec.bind);
  void commit() => _$fleeceCursor.commit();
  void rollback() => _$fleeceCursor.rollback();
  bool get isActive => _$fleeceCursor.isActive;
  typed.Uint8List? get sharedKeyState => _$fleeceCursor.sharedKeyState;
  void dispose() => _$fleeceCursor.dispose();
}

typedef $BranchFleece = BranchRecord;

extension $BranchFleeceFormat on Branch {
  static final codec = _BranchFields().modelCodec;
  typed.Uint8List toFleece({fl.SharedKeys? sharedKeys}) {
    final model = this;
    return model is BranchRecord
        ? model._$fleeceCursor.toBytes(sharedKeys: sharedKeys)
        : $BranchFleeceFormat.codec.encode(model, sharedKeys: sharedKeys);
  }
}

final class _BranchFields {
  late final modelCodec = fl.FleeceModelCodec<Branch, BranchRecord>(
    _write,
    _read,
    (cursor) => BranchRecord._(cursor, this),
  );
  late final field$name = fl.FleeceField<String>(
    "name",
    fl.FleeceCodecs.string,
  );
  late final field$child = fl.FleeceField<Branch?>(
    "child",
    _codec$0,
    whenMissing: () => null,
  );
  BranchRecord? bind$child(fl.FleeceCursor cursor) =>
      cursor.optionalObject($BranchFleeceFormat.codec.bind);
  void _write(fl.Encoder e, Branch value) {
    if (value is BranchRecord) {
      value._$fleeceCursor.writeTo(e);
      return;
    }
    e.beginDict();
    field$child.write(e, value.child);
    field$name.write(e, value.name);
    e.endDict();
  }

  Branch _read(fl.ValueRef ref) {
    final dict = fl.FleeceCodecs.dictionary(ref);
    return Branch(
      field$name.read(dict["name"]),
      child: field$child.read(dict["child"]),
    );
  }

  late final _codec$0 = $BranchFleeceFormat.codec.nullable();
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
  final _BranchFields _$fleeceFields;
  final fl.FleeceCursor _$fleeceCursor;
  static final codec = $BranchFleeceFormat.codec;
  BranchRecord._(this._$fleeceCursor, this._$fleeceFields);
  @override
  String get name => _$fleeceCursor.get(_$fleeceFields.field$name);
  set name(String value) =>
      _$fleeceCursor.set(_$fleeceFields.field$name, value);
  late final _$childCursor = _$fleeceCursor.child(_$fleeceFields.field$child);
  @override
  BranchRecord? get child => _$fleeceFields.bind$child(_$childCursor);
  set child(Branch? value) =>
      _$fleeceCursor.set(_$fleeceFields.field$child, value);
}

extension BranchRecordOperations on BranchRecord {
  Branch toModel() => _$fleeceCursor.read(_$fleeceFields.modelCodec);
  fl.$FleeceResult<R> transaction<R>(
    fl.$FleeceResult<R> Function(BranchRecord) edit,
  ) => _$fleeceCursor.transaction<BranchRecord, R>(
    _$fleeceFields.modelCodec.bind,
    edit,
  );
  BranchRecord beginTransaction() =>
      _$fleeceCursor.beginTransaction(_$fleeceFields.modelCodec.bind);
  void commit() => _$fleeceCursor.commit();
  void rollback() => _$fleeceCursor.rollback();
  bool get isActive => _$fleeceCursor.isActive;
  typed.Uint8List? get sharedKeyState => _$fleeceCursor.sharedKeyState;
  void dispose() => _$fleeceCursor.dispose();
}

typedef $DeliveryFleece = Shipment;

extension $DeliveryFleeceFormat on Delivery {
  static final codec = _DeliveryFields().modelCodec;
  typed.Uint8List toFleece({fl.SharedKeys? sharedKeys}) {
    final model = this;
    return model is Shipment
        ? model._$fleeceCursor.toBytes(sharedKeys: sharedKeys)
        : $DeliveryFleeceFormat.codec.encode(model, sharedKeys: sharedKeys);
  }
}

final class _DeliveryFields {
  late final modelCodec = fl.FleeceModelCodec<Delivery, Shipment>(
    _write,
    _read,
    (cursor) => Shipment._(cursor, this),
  );
  static const _initialCity = Delivery._initialCity;
  late final field$address = fl.FleeceField<notes.Address>(
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
  notes.$AddressFleece bind$address(fl.FleeceCursor cursor) =>
      cursor.object(notes.$AddressFleeceFormat.codec.bind);
  void _write(fl.Encoder e, Delivery value) {
    if (value is Shipment) {
      value._$fleeceCursor.writeTo(e);
      return;
    }
    e.beginDict();
    field$address.write(e, value.address);
    e.endDict();
  }

  Delivery _read(fl.ValueRef ref) {
    final dict = fl.FleeceCodecs.dictionary(ref);
    return Delivery(address: field$address.read(dict["address"]));
  }
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
  final _DeliveryFields _$fleeceFields;
  final fl.FleeceCursor _$fleeceCursor;
  static final codec = $DeliveryFleeceFormat.codec;
  Shipment._(this._$fleeceCursor, this._$fleeceFields);
  late final _$addressCursor = _$fleeceCursor.child(
    _$fleeceFields.field$address,
  );
  @override
  notes.$AddressFleece get address =>
      _$fleeceFields.bind$address(_$addressCursor);
  set address(notes.Address value) =>
      _$fleeceCursor.set(_$fleeceFields.field$address, value);
}

extension ShipmentOperations on Shipment {
  Delivery toModel() => _$fleeceCursor.read(_$fleeceFields.modelCodec);
  fl.$FleeceResult<R> transaction<R>(
    fl.$FleeceResult<R> Function(Shipment) edit,
  ) => _$fleeceCursor.transaction<Shipment, R>(
    _$fleeceFields.modelCodec.bind,
    edit,
  );
  Shipment beginTransaction() =>
      _$fleeceCursor.beginTransaction(_$fleeceFields.modelCodec.bind);
  void commit() => _$fleeceCursor.commit();
  void rollback() => _$fleeceCursor.rollback();
  bool get isActive => _$fleeceCursor.isActive;
  typed.Uint8List? get sharedKeyState => _$fleeceCursor.sharedKeyState;
  void dispose() => _$fleeceCursor.dispose();
}

typedef $CounterModelFleece = CounterRecord;

extension $CounterModelFleeceFormat on CounterModel {
  static final codec = _CounterModelFields().modelCodec;
  typed.Uint8List toFleece({fl.SharedKeys? sharedKeys}) {
    final model = this;
    return model is CounterRecord
        ? model._$fleeceCursor.toBytes(sharedKeys: sharedKeys)
        : $CounterModelFleeceFormat.codec.encode(model, sharedKeys: sharedKeys);
  }
}

final class _CounterModelFields {
  late final modelCodec = fl.FleeceModelCodec<CounterModel, CounterRecord>(
    _write,
    _read,
    (cursor) => CounterRecord._(cursor, this),
  );
  late final field$count = fl.FleeceField<int>(
    "count",
    fl.FleeceCodecs.integer,
  );
  void _write(fl.Encoder e, CounterModel value) {
    if (value is CounterRecord) {
      value._$fleeceCursor.writeTo(e);
      return;
    }
    e.beginDict();
    field$count.write(e, value.count);
    e.endDict();
  }

  CounterModel _read(fl.ValueRef ref) {
    final dict = fl.FleeceCodecs.dictionary(ref);
    return CounterModel(field$count.read(dict["count"]));
  }
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
  final _CounterModelFields _$fleeceFields;
  final fl.FleeceCursor _$fleeceCursor;
  static final codec = $CounterModelFleeceFormat.codec;
  CounterRecord._(this._$fleeceCursor, this._$fleeceFields)
    : super(_$fleeceCursor.initial(_$fleeceFields.field$count));
  @override
  int get count => _$fleeceCursor.get(_$fleeceFields.field$count);
  set count(int value) => _$fleeceCursor.set(_$fleeceFields.field$count, value);
}

extension CounterRecordOperations on CounterRecord {
  CounterModel toModel() => _$fleeceCursor.read(_$fleeceFields.modelCodec);
  fl.$FleeceResult<R> transaction<R>(
    fl.$FleeceResult<R> Function(CounterRecord) edit,
  ) => _$fleeceCursor.transaction<CounterRecord, R>(
    _$fleeceFields.modelCodec.bind,
    edit,
  );
  CounterRecord beginTransaction() =>
      _$fleeceCursor.beginTransaction(_$fleeceFields.modelCodec.bind);
  void commit() => _$fleeceCursor.commit();
  void rollback() => _$fleeceCursor.rollback();
  bool get isActive => _$fleeceCursor.isActive;
  typed.Uint8List? get sharedKeyState => _$fleeceCursor.sharedKeyState;
  void dispose() => _$fleeceCursor.dispose();
}

typedef $_MeterModelFleece = MeterRecord;

extension $_MeterModelFleeceFormat on _MeterModel {
  static final codec = __MeterModelFields().modelCodec;
  typed.Uint8List toFleece({fl.SharedKeys? sharedKeys}) {
    final model = this;
    return model is MeterRecord
        ? model._$fleeceCursor.toBytes(sharedKeys: sharedKeys)
        : $_MeterModelFleeceFormat.codec.encode(model, sharedKeys: sharedKeys);
  }
}

final class __MeterModelFields {
  late final modelCodec = fl.FleeceModelCodec<_MeterModel, MeterRecord>(
    _write,
    _read,
    (cursor) => MeterRecord._(cursor, this),
  );
  late final field$tick = fl.FleeceField<int>("tick", fl.FleeceCodecs.integer);
  void _write(fl.Encoder e, _MeterModel value) {
    if (value is MeterRecord) {
      value._$fleeceCursor.writeTo(e);
      return;
    }
    e.beginDict();
    field$tick.write(e, value.tick);
    e.endDict();
  }

  _MeterModel _read(fl.ValueRef ref) {
    final dict = fl.FleeceCodecs.dictionary(ref);
    return _MeterModel(field$tick.read(dict["tick"]));
  }
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
  final __MeterModelFields _$fleeceFields;
  final fl.FleeceCursor _$fleeceCursor;
  static final codec = $_MeterModelFleeceFormat.codec;
  MeterRecord._(this._$fleeceCursor, this._$fleeceFields)
    : super(_$fleeceCursor.initial(_$fleeceFields.field$tick));
  @override
  int get tick => _$fleeceCursor.get(_$fleeceFields.field$tick);
  set tick(int value) => _$fleeceCursor.set(_$fleeceFields.field$tick, value);
}

extension MeterRecordOperations on MeterRecord {
  _MeterModel toModel() => _$fleeceCursor.read(_$fleeceFields.modelCodec);
  fl.$FleeceResult<R> transaction<R>(
    fl.$FleeceResult<R> Function(MeterRecord) edit,
  ) => _$fleeceCursor.transaction<MeterRecord, R>(
    _$fleeceFields.modelCodec.bind,
    edit,
  );
  MeterRecord beginTransaction() =>
      _$fleeceCursor.beginTransaction(_$fleeceFields.modelCodec.bind);
  void commit() => _$fleeceCursor.commit();
  void rollback() => _$fleeceCursor.rollback();
  bool get isActive => _$fleeceCursor.isActive;
  typed.Uint8List? get sharedKeyState => _$fleeceCursor.sharedKeyState;
  void dispose() => _$fleeceCursor.dispose();
}

typedef $EnvelopeFleece<T> = EnvelopeRecord<T>;

extension $EnvelopeFleeceFormat<T> on Envelope<T> {
  static fl.FleeceModelCodec<Envelope<T>, EnvelopeRecord<T>> codec<T>({
    required fl.FleeceCodec<T> codecT,
  }) => _EnvelopeFields<T>(codecT: codecT).modelCodec;
  typed.Uint8List toFleece({
    required fl.FleeceCodec<T> codecT,
    fl.SharedKeys? sharedKeys,
  }) {
    final model = this;
    return model is EnvelopeRecord<T> && model._$fleeceFields._uses(codecT)
        ? model._$fleeceCursor.toBytes(sharedKeys: sharedKeys)
        : $EnvelopeFleeceFormat
              .codec<T>(codecT: codecT)
              .encode(model, sharedKeys: sharedKeys);
  }
}

final class _EnvelopeFields<T> {
  final fl.FleeceCodec<T> codecT;
  _EnvelopeFields({required this.codecT});
  bool _uses(fl.FleeceCodec<T> otherT) => identical(codecT, otherT);
  late final modelCodec = fl.FleeceModelCodec<Envelope<T>, EnvelopeRecord<T>>(
    _write,
    _read,
    (cursor) => EnvelopeRecord<T>._(cursor, this),
  );
  late final field$value = fl.FleeceField<T>("value", codecT);
  T bind$value(fl.FleeceCursor cursor) => codecT.bindValue(cursor);
  late final field$history = fl.FleeceField<List<T?>>(
    "history",
    _codec$1,
    whenMissing: ([List<T?> value = const []]) => value,
  );
  fl.FleeceList<T?, T?> bind$history(fl.FleeceCursor cursor) =>
      cursor.list<T?, T?>(_codec$0, (item0) => _codec$0.bindValue(item0));
  late final field$links = fl.FleeceField<Map<String, List<Uri?>>>(
    "links",
    _codec$4,
    whenMissing: ([Map<String, List<Uri?>> value = const {}]) => value,
  );
  fl.FleeceMap<List<Uri?>, fl.FleeceList<Uri?, Uri?>> bind$links(
    fl.FleeceCursor cursor,
  ) => cursor.map<List<Uri?>, fl.FleeceList<Uri?, Uri?>>(
    _codec$3,
    (item0) => item0.list<Uri?, Uri?>(_codec$2),
  );
  void _write(fl.Encoder e, Envelope<T> value) {
    if (value is EnvelopeRecord<T>) {
      final source = value._$fleeceFields;
      if (!source._uses(codecT)) {
        value._$fleeceCursor.writeTo(
          e,
          writeField: (key) {
            switch (key) {
              case "value":
                field$value.codec.write(e, value.value);
                return true;
              case "history":
                field$history.codec.write(e, value.history);
                return true;
              default:
                return false;
            }
          },
        );
        return;
      }
      value._$fleeceCursor.writeTo(e);
      return;
    }
    e.beginDict();
    field$history.write(e, value.history);
    field$links.write(e, value.links);
    field$value.write(e, value.value);
    e.endDict();
  }

  Envelope<T> _read(fl.ValueRef ref) {
    final dict = fl.FleeceCodecs.dictionary(ref);
    return Envelope<T>.stored(
      field$value.read(dict["value"]),
      history: field$history.read(dict["history"]),
      links: field$links.read(dict["links"]),
    );
  }

  late final _codec$0 = codecT.nullable();
  late final _codec$1 = fl.FleeceCodecs.list(_codec$0);
  late final _codec$2 = UriCodec().nullable();
  late final _codec$3 = fl.FleeceCodecs.list(_codec$2);
  late final _codec$4 = fl.FleeceCodecs.map(_codec$3);
}

final class EnvelopeRecord<T> implements Envelope<T> {
  factory EnvelopeRecord(
    typed.Uint8List bytes, {
    required fl.FleeceCodec<T> codecT,
    typed.Uint8List? base,
    fl.SharedKeys? sharedKeys,
    fl.FleeceTracking Function()? tracking,
  }) => $EnvelopeFleeceFormat
      .codec<T>(codecT: codecT)
      .open(bytes, base: base, sharedKeys: sharedKeys, tracking: tracking);
  final _EnvelopeFields<T> _$fleeceFields;
  final fl.FleeceCursor _$fleeceCursor;
  static fl.FleeceModelCodec<Envelope<T>, EnvelopeRecord<T>> codec<T>({
    required fl.FleeceCodec<T> codecT,
  }) => $EnvelopeFleeceFormat.codec<T>(codecT: codecT);
  EnvelopeRecord._(this._$fleeceCursor, this._$fleeceFields);
  late final _$valueCursor = _$fleeceCursor.child(_$fleeceFields.field$value);
  @override
  T get value => _$fleeceFields.bind$value(_$valueCursor);
  set value(T value) => _$fleeceCursor.set(_$fleeceFields.field$value, value);
  late final _$historyCursor = _$fleeceCursor.child(
    _$fleeceFields.field$history,
  );
  @override
  fl.FleeceList<T?, T?> get history =>
      _$fleeceFields.bind$history(_$historyCursor);
  set history(List<T?> value) =>
      _$fleeceCursor.set(_$fleeceFields.field$history, value);
  late final _$linksCursor = _$fleeceCursor.child(_$fleeceFields.field$links);
  @override
  fl.FleeceMap<List<Uri?>, fl.FleeceList<Uri?, Uri?>> get links =>
      _$fleeceFields.bind$links(_$linksCursor);
  set links(Map<String, List<Uri?>> value) =>
      _$fleeceCursor.set(_$fleeceFields.field$links, value);
}

extension EnvelopeRecordOperations<T> on EnvelopeRecord<T> {
  Envelope<T> toModel() => _$fleeceCursor.read(_$fleeceFields.modelCodec);
  typed.Uint8List toFleece({
    fl.FleeceCodec<T>? codecT,
    fl.SharedKeys? sharedKeys,
  }) => $EnvelopeFleeceFormat<T>(
    this,
  ).toFleece(codecT: codecT ?? _$fleeceFields.codecT, sharedKeys: sharedKeys);
  fl.$FleeceResult<R> transaction<R>(
    fl.$FleeceResult<R> Function(EnvelopeRecord<T>) edit,
  ) => _$fleeceCursor.transaction<EnvelopeRecord<T>, R>(
    _$fleeceFields.modelCodec.bind,
    edit,
  );
  EnvelopeRecord<T> beginTransaction() =>
      _$fleeceCursor.beginTransaction(_$fleeceFields.modelCodec.bind);
  void commit() => _$fleeceCursor.commit();
  void rollback() => _$fleeceCursor.rollback();
  bool get isActive => _$fleeceCursor.isActive;
  typed.Uint8List? get sharedKeyState => _$fleeceCursor.sharedKeyState;
  void dispose() => _$fleeceCursor.dispose();
}

typedef $LedgerFleece<R extends num> = LedgerRecord<R>;

extension $LedgerFleeceFormat<R extends num> on Ledger<R> {
  static fl.FleeceModelCodec<Ledger<R>, LedgerRecord<R>> codec<R extends num>({
    required fl.FleeceCodec<R> codecR,
  }) => _LedgerFields<R>(codecR: codecR).modelCodec;
  typed.Uint8List toFleece({
    required fl.FleeceCodec<R> codecR,
    fl.SharedKeys? sharedKeys,
  }) {
    final model = this;
    return model is LedgerRecord<R> && model._$fleeceFields._uses(codecR)
        ? model._$fleeceCursor.toBytes(sharedKeys: sharedKeys)
        : $LedgerFleeceFormat
              .codec<R>(codecR: codecR)
              .encode(model, sharedKeys: sharedKeys);
  }
}

final class _LedgerFields<R extends num> {
  final fl.FleeceCodec<R> codecR;
  _LedgerFields({required this.codecR});
  bool _uses(fl.FleeceCodec<R> otherR) => identical(codecR, otherR);
  late final modelCodec = fl.FleeceModelCodec<Ledger<R>, LedgerRecord<R>>(
    _write,
    _read,
    (cursor) => LedgerRecord<R>._(cursor, this),
  );
  late final field$envelope = fl.FleeceField<Envelope<notes.Address>>(
    "envelope",
    _codec$0,
  );
  EnvelopeRecord<notes.Address> bind$envelope(fl.FleeceCursor cursor) =>
      cursor.object(_codec$0.bind);
  late final field$amount = fl.FleeceField<R>("amount", codecR);
  R bind$amount(fl.FleeceCursor cursor) => codecR.bindValue(cursor);
  void _write(fl.Encoder e, Ledger<R> value) {
    if (value is LedgerRecord<R>) {
      final source = value._$fleeceFields;
      if (!source._uses(codecR)) {
        value._$fleeceCursor.writeTo(
          e,
          writeField: (key) {
            switch (key) {
              case "amount":
                field$amount.codec.write(e, value.amount);
                return true;
              default:
                return false;
            }
          },
        );
        return;
      }
      value._$fleeceCursor.writeTo(e);
      return;
    }
    e.beginDict();
    field$amount.write(e, value.amount);
    field$envelope.write(e, value.envelope);
    e.endDict();
  }

  Ledger<R> _read(fl.ValueRef ref) {
    final dict = fl.FleeceCodecs.dictionary(ref);
    return Ledger<R>(
      field$envelope.read(dict["envelope"]),
      field$amount.read(dict["amount"]),
    );
  }

  late final _codec$0 = $EnvelopeFleeceFormat.codec<notes.Address>(
    codecT: notes.$AddressFleeceFormat.codec,
  );
}

final class LedgerRecord<R extends num> extends Ledger<R> {
  factory LedgerRecord(
    typed.Uint8List bytes, {
    required fl.FleeceCodec<R> codecR,
    typed.Uint8List? base,
    fl.SharedKeys? sharedKeys,
    fl.FleeceTracking Function()? tracking,
  }) => $LedgerFleeceFormat
      .codec<R>(codecR: codecR)
      .open(bytes, base: base, sharedKeys: sharedKeys, tracking: tracking);
  final _LedgerFields<R> _$fleeceFields;
  final fl.FleeceCursor _$fleeceCursor;
  static fl.FleeceModelCodec<Ledger<R>, LedgerRecord<R>> codec<R extends num>({
    required fl.FleeceCodec<R> codecR,
  }) => $LedgerFleeceFormat.codec<R>(codecR: codecR);
  LedgerRecord._(this._$fleeceCursor, this._$fleeceFields)
    : super(
        _$fleeceCursor.initial(_$fleeceFields.field$envelope),
        _$fleeceCursor.initial(_$fleeceFields.field$amount),
      );
  late final _$envelopeCursor = _$fleeceCursor.child(
    _$fleeceFields.field$envelope,
  );
  @override
  EnvelopeRecord<notes.Address> get envelope =>
      _$fleeceFields.bind$envelope(_$envelopeCursor);
  set envelope(Envelope<notes.Address> value) =>
      _$fleeceCursor.set(_$fleeceFields.field$envelope, value);
  late final _$amountCursor = _$fleeceCursor.child(_$fleeceFields.field$amount);
  @override
  R get amount => _$fleeceFields.bind$amount(_$amountCursor);
  set amount(R value) => _$fleeceCursor.set(_$fleeceFields.field$amount, value);
}

extension LedgerRecordOperations<R extends num> on LedgerRecord<R> {
  Ledger<R> toModel() => _$fleeceCursor.read(_$fleeceFields.modelCodec);
  typed.Uint8List toFleece({
    fl.FleeceCodec<R>? codecR,
    fl.SharedKeys? sharedKeys,
  }) => $LedgerFleeceFormat<R>(
    this,
  ).toFleece(codecR: codecR ?? _$fleeceFields.codecR, sharedKeys: sharedKeys);
  fl.$FleeceResult<RResult> transaction<RResult>(
    fl.$FleeceResult<RResult> Function(LedgerRecord<R>) edit,
  ) => _$fleeceCursor.transaction<LedgerRecord<R>, RResult>(
    _$fleeceFields.modelCodec.bind,
    edit,
  );
  LedgerRecord<R> beginTransaction() =>
      _$fleeceCursor.beginTransaction(_$fleeceFields.modelCodec.bind);
  void commit() => _$fleeceCursor.commit();
  void rollback() => _$fleeceCursor.rollback();
  bool get isActive => _$fleeceCursor.isActive;
  typed.Uint8List? get sharedKeyState => _$fleeceCursor.sharedKeyState;
  void dispose() => _$fleeceCursor.dispose();
}

typedef $InitializedModelFleece = InitializedRecord;

extension $InitializedModelFleeceFormat on InitializedModel {
  static final codec = _InitializedModelFields().modelCodec;
  typed.Uint8List toFleece({fl.SharedKeys? sharedKeys}) {
    final model = this;
    return model is InitializedRecord
        ? model._$fleeceCursor.toBytes(sharedKeys: sharedKeys)
        : $InitializedModelFleeceFormat.codec.encode(
            model,
            sharedKeys: sharedKeys,
          );
  }
}

final class _InitializedModelFields {
  late final modelCodec =
      fl.FleeceModelCodec<InitializedModel, InitializedRecord>(
        _write,
        _read,
        (cursor) => InitializedRecord._(cursor, this),
      );
  late final field$tags = fl.FleeceField<List<String>>("tags", _codec$0);
  fl.FleeceList<String, String> bind$tags(fl.FleeceCursor cursor) =>
      cursor.list<String, String>(fl.FleeceCodecs.string);
  void _write(fl.Encoder e, InitializedModel value) {
    if (value is InitializedRecord) {
      value._$fleeceCursor.writeTo(e);
      return;
    }
    e.beginDict();
    field$tags.write(e, value.tags);
    e.endDict();
  }

  InitializedModel _read(fl.ValueRef ref) {
    final dict = fl.FleeceCodecs.dictionary(ref);
    return InitializedModel(field$tags.read(dict["tags"]));
  }

  late final _codec$0 = fl.FleeceCodecs.list(fl.FleeceCodecs.string);
}

final class InitializedRecord extends InitializedModel {
  factory InitializedRecord(
    typed.Uint8List bytes, {
    typed.Uint8List? base,
    fl.SharedKeys? sharedKeys,
    fl.FleeceTracking Function()? tracking,
  }) => $InitializedModelFleeceFormat.codec.open(
    bytes,
    base: base,
    sharedKeys: sharedKeys,
    tracking: tracking,
  );
  final _InitializedModelFields _$fleeceFields;
  final fl.FleeceCursor _$fleeceCursor;
  static final codec = $InitializedModelFleeceFormat.codec;
  InitializedRecord._(this._$fleeceCursor, this._$fleeceFields)
    : super(_$fleeceCursor.initial(_$fleeceFields.field$tags));
  late final _$tagsCursor = _$fleeceCursor.child(_$fleeceFields.field$tags);
  @override
  fl.FleeceList<String, String> get tags =>
      _$fleeceFields.bind$tags(_$tagsCursor);
  set tags(List<String> value) =>
      _$fleeceCursor.set(_$fleeceFields.field$tags, value);
}

extension InitializedRecordOperations on InitializedRecord {
  InitializedModel toModel() => _$fleeceCursor.read(_$fleeceFields.modelCodec);
  fl.$FleeceResult<R> transaction<R>(
    fl.$FleeceResult<R> Function(InitializedRecord) edit,
  ) => _$fleeceCursor.transaction<InitializedRecord, R>(
    _$fleeceFields.modelCodec.bind,
    edit,
  );
  InitializedRecord beginTransaction() =>
      _$fleeceCursor.beginTransaction(_$fleeceFields.modelCodec.bind);
  void commit() => _$fleeceCursor.commit();
  void rollback() => _$fleeceCursor.rollback();
  bool get isActive => _$fleeceCursor.isActive;
  typed.Uint8List? get sharedKeyState => _$fleeceCursor.sharedKeyState;
  void dispose() => _$fleeceCursor.dispose();
}

typedef $GaugeModelFleece = GaugeRecord;

extension $GaugeModelFleeceFormat on GaugeModel {
  static final codec = _GaugeModelFields().modelCodec;
  typed.Uint8List toFleece({fl.SharedKeys? sharedKeys}) {
    final model = this;
    return model is GaugeRecord
        ? model._$fleeceCursor.toBytes(sharedKeys: sharedKeys)
        : $GaugeModelFleeceFormat.codec.encode(model, sharedKeys: sharedKeys);
  }
}

final class _GaugeModelFields {
  late final modelCodec = fl.FleeceModelCodec<GaugeModel, GaugeRecord>(
    _write,
    _read,
    (cursor) => GaugeRecord._(cursor, this),
  );
  late final field$level = fl.FleeceField<int>(
    "level",
    fl.FleeceCodecs.integer,
  );
  late final field$adjustments = fl.FleeceField<int>(
    "adjustments",
    fl.FleeceCodecs.integer,
    whenMissing: ([int value = 0]) => value,
  );
  void _write(fl.Encoder e, GaugeModel value) {
    if (value is GaugeRecord) {
      value._$fleeceCursor.writeTo(e);
      return;
    }
    e.beginDict();
    field$adjustments.write(e, value.adjustments);
    field$level.write(e, value.level);
    e.endDict();
  }

  GaugeModel _read(fl.ValueRef ref) {
    final dict = fl.FleeceCodecs.dictionary(ref);
    return GaugeModel(
      field$level.read(dict["level"]),
      adjustments: field$adjustments.read(dict["adjustments"]),
    );
  }
}

final class GaugeRecord extends GaugeModel {
  factory GaugeRecord(
    typed.Uint8List bytes, {
    typed.Uint8List? base,
    fl.SharedKeys? sharedKeys,
    fl.FleeceTracking Function()? tracking,
  }) => $GaugeModelFleeceFormat.codec.open(
    bytes,
    base: base,
    sharedKeys: sharedKeys,
    tracking: tracking,
  );
  final _GaugeModelFields _$fleeceFields;
  final fl.FleeceCursor _$fleeceCursor;
  static final codec = $GaugeModelFleeceFormat.codec;
  GaugeRecord._(this._$fleeceCursor, this._$fleeceFields)
    : super(
        _$fleeceCursor.initial(_$fleeceFields.field$level),
        adjustments: _$fleeceCursor.initial(_$fleeceFields.field$adjustments),
      );
  @override
  int get level => _$fleeceCursor.get(_$fleeceFields.field$level);
  set level(int value) => _$fleeceCursor.applySetter<GaugeModel>(
    _$fleeceFields.modelCodec,
    (model) => model.level = value,
  );
  @override
  int get adjustments => _$fleeceCursor.get(_$fleeceFields.field$adjustments);
  set adjustments(int value) =>
      _$fleeceCursor.set(_$fleeceFields.field$adjustments, value);
}

extension GaugeRecordOperations on GaugeRecord {
  GaugeModel toModel() => _$fleeceCursor.read(_$fleeceFields.modelCodec);
  fl.$FleeceResult<R> transaction<R>(
    fl.$FleeceResult<R> Function(GaugeRecord) edit,
  ) => _$fleeceCursor.transaction<GaugeRecord, R>(
    _$fleeceFields.modelCodec.bind,
    edit,
  );
  GaugeRecord beginTransaction() =>
      _$fleeceCursor.beginTransaction(_$fleeceFields.modelCodec.bind);
  void commit() => _$fleeceCursor.commit();
  void rollback() => _$fleeceCursor.rollback();
  bool get isActive => _$fleeceCursor.isActive;
  typed.Uint8List? get sharedKeyState => _$fleeceCursor.sharedKeyState;
  void dispose() => _$fleeceCursor.dispose();
}
