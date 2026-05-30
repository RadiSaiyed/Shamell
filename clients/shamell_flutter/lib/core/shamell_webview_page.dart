import 'dart:async';
import 'package:shamell_flutter/core/session_cookie_store.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'l10n.dart';
import 'shamell_ui.dart';

class ShamellWebViewPage extends StatefulWidget {
  final Uri initialUri;
  final Uri? baseUri;
  final String? initialTitle;
  final bool injectSessionForSameOrigin;
  final bool restrictToBaseOrigin;

  const ShamellWebViewPage({
    super.key,
    required this.initialUri,
    this.baseUri,
    this.initialTitle,
    this.injectSessionForSameOrigin = true,
    this.restrictToBaseOrigin = true,
  });

  @override
  State<ShamellWebViewPage> createState() => _ShamellWebViewPageState();
}

class _ShamellWebViewPageState extends State<ShamellWebViewPage> {
  WebViewController? _controller;
  Uri? _currentUri;
  String _title = '';
  double _progress = 0;
  bool _loading = true;

  bool _isLocalhostHost(String host) {
    final h = host.trim().toLowerCase();
    return h == 'localhost' || h == '127.0.0.1' || h == '::1';
  }

  bool _allowWebViewSessionBridge(Uri baseUri) {
    // webview_flutter cannot set HttpOnly/Secure flags on cookies, so bridging a
    // native session into a JS-enabled WebView is unsafe. Allow only for local
    // dev to unblock localhost tooling.
    if (kReleaseMode) return false;
    return _isLocalhostHost(baseUri.host);
  }

  void _showBlockedSnack(String message) {
    if (!mounted) return;
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _title = (widget.initialTitle ?? '').trim();
    unawaited(_initWebView());
  }

