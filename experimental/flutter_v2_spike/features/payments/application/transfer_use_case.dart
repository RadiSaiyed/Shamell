import '../domain/payment_transfer.dart';
import '../infrastructure/payments_repository.dart';

class TransferUseCase {
  final PaymentsRepository repository;

  TransferUseCase({required this.repository});

  Future<TransferResult> run(PaymentTransfer transfer) {
    return repository.transfer(transfer);
  }

  Future<int> loadBalanceCents({required String walletId}) {
    return repository.loadBalanceCents(walletId: walletId);
  }
}
