class ShamellSupportedCurrency {
  final String code;
  final String englishName;
  final String arabicName;

  const ShamellSupportedCurrency({
    required this.code,
    required this.englishName,
    required this.arabicName,
  });
}

const String shamellDefaultWalletCurrency = 'SYP';

// Restricted to SYP-only — the deployed footprint of the app is
// Syria. The server side enforces the same restriction
// (`SUPPORTED_WALLET_CURRENCIES` in payments_service/handlers.rs).
// Re-adding a currency means restoring the entries here AND in the
// server, plus backfilling existing users via the server's
// `ensure_supported_currency_wallets_tx`.
const List<ShamellSupportedCurrency> shamellSupportedWalletCurrencies =
    <ShamellSupportedCurrency>[
  ShamellSupportedCurrency(
    code: 'SYP',
    englishName: 'Syrian Pound',
    arabicName: 'الليرة السورية',
  ),
];

String shamellNormalizeWalletCurrency(String? raw) {
  final normalized = (raw ?? '').trim().toUpperCase();
  if (normalized.isEmpty) return shamellDefaultWalletCurrency;
  return shamellIsSupportedWalletCurrency(normalized)
      ? normalized
      : shamellDefaultWalletCurrency;
}

bool shamellIsSupportedWalletCurrency(String raw) {
  final normalized = raw.trim().toUpperCase();
  return shamellSupportedWalletCurrencies
      .any((currency) => currency.code == normalized);
}

String shamellWalletCurrencyLabel(String code, {required bool isArabic}) {
  final normalized = shamellNormalizeWalletCurrency(code);
  final currency = shamellSupportedWalletCurrencies.firstWhere(
    (item) => item.code == normalized,
    orElse: () => shamellSupportedWalletCurrencies.first,
  );
  final name = isArabic ? currency.arabicName : currency.englishName;
  return '${currency.code} - $name';
}
