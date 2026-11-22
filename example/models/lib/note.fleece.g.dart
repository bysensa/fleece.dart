// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'note.dart';

// **************************************************************************
// _Generator
// **************************************************************************

typedef $AddressFleece = AddressRecord;

extension $AddressFleeceFormat on Address {
  static final codec = _AddressFields().modelCodec;
  Uint8List toFleece({SharedKeys? sharedKeys}) {
    final model = this;
    return model is AddressRecord
        ? model._$fleeceCursor.toBytes(sharedKeys: sharedKeys)
        : $AddressFleeceFormat.codec.encode(model, sharedKeys: sharedKeys);
  }
}

final class _AddressFields {
  late final modelCodec = FleeceModelCodec<Address, AddressRecord>(
    _write,
    _read,
    (cursor) => AddressRecord._(cursor, this),
  );
  late final field$city = FleeceField<String>("city", FleeceCodecs.string);
  late final field$postcode = FleeceField<String?>(
    "postcode",
    _codec$0,
    whenMissing: () => null,
  );
  void _write(Encoder e, Address value) {
    if (value is AddressRecord) {
      value._$fleeceCursor.writeTo(e);
      return;
    }
    e.beginDict();
    field$city.write(e, value.city);
    field$postcode.write(e, value.postcode);
    e.endDict();
  }

  Address _read(ValueRef ref) {
    final dict = FleeceCodecs.dictionary(ref);
    return Address(
      field$city.read(dict["city"]),
      postcode: field$postcode.read(dict["postcode"]),
    );
  }

  late final _codec$0 = FleeceCodecs.string.nullable();
}

final class AddressRecord implements Address {
  factory AddressRecord(
    Uint8List bytes, {
    Uint8List? base,
    SharedKeys? sharedKeys,
    FleeceTracking Function()? tracking,
  }) => $AddressFleeceFormat.codec.open(
    bytes,
    base: base,
    sharedKeys: sharedKeys,
    tracking: tracking,
  );
  final _AddressFields _$fleeceFields;
  final FleeceCursor _$fleeceCursor;
  static final codec = $AddressFleeceFormat.codec;
  AddressRecord._(this._$fleeceCursor, this._$fleeceFields);
  @override
  String get city => _$fleeceCursor.get(_$fleeceFields.field$city);
  set city(String value) =>
      _$fleeceCursor.set(_$fleeceFields.field$city, value);
  @override
  String? get postcode => _$fleeceCursor.get(_$fleeceFields.field$postcode);
  set postcode(String? value) =>
      _$fleeceCursor.set(_$fleeceFields.field$postcode, value);
}

extension AddressRecordOperations on AddressRecord {
  Address toModel() => _$fleeceCursor.read(_$fleeceFields.modelCodec);
  FutureOr<R> transaction<R>(FutureOr<R> Function(AddressRecord) edit) =>
      _$fleeceCursor.transaction<AddressRecord, R>(
        _$fleeceFields.modelCodec.bind,
        edit,
      );
  AddressRecord beginTransaction() =>
      _$fleeceCursor.beginTransaction(_$fleeceFields.modelCodec.bind);
  void commit() => _$fleeceCursor.commit();
  void rollback() => _$fleeceCursor.rollback();
  bool get isActive => _$fleeceCursor.isActive;
  Uint8List? get sharedKeyState => _$fleeceCursor.sharedKeyState;
  void dispose() => _$fleeceCursor.dispose();
}

typedef $NoteFleece = NoteRecord;

extension $NoteFleeceFormat on Note {
  static final codec = _NoteFields().modelCodec;
  Uint8List toFleece({SharedKeys? sharedKeys}) {
    final model = this;
    return model is NoteRecord
        ? model._$fleeceCursor.toBytes(sharedKeys: sharedKeys)
        : $NoteFleeceFormat.codec.encode(model, sharedKeys: sharedKeys);
  }
}

