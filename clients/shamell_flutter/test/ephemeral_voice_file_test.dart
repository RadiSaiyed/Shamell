import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/ephemeral_voice_file.dart';

void main() {
  test('writeEphemeralVoiceFile stores bytes in isolated temp directory',
      () async {
    final root = await Directory.systemTemp.createTemp('shamell_test_root_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final file = await writeEphemeralVoiceFile(
      Uint8List.fromList(utf8.encode('voice-bytes')),
      stem: 'Voice Playback',
      rootDirectory: root,
    );

    expect(await file.exists(), isTrue);
    expect(await file.readAsString(), 'voice-bytes');
    expect(
        file.parent.path, contains('shamell_voice_ephemeral_voice_playback_'));
  });

  test('deleteEphemeralVoiceFile removes file and managed temp directory',
      () async {
    final root = await Directory.systemTemp.createTemp('shamell_test_root_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final file = await createEphemeralVoiceFile(
      stem: 'group_voice',
      rootDirectory: root,
    );
    await file.writeAsBytes(const <int>[1, 2, 3], flush: true);
    final dir = file.parent;

    await deleteEphemeralVoiceFile(file.path);

    expect(await file.exists(), isFalse);
    expect(await dir.exists(), isFalse);
  });

  test('purgeEphemeralVoiceFiles removes leftover managed temp directories',
      () async {
    final root = await Directory.systemTemp.createTemp('shamell_test_root_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final staleFile = await writeEphemeralVoiceFile(
      Uint8List.fromList(const <int>[4, 5, 6]),
      stem: 'voice_purge',
      rootDirectory: root,
    );
    final staleDir = staleFile.parent;

    await purgeEphemeralVoiceFiles(rootDirectory: root);

    expect(await staleFile.exists(), isFalse);
    expect(await staleDir.exists(), isFalse);
  });
}
