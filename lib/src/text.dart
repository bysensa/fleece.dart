part of '../fleece.dart';

typedef TextAttributes = Map<String, Object?>;

/// Half-open UTF-8 byte range with the attributes that apply to it.
final class TextMark {
  const TextMark(this.start, this.end, this.attributes);
  final int start, end;
  final TextAttributes attributes;
}

typedef TextRun = (String, TextAttributes?);
typedef _Span = ({int start, int end, int set});

final class _TextBuilder {
  final sets = <TextAttributes>[];
  final spans = <_Span>[];
  final _byHash = <int, List<int>>{};

  int intern(TextAttributes attributes) {
    final candidates = _byHash.putIfAbsent(_valueHash(attributes), () => []);
    for (final i in candidates) {
      if (_equal(sets[i], attributes)) return i;
    }
    final index = sets.length;
    sets.add(Map.unmodifiable(attributes));
    candidates.add(index);
    return index;
  }

  void mark(int start, int end, int set) {
    final last = spans.lastOrNull;
    if (last != null && last.end == start && last.set == set) {
      spans.last = (start: last.start, end: end, set: set);
    } else {
      spans.add((start: start, end: end, set: set));
    }
  }
}

bool _boundary(Uint8List text, int offset) =>
    offset >= 0 &&
    offset <= text.length &&
    (offset == text.length || text[offset] & 0xc0 != 0x80);

Iterable<_Span> _spans(Uint8List text, Uint8List marks, int sets) sync* {
  var offset = 0, after = 0, last = -1;
  int number(int limit) {
    final (value, used) = _readVarint(marks, offset, limit, minimal: true);
    offset += used;
    return value;
  }

  while (offset < marks.length) {
    final gap = number(text.length - after);
    final start = after + gap;
    final length = number(text.length - start);
    final set = number(sets - 1);
    final end = start + length;
    if (length == 0 ||
        gap == 0 && set == last ||
        !_boundary(text, start) ||
        !_boundary(text, end)) {
      throw const FormatException('Invalid Fleece text mark');
    }
    yield (start: start, end: end, set: set);
    after = end;
    last = set;
  }
}

final class FleeceText extends FleeceValue {
  FleeceText._(this.text, this._sets, this._marks);
  FleeceText.plain(this.text)
      : _sets = const [],
        _marks = const [];
  factory FleeceText.fromRuns(Iterable<TextRun> runs) {
    final text = StringBuffer();
    final marks = <TextMark>[];
    var end = 0;
    for (final (s, attributes) in runs) {
      if (s.isEmpty) continue;
      final start = end;
      end += _utf8(s).length;
      text.write(s);
      if (attributes != null && attributes.isNotEmpty)
        marks.add(TextMark(start, end, attributes));
    }
    return FleeceText.withMarks(text.toString(), marks);
  }

  factory FleeceText.withMarks(String text, Iterable<TextMark> marks) {
    final bytes = _utf8(text);
    final builder = _TextBuilder();
    for (final mark in marks) {
      final last = builder.spans.lastOrNull;
      if (mark.attributes.isEmpty ||
          mark.start < (last?.end ?? 0) ||
          mark.start >= mark.end ||
          !_boundary(bytes, mark.start) ||
          !_boundary(bytes, mark.end)) {
        throw ArgumentError(
            'Invalid text mark at byte ' + mark.start.toString());
      }
      builder.mark(mark.start, mark.end, builder.intern(mark.attributes));
    }
    return FleeceText._(text, builder.sets, builder.spans);
  }

  final String text;
  bool get isPlain => _marks.isEmpty;
  final List<TextAttributes> _sets;
  final List<_Span> _marks;
  Iterable<TextMark> get marks =>
      _marks.map((m) => TextMark(m.start, m.end, _sets[m.set]));

  Iterable<TextRun> get runs sync* {
    final bytes = _utf8(text);
    var after = 0;
    for (final mark in marks) {
      if (mark.start > after)
        yield (_string(Uint8List.sublistView(bytes, after, mark.start)), null);
      yield (
        _string(Uint8List.sublistView(bytes, mark.start, mark.end)),
        mark.attributes
      );
      after = mark.end;
    }
    if (after < bytes.length)
      yield (_string(Uint8List.sublistView(bytes, after)), null);
  }

  @override
  ExtKind get kind => ExtKind.text;
  @override
  void _writePayload(Encoder e) {
    e.beginArray();
    e.writeString(text);
    if (_marks.isNotEmpty) {
      // Marks have three minimal varints. Their exact size lets us fill the
      // data body in place, including the length varint preceding it.
      var size = 0, after = 0;
      for (final mark in _marks) {
        size += _varintSize(mark.start - after) +
            _varintSize(mark.end - mark.start) +
            _varintSize(mark.set);
        after = mark.end;
      }
      var at = e._dataSpace(size);
      after = 0;
      for (final mark in _marks) {
        at = e._out.putVarint(at, mark.start - after);
        at = e._out.putVarint(at, mark.end - mark.start);
        at = e._out.putVarint(at, mark.set);
        after = mark.end;
      }
      for (final set in _sets) {
        e.writeValue(set);
      }
    }
    e.endArray();
  }

  @override
  Object get _payload {
    if (_marks.isEmpty) return [text];
    final bytes = BytesBuilder();
    var after = 0;
    for (final mark in _marks) {
      bytes.add(_varint(mark.start - after));
      bytes.add(_varint(mark.end - mark.start));
      bytes.add(_varint(mark.set));
      after = mark.end;
    }
    return [text, bytes.takeBytes(), ..._sets];
  }
}

/// A rich-text value backed by its original UTF-8 and mark buffers.
final class TextRef {
  const TextRef._(this.utf8Bytes, this._marks, this._items);
  final Uint8List utf8Bytes, _marks;
  final ArrayRef _items;
  String get text => _string(utf8Bytes);
  bool get isPlain => _marks.isEmpty;
  Iterable<({int start, int end, DictRef attributes})> get marks sync* {
    try {
      for (final m in _spans(utf8Bytes, _marks, _items.length - 2)) {
        final dict = _items[m.set + 2].asDict;
        if (dict == null) return;
        yield (start: m.start, end: m.end, attributes: dict);
      }
    } on FormatException {
      return;
    }
  }

  Iterable<(String, DictRef?)> get runs sync* {
    String slice(int start, int end) =>
        _string(Uint8List.sublistView(utf8Bytes, start, end));
    var pos = 0;
    for (final m in marks) {
      if (pos < m.start) yield (slice(pos, m.start), null);
      yield (slice(m.start, m.end), m.attributes);
      pos = m.end;
    }
    if (pos < utf8Bytes.length) yield (slice(pos, utf8Bytes.length), null);
  }
}

extension TextReader on ValueRef {
  TextRef? get asText {
    try {
      if (extKind != ExtKind.text) return null;
      final items = payload?.asArray;
      if (items == null || items.isEmpty || items.length == 2) return null;
      final text = items[0].asUtf8;
      if (text == null) return null;
      final marks = items.length == 1 ? Uint8List(0) : items.get(1)?.asData;
      return marks == null || items.length > 1 && marks.isEmpty
          ? null
          : TextRef._(text, marks, items);
    } on FormatException {
      return null;
    }
  }
}
