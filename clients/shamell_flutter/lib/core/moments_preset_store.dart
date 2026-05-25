import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

const momentsPresetTextPrefsKey = 'moments_preset_text';
const momentsPresetImagePrefsKey = 'moments_preset_image';
const momentsPresetMiniProgramIdPrefsKey = 'moments_preset_mini_program_id';

class MomentsPresetDraft {
  final String? text;
  final Uint8List? imageBytes;
  final String? miniProgramId;

  const MomentsPresetDraft({
    this.text,
    this.imageBytes,
    this.miniProgramId,
  });

  bool get hasContent =>
      (text ?? '').trim().isNotEmpty ||
      imageBytes != null ||
      (miniProgramId ?? '').trim().isNotEmpty;
}

Future<MomentsPresetDraft> loadAndClearMomentsPreset() async {
  final sp = await SharedPreferences.getInstance();
  final text = sp.getString(momentsPresetTextPrefsKey);
  final imgB64 = sp.getString(momentsPresetImagePrefsKey);
  final miniProgramId = sp.getString(momentsPresetMiniProgramIdPrefsKey);

  Uint8List? imageBytes;
  if (imgB64 != null && imgB64.isNotEmpty) {
    try {
      imageBytes = base64Decode(imgB64);
    } catch (_) {
      imageBytes = null;
    }
  }

  await sp.remove(momentsPresetTextPrefsKey);
  await sp.remove(momentsPresetImagePrefsKey);
  await sp.remove(momentsPresetMiniProgramIdPrefsKey);

  return MomentsPresetDraft(
    text: (text ?? '').trim().isEmpty ? null : text,
    imageBytes: imageBytes,
    miniProgramId:
        (miniProgramId ?? '').trim().isEmpty ? null : miniProgramId!.trim(),
  );
}

Future<void> saveMiniProgramMomentsPreset({
  required String text,
  required String miniProgramId,
}) async {
  final cleanText = text.trim();
  final cleanMiniProgramId = miniProgramId.trim();
  if (cleanText.isEmpty && cleanMiniProgramId.isEmpty) return;
  final sp = await SharedPreferences.getInstance();
  if (cleanText.isNotEmpty) {
    await sp.setString(momentsPresetTextPrefsKey, cleanText);
  } else {
    await sp.remove(momentsPresetTextPrefsKey);
  }
  if (cleanMiniProgramId.isNotEmpty) {
    await sp.setString(
      momentsPresetMiniProgramIdPrefsKey,
      cleanMiniProgramId,
    );
  } else {
    await sp.remove(momentsPresetMiniProgramIdPrefsKey);
  }
}
