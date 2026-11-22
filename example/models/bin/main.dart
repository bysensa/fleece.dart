import 'package:fleece_model_example/note.dart';
import 'package:fleece_signals/fleece_signals.dart';
import 'package:signals_core/signals_core.dart';

void main() {
  const original = Note(title: 'Field notes', address: Address('Lyon'));
  final bytes = original.toFleece();
  print('Decoded: ${NoteRecord.codec.decode(bytes).title}');
  final note = NoteRecord(bytes, tracking: FleeceSignals.new);
  final stop = effect(() {
    print('${note.address.city}: ${note.visits}');
  });
  note.transaction<void>((draft) {
    draft.address.city = 'Paris';
    draft.tags.addAll(['trip', 'France']);
    draft.visits++;
  });

  final tx = note.beginTransaction();
  tx.visits = 99;
  tx.rollback();
  final Note saved = note.toModel();
  print('Saved: ${saved.address.city}, ${saved.visits}');
  stop();
  note.dispose();
}
