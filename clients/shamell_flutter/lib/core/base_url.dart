// Shared validation helpers for API base URLs.
//
// Security best practice:
// - Never send authentication material over plaintext transports.
// - In release builds, allow `http://` only for explicit localhost.
// - In non-release builds, also allow local-network dev hosts.

import 'package:flutter/foundation.dart';

bool isLocalhostHost(String host) {
  final h = host.trim().toLowerCase();
  return h == 'localhost' || h == '127.0.0.1' || h == '::1';
}

bool _isPrivateIpv4Host(String host) {
  final parts = host.split('.');
  if (parts.length != 4) return false;
  final octets = <int>[];
  for (final part in parts) {
    final n = int.tryParse(part);
    if (n == null || n < 0 || n > 255) return false;
    octets.add(n);
  }
  final a = octets[0];
  final b = octets[1];
  if (a == 10) return true; // 10.0.0.0/8
  if (a == 172 && b >= 16 && b <= 31) return true; // 172.16.0.0/12
  if (a == 192 && b == 168) return true; // 192.168.0.0/16
  if (a == 169 && b == 254) return true; // Link-local
  return false;
}

bool isLocalNetworkHost(String host) {
  final h = host.trim().toLowerCase();
  if (h.isEmpty) return false;
  if (isLocalhostHost(h)) return true;
  if (_isPrivateIpv4Host(h)) return true;
  // Common mDNS hostname pattern on local networks (for example: my-mac.local).
  return h.endsWith('.local');
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
  if (scheme != 'http') return false;
  if (isLocalhostHost(host)) return true;
  if (kReleaseMode) return false;
  return isLocalNetworkHost(host);
}
