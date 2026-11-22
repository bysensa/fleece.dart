import 'package:fleece/model.dart';

part 'note.fleece.g.dart';

enum Priority { normal, high }

@FleeceModel()
class Address {
  const Address(this.city, {this.postcode});

  final String city;
  final String? postcode;
}

@FleeceModel()
class Note {
  const Note({
    required this.title,
    required this.address,
    this.visits = 0,
    this.priority = Priority.normal,
    this.tags = const [],
    this.secondary,
  });

  @FleeceKey('display.title')
  final String title;
  final Address address;
  final int visits;
  final Priority priority;
  final List<String> tags;
  final Address? secondary;
}
