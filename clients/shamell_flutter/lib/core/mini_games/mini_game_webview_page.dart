import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../l10n.dart';

/// Reusable WebView host for any HTML5 mini-game bundled under
/// `assets/mini_games/<gameId>/`.
///
/// Mini-games are pure HTML+CSS+JS payloads that ship inside the
/// Flutter APK and run inside an in-app WebView. JavaScript is enabled
/// (every game we ship needs it) but **no Flutter ↔ JS bridge is
/// wired** by this host — so a game cannot reach wallet, contacts,
/// camera, or any other platform resource beyond its own DOM and
/// `localStorage`. Games that need to talk back to Flutter must use a
/// dedicated host page (see `HotelsMiniAppPage` for that pattern).
///
/// **Why one widget for all games (vs. one Stateful per game):**
/// the boilerplate around `WebViewController`, orientation locking,
/// loading spinner, and error fallback was the same in every game's
/// host page; parameterising it on `gameId` collapses ~80 lines of
/// duplication per new game into a single registration line.
///
/// **Lifecycle:**
///  * Forces portrait on push (every shipped game declares
///    `orientation: portrait` in its manifest).
///  * Restores the prior orientation lock on pop so other screens
///    (video calls, scanner) are unaffected.
///  * Disposes cleanly — the WebView tears down with the State, which
///    in turn releases the game's audio context and animation frame.
class MiniGameWebViewPage extends StatefulWidget {
  /// Folder name under `assets/mini_games/`. Used both to resolve the
  /// entry HTML and as a debug breadcrumb.
  final String gameId;

  /// Title shown in the AppBar.
  final String title;

  /// AppBar background. Defaults to the dark navy used by Jump-Jump
  /// so unconfigured games still look on-brand.
  final Color appBarColor;

  /// Scaffold + WebView background colour. Matches the game's first-
  /// paint colour to avoid a white flash before its CSS kicks in.
  final Color backgroundColor;

  /// Spinner colour while the WebView loads.
  final Color spinnerColor;

  const MiniGameWebViewPage({
    super.key,
    required this.gameId,
    required this.title,
    this.appBarColor = const Color(0xFF1A1F2E),
    this.backgroundColor = const Color(0xFFF3EEE5),
    this.spinnerColor = const Color(0xFFFF6B6B),
  });

  @override
  State<MiniGameWebViewPage> createState() => _MiniGameWebViewPageState();
}

class _MiniGameWebViewPageState extends State<MiniGameWebViewPage> {
  late final WebViewController _controller;
  bool _isLoading = true;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(widget.backgroundColor)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) {
              setState(() => _isLoading = false);
            }
          },
          onWebResourceError: (error) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _loadError = error.description;
              });
            }
          },
          onNavigationRequest: (request) {
            // Games are fully self-contained inside their bundled
            // index.html. A nav request to anywhere else indicates
            // either a game trying to deep-link out (we don't ship
            // those yet) or tampered assets escaping the sandbox.
            // Confine navigation to the asset root.
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;
            if (uri.scheme == 'file' || uri.scheme == 'about') {
              return NavigationDecision.navigate;
            }
            if (uri.scheme.isEmpty || uri.scheme == 'asset') {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadFlutterAsset('assets/mini_games/${widget.gameId}/index.html');
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      backgroundColor: widget.backgroundColor,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: widget.appBarColor,
        foregroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_isLoading)
              Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: widget.spinnerColor,
                ),
              ),
            if (_loadError != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.videogame_asset_off_outlined,
                          size: 56, color: Colors.redAccent),
                      const SizedBox(height: 12),
                      Text(
                        l.isArabic
                            ? 'تعذّر تحميل اللعبة.'
                            : 'Could not load the game.',
                        style: const TextStyle(
                          color: Color(0xFF1A1F2E),
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        _loadError.toString(),
                        style: const TextStyle(
                          color: Color(0xFF1A1F2E),
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
