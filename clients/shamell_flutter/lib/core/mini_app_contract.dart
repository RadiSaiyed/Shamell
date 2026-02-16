import 'package:flutter/material.dart';

import 'mini_program_models.dart';
import 'superapp_api.dart';

/// Frontend contract for Shamell‑style Mini‑Apps.
///
/// Each Mini‑App provides its own entry widget/route and an optional
/// local manifest fallback for the Mini‑Program runtime.
abstract class MiniApp {
  String get id;
  MiniProgramManifest? manifest();
  Widget entry(BuildContext context, SuperappAPI api);
}
