bool isValidOfficialOwnerAccountId(String raw) {
  final v = raw.trim();
  return RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(v);
}

bool isValidOfficialOwnerPhoneE164(String raw) {
  final v = raw.trim();
  return RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(v);
}

String normalizeOfficialOwnerAccountId(String raw) => raw.trim().toLowerCase();
