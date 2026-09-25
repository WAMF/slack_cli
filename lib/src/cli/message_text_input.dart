import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:dart_slack/src/cli/commands/authenticated_command.dart';
import 'package:dart_slack/src/cli/message_text.dart';
import 'package:mason_logger/mason_logger.dart';

/// Option that carries the message text on the command line.
const String textOption = 'text';

/// Option that names a file holding the message text.
const String textFileOption = 'text-file';

/// Flag that reads the message text from standard input.
const String textStdinFlag = 'text-stdin';

/// The value of [textFileOption] that means standard input.
const String stdinPathMarker = '-';

/// Spellings a POSIX shell expands inside a double-quoted argument.
///
/// Each one turns message text into a command the shell runs before this
/// process starts.
const List<String> shellSubstitutionMarkers = ['`', r'$(', r'${'];

/// The UTF-8 encoding of U+FEFF, the byte-order mark.
const List<int> utf8ByteOrderMark = [0xEF, 0xBB, 0xBF];

/// Decodes [bytes] as UTF-8 without losing a leading U+FEFF.
///
/// Dart's UTF-8 decoder drops a leading byte-order mark, and
/// `File.readAsStringSync` uses that decoder. U+FEFF is a valid character,
/// so dropping it changes the message. The byte-for-byte promise of
/// `--text-file` and `--text-stdin` has to hold for it too, so this puts it
/// back when the bytes carried it.
String decodeMessageBytes(List<int> bytes) {
  final text = utf8.decode(bytes);
  final hadMark =
      bytes.length >= 3 &&
      bytes[0] == utf8ByteOrderMark[0] &&
      bytes[1] == utf8ByteOrderMark[1] &&
      bytes[2] == utf8ByteOrderMark[2];
  // UNCONDITIONAL when the bytes carried a mark. The decoder drops EXACTLY
  // ONE leading mark, so one must go back, whatever the decoded text starts
  // with. Testing `!text.startsWith('\uFEFF')` first was wrong and lost a
  // character: two leading marks decode to one, that one satisfied the test,
  // and the repair was skipped (kumar-waaf, review of #53).
  if (hadMark) return '\uFEFF$text';
  return text;
}

/// Reads every byte of standard input.
///
/// The read is synchronous because [AuthenticatedCommand.validateArguments]
/// is synchronous, and the message text must be resolved before any
/// credential is touched.
List<int> readStandardInputBytes() {
  final buffer = BytesBuilder(copy: false);
  while (true) {
    final byte = stdin.readByteSync();
    if (byte < 0) break;
    buffer.addByte(byte);
  }
  return buffer.takeBytes();
}

/// Reads standard input and decodes it as UTF-8.
///
/// [readBytes] is the byte source, and a test replaces it. The split is
/// deliberate: the byte loop needs a real process to exercise, but every
/// way this function can change the text lives in the decode, so a test
/// that supplies bytes runs the whole of the part that can be wrong.
String readStandardInput({List<int> Function()? readBytes}) =>
    decodeMessageBytes((readBytes ?? readStandardInputBytes)());

