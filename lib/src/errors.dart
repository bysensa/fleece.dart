part of '../fleece.dart';

enum DecodeErrorCode {
  truncated,
  malformed,
  badPointer,
  invalidUtf8,
  unknownExt,
  badPayload,
  badKey,
  unsortedKeys,
  missingSharedKey,
  undefined,
  tooDeep,
  tooManyValues,
  tooManyBytes
}

final class DecodeError extends FormatException {
  const DecodeError(this.code, String message,
      {int? position, this.kind, this.key})
      : super(message, null, position);
  final DecodeErrorCode code;
  final int? kind;

  /// A signed i64. JavaScript uses BigInt outside its safe integer range.
  final Object? key;
  int? get position => offset;
}

enum EncodeErrorCode {
  expectedKey,
  unexpectedKey,
  unbalanced,
  multipleRoots,
  incomplete,
  extPayload,
  badExtKind,
  duplicateKey,
  tooDeep,
  tooLarge,
  notInBase,
  badBase,
  invalidValue
}

abstract interface class EncodeError implements Exception {
  EncodeErrorCode get code;
  Object? get detail;
}

final class _EncoderState extends StateError implements EncodeError {
  _EncoderState(this.code, String message, [this.detail]) : super(message);
  @override
  final EncodeErrorCode code;
  @override
  final Object? detail;
}

final class _EncoderArgument extends ArgumentError implements EncodeError {
  _EncoderArgument(this.code, String message, [this.detail]) : super(message);
  @override
  final EncodeErrorCode code;
  @override
  final Object? detail;
}
