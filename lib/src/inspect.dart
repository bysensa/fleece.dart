part of '../fleece.dart';

String _hexAddress(int pos) => pos.toRadixString(16).padLeft(4, '0');

/// Visits each physical value once; inline collection slots already occupy
/// space in their enclosing value. Both base and appended bytes participate.
extension DocumentSize on Doc {
  int get liveBytes {
    if (_end < 2) return 0;
    var live = 2;
    final seen = <int>{};
    void inside(int pos, int depth, bool pointed) {
      if (pointed && !seen.add(pos)) return;
      final v = valueAt(pos);
      _Header h;
      try {
        h = v._header;
        if (pointed) live += v._size;
      } on FormatException {
        return;
      }
      if (depth > 4 * maxDepth) return;
      if (h.type == ValueType.extended && h.arg != 0) {
        inside(pos + 2, depth + 1, false);
        return;
      }
      if (h.width == 0) return;
      for (var i = 0; i < h.arg * (h.type == ValueType.dict ? 2 : 1); i++) {
        final addr = pos + h.start + i * h.width;
        try {
          final pointer = _isPointer(addr);
          inside(pointer ? _pointerTarget(addr, h.width) : addr, depth + 1,
              pointer);
        } on FormatException {
          continue;
        }
      }
    }

    final end = _end - 2;
    try {
      if (_isPointer(end)) {
        var target = _pointerTarget(end, 2);
        if (_isPointer(target)) {
          live += 4;
          target = _pointerTarget(target, 4);
        }
        inside(target, 0, true);
      }
    } on FormatException {
      return live;
    }
    return live;
  }
}

bool _debugEscaped(int rune) {
  var low = 0, high = _debugEscapeBoundaries.length;
  while (low < high) {
    final mid = (low + high) ~/ 2;
    if (_debugEscapeBoundaries[mid] <= rune) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return low.isOdd;
}

String _debugString(String s) {
  final out = StringBuffer('"');
  for (final r in s.runes) {
    out.write(switch (r) {
      0 => '\\0',
      9 => '\\t',
      10 => '\\n',
      13 => '\\r',
      34 => '\\"',
      92 => '\\\\',
      _ when _debugEscaped(r) => '\\u{' + r.toRadixString(16) + '}',
      _ => String.fromCharCode(r)
    });
  }
  return (out..write('"')).toString();
}

String _debugFloat(double d, bool single) {
  if (d.isNaN) return 'NaN';
  if (d.isInfinite) return d.isNegative ? '-inf' : 'inf';
  if (single && d != 0) {
    for (var p = 1; p <= 9; p++) {
      final n = double.parse(d.toStringAsPrecision(p));
      if (_asF32(n) == d) {
        d = n;
        break;
      }
    }
  }
  return _floatString(d, debug: true);
}

/// Lists physical addresses, pointer targets and inline values in address order.
String dump(Doc doc) {
  final lines = SplayTreeMap<int, String>();
  void slot(int pos, int width, int indent, int depth) {
    if (lines.containsKey(pos) || depth > 4 * maxDepth) return;
    final margin = '  ' * indent;
    try {
      if (doc._isPointer(pos)) {
        int target;
        try {
          target = doc._pointerTarget(pos, width);
        } on FormatException {
          lines[pos] = margin + '&?';
          return;
        }
        lines[pos] = margin + '&' + _hexAddress(target);
        slot(target, 4, doc._isPointer(target) ? indent : 0, depth + 1);
        return;
      }
      final v = doc.valueAt(pos), h = v._header;
      final label = switch (h.type) {
        ValueType.integer => v.asInteger.toString(),
        ValueType.float32 => _debugFloat(v.asDouble!, true) + 'f32',
        ValueType.float64 => _debugFloat(v.asDouble!, false),
        ValueType.boolean => v.asBool.toString(),
        ValueType.nullValue => 'null',
        ValueType.undefined => 'undefined',
        ValueType.string => _debugString(utf8
            .decode(v._contents(h), allowMalformed: true)
            .padBom(v._contents(h))),
        ValueType.data => 'data[' + h.arg.toString() + ']',
        ValueType.extended =>
          'ext ' + (ExtKind.values.elementAtOrNull(h.arg)?.wireName ?? '?'),
        _ => (h.type == ValueType.dict ? 'Dict' : 'Array') +
            '[' +
            h.arg.toString() +
            ']' +
            (h.width == 4 ? ' wide' : ''),
      };
      lines[pos] = margin + label;
      if (h.type == ValueType.extended && h.arg != 0)
        slot(pos + 2, 2, indent + 1, depth + 1);
      if (h.width != 0) {
        for (var i = 0; i < h.arg * (h.type == ValueType.dict ? 2 : 1); i++) {
          slot(pos + h.start + i * h.width, h.width, indent + 1, depth + 1);
        }
      }
    } on FormatException {
      lines[pos] = margin + '?';
    }
  }

  if (doc._end >= 2) slot(doc._end - 2, 2, 0, 0);
  return lines.entries
      .map((e) => _hexAddress(e.key) + ': ' + e.value + '\n')
      .join();
}

extension on String {
  String padBom(Uint8List b) =>
      b.length >= 3 && b[0] == 239 && b[1] == 187 && b[2] == 191
          ? '\ufeff' + this
          : this;
}
