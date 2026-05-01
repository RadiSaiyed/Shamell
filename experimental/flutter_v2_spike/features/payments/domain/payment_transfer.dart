class PaymentTransfer {
  final String fromWalletId;
  final String toWalletId;
  final int amountCents;
  final String idempotencyKey;

  const PaymentTransfer({
    required this.fromWalletId,
    required this.toWalletId,
    required this.amountCents,
    this.idempotencyKey = '',
  });
}
