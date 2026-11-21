// Keep offsets as Dart ints on web backends, including JavaScript where
// Int64List element access is unsupported.
typedef SlotBuffer = List<int>;
SlotBuffer allocateSlots(int length) => List<int>.filled(length, 0);
