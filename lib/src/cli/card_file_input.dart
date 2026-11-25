import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:dart_slack/src/cli/message_text_input.dart';
import 'package:dart_slack/src/rich_message/rich_message.dart';
import 'package:mason_logger/mason_logger.dart';

/// Option that names a file holding one RichMessage card as JSON.
const String cardFileOption = 'card-file';

/// The option that attaches a file to `send` and `reply`.
const String _attachOption = 'file';

/// Gives a command a fourth source for the message: a card file.
///
/// The file holds one provider-neutral RichMessage as JSON (epic
/// WAMF/WAAF_DigitalWorkforce#8546). The command checks it against the
/// shared schema and renders it as Block Kit in [validateArguments], so a
/// bad card stops the command before any credential is read and before any
/// API call. The error names the field that breaks the schema.
///
/// `--card-file` replaces `--text`, `--text-file` and `--text-stdin`: the
/// card's `fallbackText` becomes the message `text`. Give one of the four.
/// Without `--card-file` the text options behave exactly as before.
mixin CardFileCommand on MessageTextCommand {
  SlackCardPayload? _card;

  /// The rendered card, or `null` when the command sends plain text.
  ///
  /// Valid only after [validateArguments] returns `null`.
  SlackCardPayload? get card => _card;

  /// Adds `--card-file` to [parser].
  void addCardFileOption(ArgParser parser) {
    parser.addOption(
      cardFileOption,
      help:
          'Send a card: read one RichMessage as JSON from this file ("-" for '
          'standard input). The card is checked against the shared schema '
          'before any API call. Use it instead of --$textOption, '
          '--$textFileOption or --$textStdinFlag; its fallbackText is the '
          'message text.',
    );
  }

  @override
  int? validateArguments() {
    final path = argResults![cardFileOption] as String?;
    if (path == null) return super.validateArguments();

    final conflict = _conflictingOptions();
    if (conflict != null) return _usageError(conflict);

    final source = _readCard(path);
    if (source.exitCode != null) return source.exitCode;

    final Object? decoded;
    try {
      decoded = jsonDecode(source.text!);
    } on FormatException catch (e) {
      return _invalidCard(path, '(root)', 'is not valid JSON: ${e.message}');
    }
    try {
      _card = renderSlack(decoded);
    } on RichMessageValidationError catch (e) {
      return _invalidCard(path, e.field, e.problem);
    }
    return null;
  }

  /// The usage error for an option that cannot go with `--card-file`, or
  /// `null` when there is none.
  String? _conflictingOptions() {
    final textGiven =
        argResults![textOption] != null ||
        argResults![textFileOption] != null ||
        (argResults![textStdinFlag] as bool? ?? false);
    if (textGiven) {
      return 'Conflicting message content. Give --$cardFileOption or one of '
          '--$textOption, --$textFileOption, --$textStdinFlag, not both. The '
          "card's fallbackText is the message text.";
    }
    final attaches =
        argResults!.options.contains(_attachOption) &&
        argResults![_attachOption] != null;
    if (attaches) {
      return '--$cardFileOption cannot be combined with --$_attachOption. A '
          'file upload carries text only. Send the card and attach the file '
          'in two commands.';
    }
    return null;
  }

  /// Reads the card JSON from [path], or from standard input for `-`.
  ({String? text, int? exitCode}) _readCard(String path) {
    if (path == stdinPathMarker) {
      return (text: readMessageStdin(), exitCode: null);
    }
    final file = File(path);
    if (!file.existsSync()) {
      logger.err('Card file not found: $path');
      return (text: null, exitCode: ExitCode.noInput.code);
    }
    try {
      return (text: decodeMessageBytes(file.readAsBytesSync()), exitCode: null);
    } on FileSystemException catch (e) {
      logger.err('Cannot read the card file $path: ${e.message}');
      return (text: null, exitCode: ExitCode.noInput.code);
    }
  }

  int _invalidCard(String path, String field, String problem) {
    logger
      ..err('Invalid card file $path: RichMessage.$field: $problem')
      ..err(jsonEncode({'ok': false, 'error': 'invalid_card', 'field': field}));
    return ExitCode.data.code;
  }

  int _usageError(String message) {
    logger
      ..err(message)
      ..info('')
      ..info(usage);
    return ExitCode.usage.code;
  }
}
