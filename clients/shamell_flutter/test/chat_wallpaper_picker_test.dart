import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path/path.dart' as p;
import 'package:shamell_flutter/core/chat/chat_wallpaper_picker.dart';

class _FakeImagePickerPlatform extends ImagePickerPlatform {
  _FakeImagePickerPlatform({this.next});

  /// File the next call to `getImageFromSource` should return. Set to
  /// `null` to simulate user cancellation.
  XFile? next;

  /// Mutable list of `(source, options)` records — tests can assert
  /// the picker was driven correctly.
  final List<({ImageSource source, double? maxWidth, double? maxHeight, int? imageQuality})>
      recordedCalls =
          <({ImageSource source, double? maxWidth, double? maxHeight, int? imageQuality})>[];

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    recordedCalls.add((
      source: source,
      maxWidth: options.maxWidth,
      maxHeight: options.maxHeight,
      imageQuality: options.imageQuality,
    ));
    return next;
  }
}

void main() {
  group('chat wallpaper theme-key encoding', () {
    test('wallpaperPathFromThemeKey extracts the path for wallpaper keys', () {
      expect(
        wallpaperPathFromThemeKey('wallpaper:/data/app/peer_alice.jpg'),
        '/data/app/peer_alice.jpg',
      );
    });

    test('wallpaperPathFromThemeKey returns null for named themes', () {
      expect(wallpaperPathFromThemeKey('default'), isNull);
      expect(wallpaperPathFromThemeKey('dark'), isNull);
      expect(wallpaperPathFromThemeKey('green'), isNull);
      expect(wallpaperPathFromThemeKey(null), isNull);
    });

    test('wallpaperPathFromThemeKey rejects empty path after prefix', () {
      // Edge case: malformed pref value with the prefix but no path.
      // Returning null keeps the renderer in the named-theme path.
      expect(wallpaperPathFromThemeKey('wallpaper:'), isNull);
    });

    test('chatWallpaperThemeKey round-trips a path', () {
      const path = '/tmp/peer_alice.jpg';
      final key = chatWallpaperThemeKey(path);
      expect(key, 'wallpaper:$path');
      expect(wallpaperPathFromThemeKey(key), path);
    });
  });

  group('ChatWallpaperPicker.pickAndPersistWallpaperForPeer', () {
    late Directory tempDocs;

    setUp(() async {
      tempDocs = await Directory.systemTemp.createTemp('chat_wallpaper_test_');
    });

    tearDown(() async {
      if (await tempDocs.exists()) {
        await tempDocs.delete(recursive: true);
      }
    });

    test('returns null when user cancels the picker', () async {
      final fakePlatform = _FakeImagePickerPlatform(next: null);
      ImagePickerPlatform.instance = fakePlatform;
      final picker = ChatWallpaperPicker(
        docsDirProvider: () async => tempDocs,
      );

      final result = await picker.pickAndPersistWallpaperForPeer('alice');
      expect(result, isNull);
      expect(
        fakePlatform.recordedCalls,
        hasLength(1),
        reason: 'we still called the picker — null is the user cancellation',
      );
    });

    test('copies the picked file into chat_wallpapers/peer_<id>.<ext>',
        () async {
      // Stage a fake source file the picker will hand back.
      final source = File(p.join(tempDocs.path, 'gallery_source.png'));
      await source.writeAsBytes(<int>[1, 2, 3, 4, 5]);

      final fakePlatform = _FakeImagePickerPlatform(
        next: XFile(source.path),
      );
      ImagePickerPlatform.instance = fakePlatform;
      final picker = ChatWallpaperPicker(
        docsDirProvider: () async => tempDocs,
      );

      final result = await picker.pickAndPersistWallpaperForPeer('alice');
      expect(result, isNotNull);
      expect(result!, contains('chat_wallpapers'));
      expect(result, endsWith('peer_alice.png'));
      // The copied file actually exists and matches source bytes.
      final dest = File(result);
      expect(await dest.exists(), isTrue);
      expect(await dest.readAsBytes(), <int>[1, 2, 3, 4, 5]);
    });

    test('sanitizes unsafe characters in the peer id for the filename',
        () async {
      // A real-world group id from chat_service.dart: 'grp:abc-123'.
      // ':' would break the filename on most filesystems.
      final source = File(p.join(tempDocs.path, 'gallery.jpg'));
      await source.writeAsBytes(<int>[42]);
      ImagePickerPlatform.instance =
          _FakeImagePickerPlatform(next: XFile(source.path));

      final picker = ChatWallpaperPicker(
        docsDirProvider: () async => tempDocs,
      );

      final result = await picker.pickAndPersistWallpaperForPeer('grp:abc-123');
      expect(result, isNotNull);
      expect(
        p.basename(result!),
        'peer_grp_abc-123.jpg',
        reason: 'colon must be sanitized; hyphen and underscore preserved',
      );
    });

    test('empty peer id is rejected without touching the picker', () async {
      final fakePlatform = _FakeImagePickerPlatform();
      ImagePickerPlatform.instance = fakePlatform;
      final picker = ChatWallpaperPicker(
        docsDirProvider: () async => tempDocs,
      );

      final result = await picker.pickAndPersistWallpaperForPeer('');
      expect(result, isNull);
      expect(fakePlatform.recordedCalls, isEmpty);
    });

    test('passes 1600x1600 / quality 80 to the picker', () async {
      // We compress to JPEG quality 80 and cap dimensions so a 50 MP
      // DSLR shot doesn't become a 50 MB chat wallpaper.
      final source = File(p.join(tempDocs.path, 'g.jpg'));
      await source.writeAsBytes(<int>[1]);
      final fakePlatform = _FakeImagePickerPlatform(
        next: XFile(source.path),
      );
      ImagePickerPlatform.instance = fakePlatform;
      final picker = ChatWallpaperPicker(
        docsDirProvider: () async => tempDocs,
      );

      await picker.pickAndPersistWallpaperForPeer('alice');
      expect(fakePlatform.recordedCalls.first.maxWidth, 1600);
      expect(fakePlatform.recordedCalls.first.maxHeight, 1600);
      expect(fakePlatform.recordedCalls.first.imageQuality, 80);
      expect(fakePlatform.recordedCalls.first.source, ImageSource.gallery);
    });
  });

  group('ChatWallpaperPicker.removeWallpaperFile', () {
    late Directory tempDocs;

    setUp(() async {
      tempDocs = await Directory.systemTemp.createTemp('chat_wallpaper_rm_');
    });

    tearDown(() async {
      if (await tempDocs.exists()) {
        await tempDocs.delete(recursive: true);
      }
    });

    test('deletes an existing file and returns true', () async {
      final f = File(p.join(tempDocs.path, 'old.jpg'));
      await f.writeAsBytes(<int>[1, 2, 3]);
      final picker = ChatWallpaperPicker();

      final ok = await picker.removeWallpaperFile(f.path);
      expect(ok, isTrue);
      expect(await f.exists(), isFalse);
    });

    test('returns true (idempotent) when the file already does not exist',
        () async {
      final picker = ChatWallpaperPicker();
      final ok = await picker.removeWallpaperFile(
        p.join(tempDocs.path, 'never_existed.jpg'),
      );
      expect(ok, isTrue);
    });

    test('returns true for empty path without throwing', () async {
      final picker = ChatWallpaperPicker();
      expect(await picker.removeWallpaperFile(''), isTrue);
      expect(await picker.removeWallpaperFile('   '), isTrue);
    });
  });
}
