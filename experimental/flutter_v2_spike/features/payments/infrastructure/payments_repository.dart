import '../domain/payment_transfer.dart';

class TransferResult {
  final int newBalanceCents;

  const TransferResult({required this.newBalanceCents});
}

abstract class PaymentsRepository {
  Future<TransferResult> transfer(PaymentTransfer transfer);
  Future<int> loadBalanceCents({required String walletId});
}
