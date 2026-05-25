import 'dart:convert';

import 'package:flutter/foundation.dart';

class Base64BytesCache {
  Base64BytesCache({this.maxEntries = 128});

  final int maxEntries;
  final Map<String, Uint8List?> _entries = <String, Uint8List?>{};

  Uint8List? decode(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    if (_entries.containsKey(value)) {
      final cached = _entries.remove(value);
      _entries[value] = cached;
      return cached;
    }

    Uint8List? decoded;
    try {
      decoded = base64Decode(value);
    } catch (_) {
      decoded = null;
    }

    if (_entries.length >= maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    _entries[value] = decoded;
    return decoded;
  }

  void clear() => _entries.clear();

  @visibleForTesting
  int get size => _entries.length;
}