/// Gives a command three ways to receive message text, only one of which
/// passes that text through a shell.
///
/// The inline `--text` option is the unsafe one. A backtick span or a `$(`
/// span inside a double-quoted shell argument runs as a command *before*
/// this process starts, so the text the tool receives is not the text the
/// author wrote, and the send still reports success. The shell leaves no
/// trace of what it removed, so the tool cannot detect that case: the only
/// fix is to keep the text out of the argument list.
///
/// `--text-file <path>` and `--text-stdin` do that. Their bytes never reach
/// a shell, so they are sent unchanged. Both decode through
/// [decodeMessageBytes], which keeps a leading U+FEFF that the UTF-8
/// decoder would otherwise drop.
///
/// Two deliberate differences between the sources:
///
/// * Inline text is passed through [normalizeMessageText], which repairs
///   shell-quoting damage such as a literal `\n`. File and standard-input
///   text is sent byte-for-byte. There is no shell between the author and
///   those bytes, so there is nothing to repair, and repairing would corrupt
///   a file that legitimately contains the two characters `\` and `n`.
/// * The backtick warning applies to inline text only, for the same reason.
mixin MessageTextCommand on AuthenticatedCommand {
  late final String _messageText;

  /// Reads standard input. Replaced in tests.
  String Function() readMessageStdin = readStandardInput;

  /// Adds `--text`, `--text-file` and `--text-stdin` to [parser].
  ///
  /// [help] describes the text, for example `'The message text.'`.
  void addMessageTextOptions(ArgParser parser, {required String help}) {
    parser
      ..addOption(
        textOption,
        abbr: 't',
        help:
            '$help Unsafe for text that contains a backtick or "\$(": a '
            'shell runs those before this tool starts. Use --$textFileOption '
            'or --$textStdinFlag for that text.',
      )
      ..addOption(
        textFileOption,
        help:
            'Read the message text from this file, byte for byte. Use '
            '"$stdinPathMarker" for standard input. This is the safe way to '
            'pass text that contains backticks, quotes or newlines. It is '
            'not --file, which attaches a file to the message.',
      )
      ..addFlag(
        textStdinFlag,
        negatable: false,
        help: 'Read the message text from standard input, byte for byte.',
      );
  }

  /// The resolved message text. Valid only after [validateMessageText]
  /// returns `null`.
  String get messageText => _messageText;

  @override
  int? validateArguments() => validateMessageText();

  /// Resolves the message text from exactly one of the three sources.
  ///
  /// Returns the exit code to stop with, or `null` to continue.
  int? validateMessageText() {
    final inline = argResults![textOption] as String?;
    final textFile = argResults![textFileOption] as String?;
    final stdinFlag = argResults![textStdinFlag] as bool? ?? false;

    final fromStdin = stdinFlag || textFile == stdinPathMarker;
    final fromFile = textFile != null && textFile != stdinPathMarker;
    final sources = [inline != null, fromFile, fromStdin].where((e) => e);

    if (sources.isEmpty) {
      return _messageTextUsageError(
        'Missing the message text. Give it with exactly one of '
        '--$textOption, --$textFileOption <path> or --$textStdinFlag.',
      );
    }
    if (sources.length > 1) {
      return _messageTextUsageError(
        'Conflicting message text. Give exactly one of --$textOption, '
        '--$textFileOption <path> or --$textStdinFlag.',
      );
    }

    if (fromStdin) {
      _messageText = readMessageStdin();
      return null;
    }

    if (fromFile) {
      final file = File(textFile);
      if (!file.existsSync()) {
        logger.err('Message text file not found: $textFile');
        return ExitCode.noInput.code;
      }
      try {
        _messageText = decodeMessageBytes(file.readAsBytesSync());
      } on FileSystemException catch (e) {
        logger.err('Cannot read the message text file $textFile: ${e.message}');
        return ExitCode.noInput.code;
      }
      return null;
    }

    _warnAboutShellSubstitution(inline!);
    _messageText = normalizeMessageText(inline);
    return null;
  }

  /// Warns when inline text carries a shell substitution spelling.
  ///
  /// The warning is not a detector of damage already done. A span the shell
  /// ran is gone before this process starts, so a marker that arrives here
  /// proves the shell did *not* run it this time. The warning names the
  /// habit, because the same command line under different quoting silently
  /// sends a different message.
  void _warnAboutShellSubstitution(String text) {
    final found = shellSubstitutionMarkers.where(text.contains).toList();
    if (found.isEmpty) return;
    final markers = found.map((m) => '"$m"').join(' and ');
    logger.warn(
      'The --$textOption value contains $markers. A shell runs that '
      'spelling as a command before this tool starts. It arrived here '
      'intact, so the shell did not run it this time. A span the shell '
      'does run leaves no trace and the send still reports success. Use '
      '--$textFileOption <path> or --$textStdinFlag for text like this.',
    );
  }

  int _messageTextUsageError(String message) {
    logger
      ..err(message)
      ..info('')
      ..info(usage);
    return ExitCode.usage.code;
  }
}
