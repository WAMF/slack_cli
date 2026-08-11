/// Normalizes the `--text` argument of the message-writing commands before it
/// is sent to the Slack Web API.
///
/// A shell is the only way to supply message text to the CLI, and a plain
/// double-quoted string does not interpret backslash escapes: `"a\nb"` is the
/// four characters `a`, `\`, `n`, `b` — not `a`, newline, `b`. Slack's mrkdwn
/// renderer shows that literal `\n` as text, so the line break is lost.
///
/// This is a safety net, not a rewrite of correct input. Text that already
/// contains real newlines, real tabs, and printable characters is returned
/// byte-for-byte unchanged.
///
/// Three steps run in order:
///
/// 1. Unescape the literal two-character sequences `\n`, `\r`, `\t` and `\\`.
///    `\\` yields a single backslash, so `\\n` is the escape hatch for text
///    that must keep a literal `\n`. Every other backslash sequence (`\d`,
///    `\s`, a trailing `\`) is left alone.
/// 2. Normalize line endings: `\r\n` and a lone `\r` become `\n`.
/// 3. Strip the remaining non-printable control characters (C0 and DEL),
///    keeping newline and tab.
String normalizeMessageText(String text) {
  final unescaped = _unescape(text);
  final normalized = _normalizeLineEndings(unescaped);
  return _stripControlCharacters(normalized);
}

/// Replaces the literal `\n`, `\r`, `\t` and `\\` sequences with the
/// characters they denote, leaving any other backslash sequence untouched.
String _unescape(String text) {
  if (!text.contains(r'\')) return text;

  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (char != r'\' || i + 1 == text.length) {
      buffer.write(char);
      continue;
    }
    final next = text[i + 1];
    final replacement = switch (next) {
      'n' => '\n',
      'r' => '\r',
      't' => '\t',
      r'\' => r'\',
      _ => null,
    };
    if (replacement == null) {
      buffer.write(char);
      continue;
    }
    buffer.write(replacement);
    i++;
  }
  return buffer.toString();
}

/// Converts `\r\n` and lone `\r` line endings to `\n`.
String _normalizeLineEndings(String text) {
  if (!text.contains('\r')) return text;
  return text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
}

/// Removes C0 control characters and DEL, keeping newline and tab.
String _stripControlCharacters(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    final isC0 = rune < 0x20;
    final isDelete = rune == 0x7F;
    final isKept = rune == 0x0A || rune == 0x09;
    if (isKept || !(isC0 || isDelete)) {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}
