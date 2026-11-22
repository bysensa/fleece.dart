import 'package:fleece/model.dart';
import 'package:signals_core/signals_core.dart';

/// Pass FleeceSignals.new to the generated document constructor.
final class FleeceSignals implements FleeceTracking {
  var _signals = Expando<_FieldSignal>();
  final _live = <WeakReference<_FieldSignal>>{};
  late final _cleanup = Finalizer<WeakReference<_FieldSignal>>(_live.remove);

  @override
  Iterable<FleeceDependency> get fields sync* {
    for (final entry in _live) {
      final signal = entry.target;
      if (signal != null) yield signal.field;
    }
  }

  @override
  void track(FleeceDependency field) {
    var signal = _signals[field];
    if (signal == null) {
      _signals[field] = signal = _FieldSignal(field);
      final entry = WeakReference(signal);
      _live.add(entry);
      _cleanup.attach(signal, entry);
    }
    signal.value;
  }

  @override
  void publish(List<FleeceDependency> changed) {
    batch(() {
      for (final field in changed) {
        final version = _signals[field]!;
        version.value = version.peek() + 1;
      }
    });
  }

  @override
  void dispose() {
    for (final entry in _live) {
      entry.target?.dispose();
    }
    _live.clear();
    _signals = Expando();
  }
}

// Computed values can retain their dependencies even without active listeners.
// Their signal keeps the corresponding cursor alive for exactly that lifetime.
final class _FieldSignal extends Signal<int> {
  _FieldSignal(this.field) : super(0);
  final FleeceDependency field;
}
