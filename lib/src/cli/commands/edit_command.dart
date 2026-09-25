import 'package:dart_slack/src/cli/commands/authenticated_command.dart';
import 'package:dart_slack/src/cli/message_text_input.dart';
import 'package:dart_slack/src/slack.dart';
import 'package:mason_logger/mason_logger.dart';

/// `dart_slack edit --channel <id> --ts <timestamp> --text-file <path>`
///
/// The new text comes from exactly one of `--text`, `--text-file` or
/// `--text-stdin`.
///
/// Edits an existing Slack message.
class EditCommand extends AuthenticatedCommand with MessageTextCommand {
  /// Creates an [EditCommand].
  EditCommand({
    required super.logger,
    super.credentialsStore,
    super.httpClient,
  }) {
    argParser
      ..addOption(
        'channel',
        abbr: 'c',
        help: 'The channel ID containing the message.',
        mandatory: true,
      )
      ..addOption(
        'ts',
        help: 'The message timestamp to edit.',
        mandatory: true,
      );
    addMessageTextOptions(argParser, help: 'The new message text.');
  }

  @override
  String get description => 'Edit an existing Slack message.';

  @override
  String get name => 'edit';

  @override
  Future<int> runAuthenticated(Slack slack) async {
    final channel = argResults!['channel'] as String;
    final ts = argResults!['ts'] as String;

    await slack.updateMessage(channel: channel, ts: ts, text: messageText);
    logger.success('Message $ts in $channel updated.');
    return ExitCode.success.code;
  }
}
