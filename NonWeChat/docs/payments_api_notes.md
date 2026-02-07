# Payments API Notes

- **Payment requests accept**: `/payments/requests/{id}/accept` now requires a JSON body `{ "to_wallet_id": <payer_wallet> }`. The accept call validates the wallet matches the original requester, and idempotent retries return the original payer/balance snapshot.
- **Topup vouchers**: Outside `ENV=dev/test`, voucher batches must supply `funding_wallet_id`; the batch upfront-debits that wallet and redeems/voids/expiry release the reserve back. Unfunded batches are rejected in prod/staging.
- **Idempotency metadata**: Idempotent responses for transfers/requests now persist amount/currency/wallet/balance for stable retries.
