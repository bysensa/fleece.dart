import 'dart:typed_data';

// Keep absolute positions even when a value is near the end of a large base.
// The concrete buffer type lets AOT inline element loads and stores.
typedef SlotBuffer = Int64List;
SlotBuffer allocateSlots(int length) => Int64List(length);