  Future<void> _initWebView() async {
    final baseUri = widget.baseUri;
    Uri targetUri = widget.initialUri;
    if (baseUri != null && targetUri.scheme.isEmpty) {
      try {
        targetUri = baseUri.resolveUri(targetUri);
      } catch (_) {}
    }
    if (baseUri != null &&
        widget.injectSessionForSameOrigin &&
        _allowWebViewSessionBridge(baseUri)) {
      targetUri = await _maybeWireSession(
        targetUri,
        baseUri: baseUri,
      );
    }

    final controller = WebViewController();
    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(ShamellPalette.background)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (!mounted) return;
            setState(() {
              _progress = (p.clamp(0, 100)) / 100.0;
              _loading = _progress < 1;
            });
          },
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() {
              _loading = true;
              _progress = 0;
              _currentUri = Uri.tryParse(url);
            });
          },
          onPageFinished: (url) async {
            final uri = Uri.tryParse(url);
            String? title;
            try {
              title = await controller.getTitle();
            } catch (_) {}
            if (!mounted) return;
            setState(() {
              _currentUri = uri;
              if (title != null && title.trim().isNotEmpty) {
                _title = title.trim();
              } else if (_title.isEmpty && uri != null) {
                _title = uri.host;
              }
              _progress = 1;
              _loading = false;
            });
          },
          onNavigationRequest: (request) async {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.navigate;
            final scheme = uri.scheme.toLowerCase();
            if (scheme == 'http' || scheme == 'https') {
              // Best practice: block plaintext HTTP except localhost.
              if (scheme == 'http' && !_isLocalhostHost(uri.host)) {
                _showBlockedSnack('Blocked insecure http:// navigation.');
                return NavigationDecision.prevent;
              }
              // Best practice: keep embedded WebViews same-origin to reduce
              // phishing surface and cross-site navigation surprises.
              final base = widget.baseUri;
              if (widget.restrictToBaseOrigin &&
                  base != null &&
                  !_isSameOrigin(uri, base)) {
                try {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } catch (_) {}
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            }
            try {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } catch (_) {}
            return NavigationDecision.prevent;
          },
        ),
      );

    if (!mounted) return;
    setState(() {
      _controller = controller;
      _currentUri = targetUri;
    });
    try {
      await controller.loadRequest(targetUri);
    } catch (_) {}
  }

  Future<String?> _getSessionTokenForBase(Uri baseUri) async {
    try {
      return await getSessionTokenForBaseUrl(baseUri.toString());
    } catch (_) {
      return null;
    }
  }

  bool _isSameOrigin(Uri a, Uri b) {
    if (a.scheme.toLowerCase() != b.scheme.toLowerCase()) return false;
    if (a.host.toLowerCase() != b.host.toLowerCase()) return false;
    int portA = a.hasPort ? a.port : 0;
    int portB = b.hasPort ? b.port : 0;
    if (portA == 0) {
      portA = a.scheme.toLowerCase() == 'https' ? 443 : 80;
    }
    if (portB == 0) {
      portB = b.scheme.toLowerCase() == 'https' ? 443 : 80;
    }
    return portA == portB;
  }

  Future<void> _setWebViewSessionCookie({
    required Uri baseUri,
    required String sessionToken,
  }) async {
    try {
      final cookieManager = WebViewCookieManager();
      // Prefer the hardened session cookie name. Keep a legacy cookie in
      // dev/test webviews as a best-effort fallback.
      await cookieManager.setCookie(
        WebViewCookie(
          name: '__Host-sa_session',
          value: sessionToken,
          domain: baseUri.host,
          path: '/',
        ),
      );
      await cookieManager.setCookie(
        WebViewCookie(
          name: 'sa_session',
          value: sessionToken,
          domain: baseUri.host,
          path: '/',
        ),
      );
    } catch (_) {}
  }

  Future<Uri> _maybeWireSession(
    Uri uri, {
    required Uri baseUri,
  }) async {
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return uri;
    if (!_isSameOrigin(uri, baseUri)) return uri;
    try {
      final token = await _getSessionTokenForBase(baseUri);
      if (token == null || token.isEmpty) return uri;
      await _setWebViewSessionCookie(baseUri: baseUri, sessionToken: token);
      return uri;
    } catch (_) {
      return uri;
    }
  }

  Future<bool> _handleBack() async {
    final controller = _controller;
    if (controller == null) return true;
    try {
      final canGoBack = await controller.canGoBack();
      if (canGoBack) {
        await controller.goBack();
        return false;
      }
    } catch (_) {}
    return true;
  }

  void _showMenu() {
    final controller = _controller;
    final current = _currentUri;
    final l = L10n.of(context);
    final isArabic = l.isArabic;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.dividerColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.refresh),
                  title: Text(isArabic ? 'تحديث' : 'Refresh'),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    try {
                      await controller?.reload();
                    } catch (_) {}
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.link),
                  title: Text(isArabic ? 'نسخ الرابط' : 'Copy link'),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final url = current?.toString() ?? '';
                    if (url.isEmpty) return;
                    try {
                      await Clipboard.setData(ClipboardData(text: url));
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            isArabic ? 'تم نسخ الرابط' : 'Link copied',
                          ),
                        ),
                      );
                    } catch (_) {}
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.ios_share),
                  title: Text(isArabic ? 'مشاركة' : 'Share'),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final url = current?.toString() ?? '';
                    if (url.isEmpty) return;
                    try {
                      await Share.share(url);
                    } catch (_) {}
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.open_in_browser),
                  title: Text(isArabic ? 'فتح في المتصفح' : 'Open in browser'),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final url = current;
                    if (url == null) return;
                    try {
                      await launchUrl(url,
                          mode: LaunchMode.externalApplication);
                    } catch (_) {}
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final current = _currentUri;
    final theme = Theme.of(context);

    final barBg = theme.colorScheme.surface;
    final title = _title.isNotEmpty
        ? _title
        : (current?.host.isNotEmpty == true ? current!.host : 'Web');

    if (kIsWeb) {
      return Scaffold(
        backgroundColor: ShamellPalette.background,
        appBar: AppBar(
          backgroundColor: barBg,
          elevation: 0,
          title: Text(
            title,
            style: const TextStyle(color: ShamellPalette.textPrimary),
          ),
          iconTheme: const IconThemeData(color: ShamellPalette.textPrimary),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'WebView is not supported on Web. Use the menu to open in browser.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final web = controller == null
        ? const Center(child: CircularProgressIndicator())
        : WebViewWidget(controller: controller);

    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        unawaited(() async {
          final shouldPop = await _handleBack();
          if (!shouldPop || !context.mounted) return;
          Navigator.of(context).pop(result);
        }());
      },
      child: Scaffold(
        backgroundColor: ShamellPalette.background,
        appBar: AppBar(
          backgroundColor: barBg,
          elevation: 0,
          titleSpacing: 0,
          leadingWidth: 96,
          leading: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                onPressed: () async {
                  final pop = await _handleBack();
                  if (pop && context.mounted) {
                    Navigator.of(context).maybePop();
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: ShamellPalette.textPrimary,
              fontSize: 16,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.more_horiz),
              onPressed: _showMenu,
            ),
          ],
          iconTheme: const IconThemeData(color: ShamellPalette.textPrimary),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(2),
            child: AnimatedOpacity(
              opacity: _loading ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              child: LinearProgressIndicator(
                minHeight: 2,
                value: _loading ? (_progress == 0 ? null : _progress) : 0,
                backgroundColor: Colors.transparent,
                color: ShamellPalette.green,
              ),
            ),
          ),
        ),
        body: web,
      ),
    );
  }
}
