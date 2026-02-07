/// Minimal manifest model for a WeChat‑style Mini‑Program.
///
/// Für das erste MVP halten wir das Schema bewusst klein und
/// konzentrieren uns auf einfache Info‑Seiten mit Buttons, die
/// entweder einen Modul‑Sprung (`openMod`) oder ein Schließen
/// auslösen.

library mini_program_models;

class MiniProgramManifest {
  final String id;
  final String titleEn;
  final String titleAr;
  final String descriptionEn;
  final String descriptionAr;
  final List<MiniProgramAction> actions;

  const MiniProgramManifest({
    required this.id,
    required this.titleEn,
    required this.titleAr,
    required this.descriptionEn,
    required this.descriptionAr,
    required this.actions,
  });

  String title({required bool isArabic}) => isArabic ? titleAr : titleEn;

  String description({required bool isArabic}) =>
      isArabic ? descriptionAr : descriptionEn;
}

enum MiniProgramActionKind { close, openMod, openUrl }

class MiniProgramAction {
  final String id;
  final String labelEn;
  final String labelAr;
  final MiniProgramActionKind kind;
  final String? modId;
  final String? url;

  const MiniProgramAction({
    required this.id,
    required this.labelEn,
    required this.labelAr,
    required this.kind,
    this.modId,
    this.url,
  });

  String label({required bool isArabic}) => isArabic ? labelAr : labelEn;
}
