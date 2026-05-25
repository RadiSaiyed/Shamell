import 'dart:io';
import 'dart:typed_data';

const String _shamellEphemeralVoiceDirPrefix = 'shamell_voice_ephemeral_';
const String _defaultVoiceExtension = 'aac';

String _sanitizeVoiceStem(String stem) {
  final normalized = stem.trim().toLowerCase();
  final sanitized = normalized.replaceAll(RegExp(r'[^a-z0-9._-]+'), '_');
  return sanitized.isEmpty ? 'voice' : sanitized;
}

Future<File> createEphemeralVoiceFile({
  required String stem,
  String extension = _defaultVoiceExtension,
  Directory? rootDirectory,
}) async {
  final root = rootDirectory ?? Directory.systemTemp;
  final safeStem = _sanitizeVoiceStem(stem);
  final safeExtension = _sanitizeVoiceStem(extension).replaceAll('.', '');
  final dir =
      await root.createTemp('$_shamellEphemeralVoiceDirPrefix${safeStem}_');
  return File('${dir.path}${Platform.pathSeparator}$safeStem.$safeExtension');
}

Future<File> writeEphemeralVoiceFile(
  Uint8List bytes, {
  required String stem,
  String extension = _defaultVoiceExtension,
  Directory? rootDirectory,
}) async {
  final file = await createEphemeralVoiceFile(
    stem: stem,
    extension: extension,
    rootDirectory: rootDirectory,
  );
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

Future<void> deleteEphemeralVoiceFile(String? path) async {
  final rawPath = path?.trim() ?? '';
  if (rawPath.isEmpty) return;
  final file = File(rawPath);
  try {
    if (await file.exists()) {
      await file.delete();
    }
  } catch (_) {}
  final segments = file.parent.uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();
  final dirName = segments.isEmpty ? '' : segments.last;
  if (!dirName.startsWith(_shamellEphemeralVoiceDirPrefix)) {
    return;
  }
  try {
    if (await file.parent.exists()) {
      await file.parent.delete(recursive: true);
    }
  } catch (_) {}
}

Future<void> purgeEphemeralVoiceFiles({Directory? rootDirectory}) async {
  final root = rootDirectory ?? Directory.systemTemp;
  try {
    await for (final entity in root.list(followLinks: false)) {
      final segments = entity.uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .toList(growable: false);
      final name = segments.isEmpty ? '' : segments.last;
      if (!name.startsWith(_shamellEphemeralVoiceDirPrefix)) {
        continue;
      }
      try {
        if (entity is Directory) {
          await entity.delete(recursive: true);
          continue;
        }
        if (entity is File) {
          await entity.delete();
        }
      } catch (_) {}
    }
  } catch (_) {}
}