final class _NoteFields {
  late final modelCodec = FleeceModelCodec<Note, NoteRecord>(
    _write,
    _read,
    (cursor) => NoteRecord._(cursor, this),
  );
  late final field$title = FleeceField<String>(
    "display.title",
    FleeceCodecs.string,
  );
  late final field$address = FleeceField<Address>(
    "address",
    $AddressFleeceFormat.codec,
  );
  AddressRecord bind$address(FleeceCursor cursor) =>
      cursor.object($AddressFleeceFormat.codec.bind);
  late final field$visits = FleeceField<int>(
    "visits",
    FleeceCodecs.integer,
    whenMissing: ([int value = 0]) => value,
  );
  late final field$priority = FleeceField<Priority>(
    "priority",
    _codec$0,
    whenMissing: ([Priority value = Priority.normal]) => value,
  );
  late final field$tags = FleeceField<List<String>>(
    "tags",
    _codec$1,
    whenMissing: ([List<String> value = const []]) => value,
  );
  FleeceList<String, String> bind$tags(FleeceCursor cursor) =>
      cursor.list<String, String>(FleeceCodecs.string);
  late final field$secondary = FleeceField<Address?>(
    "secondary",
    _codec$2,
    whenMissing: () => null,
  );
  AddressRecord? bind$secondary(FleeceCursor cursor) =>
      cursor.optionalObject($AddressFleeceFormat.codec.bind);
  void _write(Encoder e, Note value) {
    if (value is NoteRecord) {
      value._$fleeceCursor.writeTo(e);
      return;
    }
    e.beginDict();
    field$address.write(e, value.address);
    field$title.write(e, value.title);
    field$priority.write(e, value.priority);
    field$secondary.write(e, value.secondary);
    field$tags.write(e, value.tags);
    field$visits.write(e, value.visits);
    e.endDict();
  }

  Note _read(ValueRef ref) {
    final dict = FleeceCodecs.dictionary(ref);
    return Note(
      title: field$title.read(dict["display.title"]),
      address: field$address.read(dict["address"]),
      visits: field$visits.read(dict["visits"]),
      priority: field$priority.read(dict["priority"]),
      tags: field$tags.read(dict["tags"]),
      secondary: field$secondary.read(dict["secondary"]),
    );
  }

  late final _codec$0 = FleeceCodecs.enumeration(Priority.values);
  late final _codec$1 = FleeceCodecs.list(FleeceCodecs.string);
  late final _codec$2 = $AddressFleeceFormat.codec.nullable();
}

final class NoteRecord implements Note {
  factory NoteRecord(
    Uint8List bytes, {
    Uint8List? base,
    SharedKeys? sharedKeys,
    FleeceTracking Function()? tracking,
  }) => $NoteFleeceFormat.codec.open(
    bytes,
    base: base,
    sharedKeys: sharedKeys,
    tracking: tracking,
  );
  final _NoteFields _$fleeceFields;
  final FleeceCursor _$fleeceCursor;
  static final codec = $NoteFleeceFormat.codec;
  NoteRecord._(this._$fleeceCursor, this._$fleeceFields);
  @override
  String get title => _$fleeceCursor.get(_$fleeceFields.field$title);
  set title(String value) =>
      _$fleeceCursor.set(_$fleeceFields.field$title, value);
  late final _$addressCursor = _$fleeceCursor.child(
    _$fleeceFields.field$address,
  );
  @override
  AddressRecord get address => _$fleeceFields.bind$address(_$addressCursor);
  set address(Address value) =>
      _$fleeceCursor.set(_$fleeceFields.field$address, value);
  @override
  int get visits => _$fleeceCursor.get(_$fleeceFields.field$visits);
  set visits(int value) =>
      _$fleeceCursor.set(_$fleeceFields.field$visits, value);
  @override
  Priority get priority => _$fleeceCursor.get(_$fleeceFields.field$priority);
  set priority(Priority value) =>
      _$fleeceCursor.set(_$fleeceFields.field$priority, value);
  late final _$tagsCursor = _$fleeceCursor.child(_$fleeceFields.field$tags);
  @override
  FleeceList<String, String> get tags => _$fleeceFields.bind$tags(_$tagsCursor);
  set tags(List<String> value) =>
      _$fleeceCursor.set(_$fleeceFields.field$tags, value);
  late final _$secondaryCursor = _$fleeceCursor.child(
    _$fleeceFields.field$secondary,
  );
  @override
  AddressRecord? get secondary =>
      _$fleeceFields.bind$secondary(_$secondaryCursor);
  set secondary(Address? value) =>
      _$fleeceCursor.set(_$fleeceFields.field$secondary, value);
}

extension NoteRecordOperations on NoteRecord {
  Note toModel() => _$fleeceCursor.read(_$fleeceFields.modelCodec);
  FutureOr<R> transaction<R>(FutureOr<R> Function(NoteRecord) edit) =>
      _$fleeceCursor.transaction<NoteRecord, R>(
        _$fleeceFields.modelCodec.bind,
        edit,
      );
  NoteRecord beginTransaction() =>
      _$fleeceCursor.beginTransaction(_$fleeceFields.modelCodec.bind);
  void commit() => _$fleeceCursor.commit();
  void rollback() => _$fleeceCursor.rollback();
  bool get isActive => _$fleeceCursor.isActive;
  Uint8List? get sharedKeyState => _$fleeceCursor.sharedKeyState;
  void dispose() => _$fleeceCursor.dispose();
}
