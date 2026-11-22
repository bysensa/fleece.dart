// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'note.dart';

// **************************************************************************
// _Generator
// **************************************************************************

typedef $AddressFleece = AddressRecord;

extension $AddressFleeceFormat on Address {
  static final codec = FleeceModelCodec<Address, AddressRecord>(
    _writeAddress,
    _readAddress,
    AddressRecord._,
  );
  Uint8List toFleece({SharedKeys? sharedKeys}) {
    final model = this;
    return model is AddressRecord
        ? model._$fleeceCursor.toBytes(sharedKeys: sharedKeys)
        : codec.encode(model, sharedKeys: sharedKeys);
  }
}

abstract final class _AddressFields {
  static final city = FleeceField<String>("city", FleeceCodecs.string);
  static final postcode = FleeceField<String?>(
    "postcode",
    FleeceCodecs.string.nullable(),
    whenMissing: () => null,
  );
}

void _writeAddress(Encoder e, Address value) {
  if (value is AddressRecord) {
    value._$fleeceCursor.writeTo(e);
    return;
  }
  e.beginDict();
  _AddressFields.city.write(e, value.city);
  _AddressFields.postcode.write(e, value.postcode);
  e.endDict();
}

Address _readAddress(ValueRef ref) {
  final dict = FleeceCodecs.dictionary(ref);
  return Address(
    _AddressFields.city.read(dict["city"]),
    postcode: _AddressFields.postcode.read(dict["postcode"]),
  );
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
  final FleeceCursor _$fleeceCursor;
  AddressRecord._(this._$fleeceCursor);
  @override
  String get city => _$fleeceCursor.get(_AddressFields.city);
  set city(String value) => _$fleeceCursor.set(_AddressFields.city, value);
  @override
  String? get postcode => _$fleeceCursor.get(_AddressFields.postcode);
  set postcode(String? value) =>
      _$fleeceCursor.set(_AddressFields.postcode, value);
}

extension AddressRecordOperations on AddressRecord {
  Address toModel() => _$fleeceCursor.read($AddressFleeceFormat.codec);
  FutureOr<R> transaction<R>(FutureOr<R> Function(AddressRecord) edit) =>
      _$fleeceCursor.transaction<AddressRecord, R>(
        $AddressFleeceFormat.codec.bind,
        edit,
      );
  AddressRecord beginTransaction() =>
      _$fleeceCursor.beginTransaction($AddressFleeceFormat.codec.bind);
  void commit() => _$fleeceCursor.commit();
  void rollback() => _$fleeceCursor.rollback();
  bool get isActive => _$fleeceCursor.isActive;
  Uint8List? get sharedKeyState => _$fleeceCursor.sharedKeyState;
  void dispose() => _$fleeceCursor.dispose();
}

typedef $NoteFleece = NoteRecord;

extension $NoteFleeceFormat on Note {
  static final codec = FleeceModelCodec<Note, NoteRecord>(
    _writeNote,
    _readNote,
    NoteRecord._,
  );
  Uint8List toFleece({SharedKeys? sharedKeys}) {
    final model = this;
    return model is NoteRecord
        ? model._$fleeceCursor.toBytes(sharedKeys: sharedKeys)
        : codec.encode(model, sharedKeys: sharedKeys);
  }
}

abstract final class _NoteFields {
  static final title = FleeceField<String>(
    "display.title",
    FleeceCodecs.string,
  );
  static final address = FleeceField<Address>(
    "address",
    $AddressFleeceFormat.codec,
  );
  static final visits = FleeceField<int>(
    "visits",
    FleeceCodecs.integer,
    whenMissing: ([int value = 0]) => value,
  );
  static final priority = FleeceField<Priority>(
    "priority",
    FleeceCodecs.enumeration(Priority.values),
    whenMissing: ([Priority value = Priority.normal]) => value,
  );
  static final tags = FleeceField<List<String>>(
    "tags",
    FleeceCodecs.list(FleeceCodecs.string),
    whenMissing: ([List<String> value = const []]) => value,
  );
  static final secondary = FleeceField<Address?>(
    "secondary",
    $AddressFleeceFormat.codec.nullable(),
    whenMissing: () => null,
  );
}

void _writeNote(Encoder e, Note value) {
  if (value is NoteRecord) {
    value._$fleeceCursor.writeTo(e);
    return;
  }
  e.beginDict();
  _NoteFields.address.write(e, value.address);
  _NoteFields.title.write(e, value.title);
  _NoteFields.priority.write(e, value.priority);
  _NoteFields.secondary.write(e, value.secondary);
  _NoteFields.tags.write(e, value.tags);
  _NoteFields.visits.write(e, value.visits);
  e.endDict();
}

Note _readNote(ValueRef ref) {
  final dict = FleeceCodecs.dictionary(ref);
  return Note(
    title: _NoteFields.title.read(dict["display.title"]),
    address: _NoteFields.address.read(dict["address"]),
    visits: _NoteFields.visits.read(dict["visits"]),
    priority: _NoteFields.priority.read(dict["priority"]),
    tags: _NoteFields.tags.read(dict["tags"]),
    secondary: _NoteFields.secondary.read(dict["secondary"]),
  );
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
  final FleeceCursor _$fleeceCursor;
  NoteRecord._(this._$fleeceCursor);
  @override
  String get title => _$fleeceCursor.get(_NoteFields.title);
  set title(String value) => _$fleeceCursor.set(_NoteFields.title, value);
  late final _$addressCursor = _$fleeceCursor.child(_NoteFields.address);
  @override
  AddressRecord get address =>
      _$addressCursor.object($AddressFleeceFormat.codec.bind);
  set address(Address value) => _$fleeceCursor.set(_NoteFields.address, value);
  @override
  int get visits => _$fleeceCursor.get(_NoteFields.visits);
  set visits(int value) => _$fleeceCursor.set(_NoteFields.visits, value);
  @override
  Priority get priority => _$fleeceCursor.get(_NoteFields.priority);
  set priority(Priority value) =>
      _$fleeceCursor.set(_NoteFields.priority, value);
  @override
  List<String> get tags => _$fleeceCursor.get(_NoteFields.tags);
  set tags(List<String> value) => _$fleeceCursor.set(_NoteFields.tags, value);
  late final _$secondaryCursor = _$fleeceCursor.child(_NoteFields.secondary);
  @override
  AddressRecord? get secondary =>
      _$secondaryCursor.optionalObject($AddressFleeceFormat.codec.bind);
  set secondary(Address? value) =>
      _$fleeceCursor.set(_NoteFields.secondary, value);
}

extension NoteRecordOperations on NoteRecord {
  Note toModel() => _$fleeceCursor.read($NoteFleeceFormat.codec);
  FutureOr<R> transaction<R>(FutureOr<R> Function(NoteRecord) edit) =>
      _$fleeceCursor.transaction<NoteRecord, R>(
        $NoteFleeceFormat.codec.bind,
        edit,
      );
  NoteRecord beginTransaction() =>
      _$fleeceCursor.beginTransaction($NoteFleeceFormat.codec.bind);
  void commit() => _$fleeceCursor.commit();
  void rollback() => _$fleeceCursor.rollback();
  bool get isActive => _$fleeceCursor.isActive;
  Uint8List? get sharedKeyState => _$fleeceCursor.sharedKeyState;
  void dispose() => _$fleeceCursor.dispose();
}
