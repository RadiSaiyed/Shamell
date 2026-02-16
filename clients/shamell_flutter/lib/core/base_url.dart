// Shared validation helpers for API base URLs.
//
// Security best practice:
// - Never send authentication material over plaintext transports.
// - Allow `http://` only for explicit localhost development.

bool isLocalhostHost(String host) {
  final h = host.trim().toLowerCase();
  return h == 'localhost' || h == '127.0.0.1' || h == '::1';
}

Uri? parseApiBaseUrl(String baseUrl) {
  final raw = baseUrl.trim();
  if (raw.isEmpty) return null;
  final u = Uri.tryParse(raw);
  if (u == null) return null;
  if ((u.host).trim().isEmpty) return null;
  return u;
}

bool isSecureApiBaseUrl(String baseUrl) {
  final u = parseApiBaseUrl(baseUrl);
  if (u == null) return false;
  final scheme = u.scheme.trim().toLowerCase();
  final host = u.host.trim().toLowerCase();
  if (scheme == 'https') return true;
  return scheme == 'http' && isLocalhostHost(host);
}
