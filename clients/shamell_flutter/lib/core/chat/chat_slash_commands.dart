// Cycle 28 — slash-command shortcuts the composer recognises.
//
// The composer's _send flow intercepts text matching `/cmd[args…]`
// and dispatches to the matching command instead of sending the
// raw text. Commands are powerful: `/poll Question | A | B`
// opens the poll creator pre-filled with the parsed args.

/// A parsed slash command. `name` is the lowercased command (no
/// slash); `rest` is everything after the command name (already
/// trimmed). For `/poll Lunch? | Pizza | Sushi` you get
/// `name="poll"`, `rest="Lunch? | Pizza | Sushi"`.
class ParsedSlashCommand {
  final String name;
  final String rest;
  const ParsedSlashCommand({required this.name, required this.rest});
}

/// Parse the composer text as a slash command. Returns `null` when
/// the text isn't a slash command (i.e. doesn't start with `/` or
/// the part after `/` is empty / contains whitespace before the
/// first letter).
ParsedSlashCommand? parseSlashCommand(String text) {
  final trimmed = text.trimLeft();
  if (!trimmed.startsWith('/')) return null;
  // After the slash, the command name runs up to the first space or
  // end-of-string. Names must start with a letter.
  if (trimmed.length < 2) return null;
  final firstChar = trimmed.codeUnitAt(1);
  if (!_isAlpha(firstChar)) return null;
  int i = 1;
  while (i < trimmed.length) {
    final c = trimmed.codeUnitAt(i);
    if (c == 0x20 || c == 0x09 || c == 0x0A) break;
    if (!_isAlpha(c) && !_isDigit(c) && c != 0x5F /* _ */) break;
    i += 1;
  }
  final name = trimmed.substring(1, i).toLowerCase();
  final rest = i < trimmed.length ? trimmed.substring(i).trim() : '';
  return ParsedSlashCommand(name: name, rest: rest);
}

/// Cycle 28 — the registered command set. The chat page reads this
/// to show suggestions in the slash-command bar AND to dispatch
/// on send.
class SlashCommandDef {
  final String name;
  final String descriptionEn;
  final String descriptionAr;
  const SlashCommandDef({
    required this.name,
    required this.descriptionEn,
    required this.descriptionAr,
  });
}

const List<SlashCommandDef> slashCommands = <SlashCommandDef>[
  SlashCommandDef(
    name: 'poll',
    descriptionEn: 'Create a poll (optionally: question | opt1 | opt2)',
    descriptionAr: 'إنشاء استطلاع (اختياري: سؤال | خيار1 | خيار2)',
  ),
  SlashCommandDef(
    name: 'me',
    descriptionEn: 'Send a third-person action message',
    descriptionAr: 'إرسال رسالة عمل بصيغة الغائب',
  ),
  SlashCommandDef(
    name: 'shrug',
    descriptionEn: 'Insert ¯\\_(ツ)_/¯',
    descriptionAr: 'إدراج ¯\\_(ツ)_/¯',
  ),
];

/// Return the subset of [slashCommands] matching the partial name
/// the user is currently typing.
List<SlashCommandDef> suggestSlashCommands({required String partial}) {
  if (partial.isEmpty) return slashCommands;
  final p = partial.toLowerCase();
  return slashCommands
      .where((c) => c.name.startsWith(p))
      .toList(growable: false);
}

/// Helper for `/poll Lunch? | Pizza | Sushi` — split the rest by
/// `|` into question + options. Returns `null` if the rest is
/// empty (caller opens an empty creator dialog in that case).
({String question, List<String> options})? parsePollArgs(String rest) {
  final trimmed = rest.trim();
  if (trimmed.isEmpty) return null;
  final parts = trimmed.split('|').map((s) => s.trim()).toList();
  final question = parts.first;
  if (question.isEmpty) return null;
  final options =
      parts.skip(1).where((s) => s.isNotEmpty).toList(growable: false);
  return (question: question, options: options);
}

/// `/me danced wildly` → "* Alice danced wildly *"
String buildMeMessage({required String senderName, required String rest}) {
  final trimmed = rest.trim();
  final name = senderName.trim().isEmpty ? '?' : senderName.trim();
  if (trimmed.isEmpty) return '* $name *';
  return '* $name $trimmed *';
}

bool _isAlpha(int code) =>
    (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);
bool _isDigit(int code) => code >= 0x30 && code <= 0x39;
