import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'l10n.dart';
import 'wechat_ui.dart';

class WeChatWebViewPage extends StatefulWidget {
  final Uri initialUri;
  final Uri? baseUri;
  final String? initialTitle;
  final bool injectSessionForSameOrigin;

  const WeChatWebViewPage({
    super.key,
    required this.initialUri,
    this.baseUri,
    this.initialTitle,
    this.injectSessionForSameOrigin = true,
  });

  @override
  State<WeChatWebViewPage> createState() => _WeChatWebViewPageState();
}

class _WeChatWebViewPageState extends State<WeChatWebViewPage> {
  WebViewController? _controller;
  Uri? _currentUri;
  String _title = '';
  double _progress = 0;
  bool _loading = true;

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
    if (baseUri != null && widget.injectSessionForSameOrigin) {
      targetUri = await _maybeWireSession(
        targetUri,
        baseUri: baseUri,
      );
    }

    final controller = WebViewController();
    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(WeChatPalette.background)
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

  Future<String?> _getSaCookie() async {
    try {
      final sp = await SharedPreferences.getInstance();
      return sp.getString('sa_cookie');
    } catch (_) {
      return null;
    }
  }

  String? _extractSaSession(String cookie) {
    final c = cookie.trim();
    if (c.isEmpty) return null;
    try {
      final m = RegExp(r'sa_session=([^;]+)').firstMatch(c);
      if (m != null && m.group(1) != null && m.group(1)!.isNotEmpty) {
        return m.group(1)!.trim();
      }
    } catch (_) {}
    return c;
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
      final cookie = await _getSaCookie();
      final token = cookie == null ? null : _extractSaSession(cookie);
      if (token == null || token.isEmpty) return uri;
      await _setWebViewSessionCookie(baseUri: baseUri, sessionToken: token);
      if (uri.queryParameters.containsKey('sa_session')) return uri;
      final qp = Map<String, String>.from(uri.queryParameters);
      qp['sa_session'] = token;
      return uri.replace(queryParameters: qp);
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
        backgroundColor: WeChatPalette.background,
        appBar: AppBar(
          backgroundColor: barBg,
          elevation: 0,
          title: Text(
            title,
            style: const TextStyle(color: WeChatPalette.textPrimary),
          ),
          iconTheme: const IconThemeData(color: WeChatPalette.textPrimary),
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
        backgroundColor: WeChatPalette.background,
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
              color: WeChatPalette.textPrimary,
              fontSize: 16,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.more_horiz),
              onPressed: _showMenu,
            ),
          ],
          iconTheme: const IconThemeData(color: WeChatPalette.textPrimary),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(2),
            child: AnimatedOpacity(
              opacity: _loading ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              child: LinearProgressIndicator(
                minHeight: 2,
                value: _loading ? (_progress == 0 ? null : _progress) : 0,
                backgroundColor: Colors.transparent,
                color: WeChatPalette.green,
              ),
            ),
          ),
        ),
        body: web,
      ),
    );
  }
}
