import 'package:fleece/model.dart';
import 'package:signals_core/signals_core.dart';

/// Pass FleeceSignals.new to the generated document constructor.
final class FleeceSignals implements FleeceTracking {
  final _fields = <FleeceDependency, Signal<int>>{};

  @override
  Iterable<FleeceDependency> get fields => _fields.keys;

  @override
  void track(FleeceDependency field) {
    _fields.putIfAbsent(field, () => signal(0)).value;
  }

  @override
  void publish(List<FleeceDependency> changed) {
    batch(() {
      for (final field in changed) {
        final version = _fields[field]!;
        version.value = version.peek() + 1;
      }
    });
  }

  @override
  void dispose() {
    for (final version in _fields.values) {
      version.dispose();
    }
    _fields.clear();
  }
}
