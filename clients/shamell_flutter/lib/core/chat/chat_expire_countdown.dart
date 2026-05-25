/// Cycle 19 — render a compact "expires in X" label for messages
/// whose `expireAt` is in the future. The chat-page bubble footer
/// surfaces this so disappearing-message recipients can see the
/// remaining window without opening the long-press menu.

/// Pure helper: format `remaining` as the shortest legible label.
///
/// Rules (tuned to feel like a phone clock at a glance):
/// * `<= 0` → empty string ("don't show a chip")
/// * `< 60s` → "Ns"  (drop the trailing zero)
/// * `< 60m` → "Nm"
/// * `< 24h` → "Nh"  (round down)
/// * otherwise → "Nd" up to 99 days, then ">99d"
String formatExpireCountdown(Duration remaining) {
  if (remaining.inSeconds <= 0) return '';
  if (remaining.inMinutes < 1) return '${remaining.inSeconds}s';
  if (remaining.inHours < 1) return '${remaining.inMinutes}m';
  if (remaining.inDays < 1) return '${remaining.inHours}h';
  final d = remaining.inDays;
  if (d > 99) return '>99d';
  return '${d}d';
}
