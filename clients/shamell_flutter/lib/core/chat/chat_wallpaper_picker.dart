import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Picks an image from the gallery and copies it into the app's local
/// documents directory so the wallpaper stays available even if the user
/// later removes the gallery original (Cycle 3D).
///
/// **Why copy instead of referencing the gallery URI directly.** Android
/// content URIs from the gallery are scoped to the picker session and can
/// be revoked when the app process is killed or when the system rotates
/// permissions. Copying to the app-private docs directory gives us a
/// stable file path that survives every restart — at the cost of one
/// duplicated file per chat (acceptable: typical wallpapers are well
/// under 1 MB and we only ever keep one per peer thanks to the
/// `removeWallpaperFile` cleanup on overwrite).
///
/// **Why a class, not free functions.** `ImagePicker` and the docs-dir
/// path-provider are externally-impure dependencies that need to be
/// mocked in tests. Threading them through a class with an overrideable
/// constructor keeps the chat page testable without monkey-patching
/// statics.
class ChatWallpaperPicker {
  /// Optional injectable [ImagePicker] for tests. Production code defaults
  /// to a fresh instance per call (the picker holds no per-instance state
  /// worth sharing, so this is fine).
  final ImagePicker _picker;

  /// Optional injectable function that resolves the app-docs directory.
  /// Tests can substitute a temp directory; production defaults to
  /// [getApplicationDocumentsDirectory].
  final Future<Directory> Function() _docsDirProvider;

  ChatWallpaperPicker({
    ImagePicker? picker,
    Future<Directory> Function()? docsDirProvider,
  })  : _picker = picker ?? ImagePicker(),
        _docsDirProvider =
            docsDirProvider ?? getApplicationDocumentsDirectory;

  /// Opens the system gallery and, if the user picks an image, copies
  /// the chosen file into the app's `chat_wallpapers/` subdirectory
  /// under a stable per-peer filename. Returns the absolute path of the
  /// copied file (suitable for storing as a theme key like
  /// `wallpaper:<path>` via `_setChatThemeForPeer`).
  ///
  /// Returns `null` if the user cancelled the picker or if any I/O
  /// failure occurred — callers should treat null as "no change, keep
  /// the existing wallpaper" rather than as an error worth surfacing.
  ///
  /// The destination filename is `peer_<safe_peer_id>.<ext>`, with the
  /// extension preserved from the source so e.g. PNG transparency is
  /// retained. Overwrites any previous wallpaper for the same peer
  /// (the old file's bytes become unreachable; cleanup of dangling
  /// files happens via [removeWallpaperFile] when the user explicitly
  /// clears or replaces).
  Future<String?> pickAndPersistWallpaperForPeer(String peerId) async {
    final trimmedPeerId = peerId.trim();
    if (trimmedPeerId.isEmpty) return null;

    final XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: ImageSource.gallery,
        // Reasonable cap so we never copy a 50 MB DSLR shot into the
        // app's private storage. 2 MP is plenty for a chat backdrop.
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
    } catch (error, stack) {
      debugPrint('ChatWallpaperPicker.pickImage threw: $error\n$stack');
      return null;
    }

    if (picked == null) return null;

    try {
      final docs = await _docsDirProvider();
      final wallpapersDir = Directory('${docs.path}/chat_wallpapers');
      if (!await wallpapersDir.exists()) {
        await wallpapersDir.create(recursive: true);
      }
      // Strip everything that isn't safe in a filename so a peer id of
      // the form "user@host" or "grp:<uuid>" maps cleanly. We don't
      // need to be reversible — the chat page already holds the peer
      // id as a Map key, this filename is just for storage.
      final safe = trimmedPeerId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final ext = _extensionOf(picked.path);
      final dest = File('${wallpapersDir.path}/peer_$safe$ext');
      await dest.parent.create(recursive: true);
      await File(picked.path).copy(dest.path);
      return dest.path;
    } catch (error, stack) {
      debugPrint('ChatWallpaperPicker.copy threw: $error\n$stack');
      return null;
    }
  }

  /// Best-effort cleanup of a previously-stored wallpaper file. Returns
  /// `true` if the file was deleted or was already gone; `false` if the
  /// delete attempt threw (we never propagate the error because removing
  /// a stale wallpaper must never block the user from picking a new one).
  Future<bool> removeWallpaperFile(String path) async {
    if (path.trim().isEmpty) return true;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
      return true;
    } catch (error, stack) {
      debugPrint('ChatWallpaperPicker.remove threw: $error\n$stack');
      return false;
    }
  }

  /// Extracts the file extension including the leading dot. Falls back to
  /// `.jpg` because the picker compresses to JPEG when [imageQuality] is
  /// set, so an extensionless platform URI still safely lands on a JPEG
  /// payload.
  static String _extensionOf(String path) {
    final dotIdx = path.lastIndexOf('.');
    if (dotIdx < 0 || dotIdx == path.length - 1) return '.jpg';
    final ext = path.substring(dotIdx);
    // Guard against absurd "extensions" like "/some/file.exclamation_mark"
    if (ext.length > 6 || ext.contains('/') || ext.contains('\\')) {
      return '.jpg';
    }
    return ext.toLowerCase();
  }
}

/// Theme-key prefix that flags the value as a custom wallpaper file path.
/// The chat page renderer checks for this prefix before falling through to
/// the legacy named-theme (`'default'`, `'dark'`, `'green'`) dispatch.
///
/// Example: `'wallpaper:/data/data/com.shamell.app/.../peer_alice.jpg'`.
const String chatWallpaperThemeKeyPrefix = 'wallpaper:';

/// Build a theme-key value for a wallpaper file path, matching the format
/// the chat page expects.
String chatWallpaperThemeKey(String absolutePath) =>
    '$chatWallpaperThemeKeyPrefix$absolutePath';

/// Returns the wallpaper file path if [themeKey] is a wallpaper key,
/// otherwise `null`.
String? wallpaperPathFromThemeKey(String? themeKey) {
  if (themeKey == null) return null;
  if (!themeKey.startsWith(chatWallpaperThemeKeyPrefix)) return null;
  final path = themeKey.substring(chatWallpaperThemeKeyPrefix.length);
  return path.isEmpty ? null : path;
}
