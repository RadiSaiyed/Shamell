import 'dart:math';

final Random _paymentsIdempotencyRandom = Random.secure();
const int _paymentsIdempotencyRandomMax = 0x100000000;

String newPaymentsIdempotencyKey(String prefix) {
  final normalizedPrefix = prefix.trim().isEmpty ? 'pay' : prefix.trim();
  final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final randHi = _paymentsIdempotencyRandom
      .nextInt(_paymentsIdempotencyRandomMax)
      .toRadixString(36)
      .padLeft(7, '0');
  final randLo = _paymentsIdempotencyRandom
      .nextInt(_paymentsIdempotencyRandomMax)
      .toRadixString(36)
      .padLeft(7, '0');
  return '$normalizedPrefix-$ts-$randHi$randLo';
}
