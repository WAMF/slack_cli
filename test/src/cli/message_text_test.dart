import 'package:dart_slack/src/cli/message_text.dart';
import 'package:test/test.dart';

void main() {
  group('normalizeMessageText', () {
    test('leaves short plain text unchanged byte-for-byte', () {
      const text = 'Deploy is green. Nothing to do.';

      final result = normalizeMessageText(text);

      expect(result, equals(text));
      expect(result.codeUnits, equals(text.codeUnits));
    });

    test('leaves real newlines and tabs unchanged', () {
      const text = 'line1\nline2\n\nparagraph\tcolumn\n';

      final result = normalizeMessageText(text);

      expect(result, equals(text));
      expect(result.codeUnits, equals(text.codeUnits));
    });

    test('leaves mrkdwn, links, emoji and non-ASCII unchanged', () {
      const text =
          '<https://example.com|Read it> :tada: *bold* — café 🚀 100% & more';

      final result = normalizeMessageText(text);

      expect(result, equals(text));
      expect(result.codeUnits, equals(text.codeUnits));
    });

    test(r'converts a literal \n sequence to a real newline', () {
      // Two characters: backslash, n — what a plain double-quoted bash
      // string produces.
      final result = normalizeMessageText(r'line1\nline2');

      expect(result, equals('line1\nline2'));
      expect(result.codeUnits, contains(0x0A));
      expect(result, isNot(contains(r'\n')));
    });

    test(r'converts a literal \r\n sequence to a single newline', () {
      final result = normalizeMessageText(r'line1\r\nline2');

      expect(result, equals('line1\nline2'));
      expect(result.codeUnits, isNot(contains(0x0D)));
    });

    test(r'converts a literal lone \r sequence to a newline', () {
      final result = normalizeMessageText(r'line1\rline2');

      expect(result, equals('line1\nline2'));
    });

    test(r'converts a literal \t sequence to a real tab', () {
      final result = normalizeMessageText(r'name\tvalue');

      expect(result, equals('name\tvalue'));
    });

    test('converts every literal escape in a multi-paragraph message', () {
      final result = normalizeMessageText(
        r'Summary line.\n\nDetail one.\nDetail two.',
      );

      expect(result, equals('Summary line.\n\nDetail one.\nDetail two.'));
    });

    test('normalizes real CRLF and lone CR line endings to newlines', () {
      final result = normalizeMessageText('line1\r\nline2\rline3');

      expect(result, equals('line1\nline2\nline3'));
    });

    test('strips stray non-printable control bytes', () {
      // NUL, BEL, ESC, vertical tab, form feed and DEL around real text.
      final result = normalizeMessageText(
        '\u0000head\u0007 \u001B mid\u000B\u000Ctail\u007F',
      );

      expect(result, equals('head  midtail'));
    });

    test('keeps newline and tab while stripping other control bytes', () {
      final result = normalizeMessageText('a\nb\tc\u0001d');

      expect(result, equals('a\nb\tcd'));
    });

    test('treats a double backslash as the escape hatch for a literal', () {
      // \\n must stay the two visible characters \ and n.
      final result = normalizeMessageText(r'literal \\n stays');

      expect(result, equals(r'literal \n stays'));
      expect(result.codeUnits, isNot(contains(0x0A)));
    });

    test('leaves unrecognized backslash sequences untouched', () {
      const text = r'regex \d+ and \s* and a path C:\x';

      final result = normalizeMessageText(text);

      expect(result, equals(text));
    });

    test('leaves a trailing lone backslash untouched', () {
      const text = r'ends with a backslash \';

      final result = normalizeMessageText(text);

      expect(result, equals(text));
    });

    test('returns an empty string unchanged', () {
      expect(normalizeMessageText(''), isEmpty);
    });

    test('is idempotent for already normalized text', () {
      final once = normalizeMessageText(r'line1\nline2\ttabbed');

      expect(normalizeMessageText(once), equals(once));
    });
  });
}
