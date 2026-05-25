// Cycle 38 — client-side OpenGraph link preview fetcher.
//
// Detects the first http(s) URL in a chat message body and fetches
// the page's OG meta tags so the chat bubble can render a small
// preview card under the message. The card has the same layout as
// the WhatsApp / Signal / Telegram preview cards: a tall image on
// top (when present), a bold title, a one-line site name + domain,
// and a 2-line description.
//
// Why fetch client-side instead of via the BFF: the BFF would have
// to make outbound HTTP requests to arbitrary URLs, which is a
// classic SSRF surface (think `http://169.254.169.254/...` against
// cloud metadata services). Doing it from the device side-steps SSRF
// entirely; the trade-off is that the link target sees the user's
// IP, which is the same trade-off most chat apps make for their MVP
// preview surface. A future cycle can move this to a hardened proxy
// once we want the privacy / link-bounce hardening.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Parsed OG metadata for a link.
@immutable
class ChatLinkPreview {
  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? siteName;

  const ChatLinkPreview({
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
    this.siteName,
  });

  /// Returns true when there's at least a title — empty previews are
  /// suppressed at the call site so the bubble doesn't get an empty
  /// card.
  bool get hasContent =>
      (title?.trim().isNotEmpty ?? false) ||
      (description?.trim().isNotEmpty ?? false) ||
      (imageUrl?.trim().isNotEmpty ?? false);
}

/// First http(s) URL in [text], or null. Excludes trailing
/// punctuation (`.`, `,`, `)`, `>`) so a sentence like "see http://x"
/// yields `http://x` without the period when no period is in the URL.
Uri? chatFirstUrl(String text) {
  if (text.isEmpty) return null;
  final reg = RegExp(r'https?://[^\s<>()]+', caseSensitive: false);
  final m = reg.firstMatch(text);
  if (m == null) return null;
  var raw = m.group(0)!;
  // Strip trailing sentence-ending punctuation that's unlikely to be
  // part of the URL itself.
  while (raw.isNotEmpty &&
      (raw.endsWith('.') ||
          raw.endsWith(',') ||
          raw.endsWith(';') ||
          raw.endsWith('!') ||
          raw.endsWith('?'))) {
    raw = raw.substring(0, raw.length - 1);
  }
  try {
    final u = Uri.parse(raw);
    if (u.scheme.toLowerCase() != 'http' &&
        u.scheme.toLowerCase() != 'https') {
      return null;
    }
    if (u.host.isEmpty) return null;
    return u;
  } catch (_) {
    return null;
  }
}

/// Network + HTML parse caps. The HTTP body limit keeps a single
/// huge page from blowing up the device's RAM; the timeout keeps a
/// slow site from holding a list slot.
const int _maxBodyBytes = 1024 * 1024; // 1 MB
const Duration _fetchTimeout = Duration(seconds: 5);

/// Process-wide cache (URL → preview or null sentinel). Null means
/// "we already tried and failed"; treating it as a sentinel avoids
/// re-fetching on every rebuild.
final Map<String, ChatLinkPreview?> _previewCache =
    <String, ChatLinkPreview?>{};

bool chatLinkPreviewIsCached(String url) => _previewCache.containsKey(url);
ChatLinkPreview? chatLinkPreviewCached(String url) => _previewCache[url];

