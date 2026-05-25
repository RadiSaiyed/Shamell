import 'dart:convert';

const String _envCallIceServersJson = String.fromEnvironment(
  'SHAMELL_CALL_ICE_SERVERS_JSON',
  defaultValue: '',
);

const String _envCallStunUrls = String.fromEnvironment(
  'SHAMELL_CALL_STUN_URLS',
  defaultValue: 'stun:stun.l.google.com:19302',
);

const String _envCallTurnUrls = String.fromEnvironment(
  'SHAMELL_CALL_TURN_URLS',
  defaultValue: '',
);

const String _envCallTurnUsername = String.fromEnvironment(
  'SHAMELL_CALL_TURN_USERNAME',
  defaultValue: '',
);

const String _envCallTurnCredential = String.fromEnvironment(
  'SHAMELL_CALL_TURN_CREDENTIAL',
  defaultValue: '',
);

bool _isValidIceUrl(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized.startsWith('stun:') ||
      normalized.startsWith('turn:') ||
      normalized.startsWith('turns:');
}

List<String> _splitIceUrls(String raw) {
  final normalized = raw.replaceAll(';', ',');
  final out = <String>[];
  for (final part in normalized.split(',')) {
    final trimmed = part.trim();
    if (trimmed.isEmpty || !_isValidIceUrl(trimmed)) {
      continue;
    }
    out.add(trimmed);
  }
  return out;
}

List<String> _urlsFromDynamic(Object? value) {
  if (value is String) {
    return _splitIceUrls(value);
  }
  if (value is List) {
    final out = <String>[];
    for (final entry in value) {
      if (entry is! String) {
        continue;
      }
      final trimmed = entry.trim();
      if (trimmed.isEmpty || !_isValidIceUrl(trimmed)) {
        continue;
      }
      out.add(trimmed);
    }
    return out;
  }
  return const <String>[];
}

List<Map<String, dynamic>> _serversFromJson(String raw) {
  if (raw.trim().isEmpty) {
    return const <Map<String, dynamic>>[];
  }
  final decoded = jsonDecode(raw);
  if (decoded is! List) {
    return const <Map<String, dynamic>>[];
  }
  final out = <Map<String, dynamic>>[];
  for (final entry in decoded) {
    if (entry is! Map) {
      continue;
    }
    final urls = _urlsFromDynamic(entry['urls']);
    if (urls.isEmpty) {
      continue;
    }
    final server = <String, dynamic>{'urls': urls};
    final username = (entry['username'] ?? '').toString().trim();
    if (username.isNotEmpty) {
      server['username'] = username;
    }
    final credential = (entry['credential'] ?? '').toString().trim();
    if (credential.isNotEmpty) {
      server['credential'] = credential;
    }
    out.add(server);
  }
  return out;
}

List<Map<String, dynamic>> shamellCallIceServers({
  String? rawIceServersJson,
  String? rawStunUrls,
  String? rawTurnUrls,
  String? rawTurnUsername,
  String? rawTurnCredential,
}) {
  final jsonRaw = (rawIceServersJson ?? _envCallIceServersJson).trim();
  if (jsonRaw.isNotEmpty) {
    try {
      final parsed = _serversFromJson(jsonRaw);
      if (parsed.isNotEmpty) {
        return parsed;
      }
    } catch (_) {
      // Fall back to explicit STUN/TURN env vars.
    }
  }

  final stunUrls = _splitIceUrls((rawStunUrls ?? _envCallStunUrls).trim());
  final turnUrls = _splitIceUrls((rawTurnUrls ?? _envCallTurnUrls).trim());
  final turnUsername = (rawTurnUsername ?? _envCallTurnUsername).trim();
  final turnCredential = (rawTurnCredential ?? _envCallTurnCredential).trim();

  final out = <Map<String, dynamic>>[];
  if (stunUrls.isNotEmpty) {
    out.add(<String, dynamic>{'urls': stunUrls});
  }
  if (turnUrls.isNotEmpty &&
      turnUsername.isNotEmpty &&
      turnCredential.isNotEmpty) {
    out.add(<String, dynamic>{
      'urls': turnUrls,
      'username': turnUsername,
      'credential': turnCredential,
    });
  }

  if (out.isNotEmpty) {
    return out;
  }
  return const <Map<String, dynamic>>[
    <String, dynamic>{
      'urls': <String>['stun:stun.l.google.com:19302'],
    }
  ];
}

Map<String, dynamic> shamellCallPeerConnectionConfig({
  String? rawIceServersJson,
  String? rawStunUrls,
  String? rawTurnUrls,
  String? rawTurnUsername,
  String? rawTurnCredential,
}) {
  return <String, dynamic>{
    'iceServers': shamellCallIceServers(
      rawIceServersJson: rawIceServersJson,
      rawStunUrls: rawStunUrls,
      rawTurnUrls: rawTurnUrls,
      rawTurnUsername: rawTurnUsername,
      rawTurnCredential: rawTurnCredential,
    ),
  };
}
