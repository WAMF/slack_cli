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

/// Reads every byte of standard input and decodes it as UTF-8.
///
/// The read is synchronous because [AuthenticatedCommand.validateArguments]
/// is synchronous, and the message text must be resolved before any
/// credential is touched.
String readStandardInput() {
  final buffer = BytesBuilder(copy: false);
  while (true) {
    final byte = stdin.readByteSync();
    if (byte < 0) break;
    buffer.addByte(byte);
  }
  return utf8.decode(buffer.takeBytes());
}

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
/// a shell, so they are sent unchanged.
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
        _messageText = file.readAsStringSync();
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