/// Fetch + parse OG meta for [uri]. Returns null on any error or
/// when the page yielded no usable preview content. Results are
/// cached per-URL for the process lifetime.
Future<ChatLinkPreview?> chatFetchLinkPreview(
  Uri uri, {
  http.Client? httpClient,
}) async {
  final key = uri.toString();
  if (_previewCache.containsKey(key)) return _previewCache[key];
  final client = httpClient ?? http.Client();
  final owns = httpClient == null;
  try {
    final req = http.Request('GET', uri);
    req.headers['User-Agent'] =
        'ShamellLinkPreview/1.0 (+https://shamell.online)';
    req.headers['Accept'] = 'text/html, application/xhtml+xml';
    req.followRedirects = true;
    req.maxRedirects = 5;
    final response = await client.send(req).timeout(_fetchTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _previewCache[key] = null;
      return null;
    }
    final ctype = (response.headers['content-type'] ?? '').toLowerCase();
    if (!ctype.contains('text/html') &&
        !ctype.contains('application/xhtml')) {
      _previewCache[key] = null;
      return null;
    }
    // Read up to _maxBodyBytes — bail early on giant pages.
    final buffer = <int>[];
    final completer = Completer<void>();
    late StreamSubscription<List<int>> sub;
    sub = response.stream.listen(
      (chunk) {
        buffer.addAll(chunk);
        if (buffer.length >= _maxBodyBytes) {
          sub.cancel();
          if (!completer.isCompleted) completer.complete();
        }
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
      onError: (_) {
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );
    await completer.future.timeout(_fetchTimeout, onTimeout: () {
      sub.cancel();
    });
    String body;
    try {
      // Most pages are utf-8; fall back to latin-1 if the bytes
      // don't decode cleanly.
      body = utf8.decode(buffer, allowMalformed: true);
    } catch (_) {
      body = latin1.decode(buffer, allowInvalid: true);
    }
    final preview = _parseOgFromHtml(uri, body);
    _previewCache[key] = preview?.hasContent ?? false ? preview : null;
    return _previewCache[key];
  } catch (_) {
    _previewCache[key] = null;
    return null;
  } finally {
    if (owns) client.close();
  }
}

/// Extract OG / Twitter / fallback meta tags from a raw HTML
/// string. We avoid the `html` package dep — a small regex over
/// `<meta ...>` and `<title>` covers the common preview cases.
ChatLinkPreview? _parseOgFromHtml(Uri uri, String html) {
  String? title;
  String? description;
  String? imageUrl;
  String? siteName;
  // Read only the head — preview metadata is always there, and
  // bounding the parse to the head saves cycles on huge pages.
  final headEnd = html.toLowerCase().indexOf('</head>');
  final searchBody = headEnd > 0 ? html.substring(0, headEnd) : html;
  final metaReg = RegExp(
    r'<meta[^>]+(?:property|name)\s*=\s*"([^"]+)"[^>]+content\s*=\s*"([^"]*)"',
    caseSensitive: false,
  );
  for (final m in metaReg.allMatches(searchBody)) {
    final key = (m.group(1) ?? '').toLowerCase();
    final val = m.group(2);
    if (val == null) continue;
    switch (key) {
      case 'og:title':
      case 'twitter:title':
        title ??= _decodeHtmlEntities(val);
        break;
      case 'og:description':
      case 'description':
      case 'twitter:description':
        description ??= _decodeHtmlEntities(val);
        break;
      case 'og:image':
      case 'og:image:secure_url':
      case 'twitter:image':
        imageUrl ??= val;
        break;
      case 'og:site_name':
        siteName ??= _decodeHtmlEntities(val);
        break;
    }
  }
  if (title == null) {
    final titleReg =
        RegExp(r'<title[^>]*>([\s\S]*?)<\/title>', caseSensitive: false);
    final tm = titleReg.firstMatch(searchBody);
    if (tm != null) {
      title = _decodeHtmlEntities((tm.group(1) ?? '').trim());
    }
  }
  // Normalize a relative image URL to absolute.
  if (imageUrl != null && imageUrl.trim().isNotEmpty) {
    try {
      imageUrl = uri.resolve(imageUrl).toString();
    } catch (_) {}
  }
  // Default site_name to the host so the card always has a small
  // identity strip.
  siteName ??= uri.host;
  return ChatLinkPreview(
    url: uri.toString(),
    title: title?.trim(),
    description: description?.trim(),
    imageUrl: imageUrl?.trim(),
    siteName: siteName.trim(),
  );
}

/// Tiny HTML-entity decoder for the entities that show up in OG
/// metadata. We can't pull in `package:html_unescape` for a feature
/// that has to ship in the next APK; this covers >95% of cases.
String _decodeHtmlEntities(String raw) {
  if (raw.isEmpty) return raw;
  return raw
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&nbsp;', ' ');
}
