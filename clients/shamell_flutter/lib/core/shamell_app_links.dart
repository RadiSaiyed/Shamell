const String shamellAppLinkHost = 'online.shamell.online';
const String shamellAppLinkPathSegment = 'app';
const String shamellAppLinkPathPrefix = '/$shamellAppLinkPathSegment';

const Set<String> shamellSensitiveInboundHosts = <String>{
  'device_login',
  'invite',
  'friend',
};

// Custom-scheme deep links are intentionally not exposed via Android intent
// filters in production. Runtime parsing still supports `shamell://` payloads
// from in-app QR scan flows.
const Set<String> shamellCustomSchemeInboundHosts = <String>{};

bool shamellHostedAppLinkRequiresFragment(String host) {
  return shamellSensitiveInboundHosts.contains(host.trim().toLowerCase());
}

Map<String, String> shamellMergedInboundParams(
  Uri uri, {
  bool includeQueryParameters = true,
}) {
  final out = <String, String>{};
  if (includeQueryParameters) {
    for (final entry in uri.queryParameters.entries) {
      final key = entry.key.trim();
      final value = entry.value.trim();
      if (key.isNotEmpty && value.isNotEmpty) {
        out[key] = value;
      }
    }
  }
  final fragment = uri.fragment.trim();
  if (fragment.isEmpty) {
    return out;
  }
  final raw = fragment.startsWith('?') ? fragment.substring(1) : fragment;
  if (raw.trim().isEmpty) {
    return out;
  }
  try {
    final parsed = Uri.splitQueryString(raw);
    for (final entry in parsed.entries) {
      final key = entry.key.trim();
      final value = entry.value.trim();
      if (key.isNotEmpty && value.isNotEmpty) {
        out[key] = value;
      }
    }
  } catch (_) {}
  return out;
}

Uri buildShamellAppLinkUri(
  String host, {
  List<String> pathSegments = const <String>[],
  Map<String, String>? queryParameters,
}) {
  final normalizedHost = host.trim().toLowerCase();
  final normalizedPathSegments = pathSegments
      .map((segment) => segment.trim())
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
  final normalizedQueryParameters = queryParameters == null
      ? null
      : <String, String>{
          for (final entry in queryParameters.entries)
            if (entry.key.trim().isNotEmpty && entry.value.trim().isNotEmpty)
              entry.key.trim(): entry.value.trim(),
        };
  return Uri(
    scheme: 'https',
    host: shamellAppLinkHost,
    pathSegments: <String>[
      shamellAppLinkPathSegment,
      normalizedHost,
      ...normalizedPathSegments,
    ],
    queryParameters:
        normalizedQueryParameters == null || normalizedQueryParameters.isEmpty
            ? null
            : normalizedQueryParameters,
  );
}

String? _encodedFragmentParams(Map<String, String> params) {
  final normalized = <String, String>{
    for (final entry in params.entries)
      if (entry.key.trim().isNotEmpty && entry.value.trim().isNotEmpty)
        entry.key.trim(): entry.value.trim(),
  };
  if (normalized.isEmpty) {
    return null;
  }
  final encoded = Uri(queryParameters: normalized).query;
  return encoded.trim().isEmpty ? null : encoded;
}

Uri buildShamellInviteAppLink(String token) {
  final uri = buildShamellAppLinkUri('invite');
  final fragment = _encodedFragmentParams(<String, String>{'token': token});
  if (fragment == null) {
    return uri;
  }
  return uri.replace(fragment: fragment);
}

Uri buildShamellDeviceLoginAppLink({
  required String token,
  String? label,
}) {
  final uri = buildShamellAppLinkUri('device_login');
  final fragment = _encodedFragmentParams(<String, String>{
    'token': token,
    if ((label ?? '').trim().isNotEmpty) 'label': label!.trim(),
  });
  if (fragment == null) {
    return uri;
  }
  return uri.replace(fragment: fragment);
}
