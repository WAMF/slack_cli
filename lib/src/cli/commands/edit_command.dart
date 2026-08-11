import 'package:dart_slack/src/cli/commands/authenticated_command.dart';
import 'package:dart_slack/src/cli/message_text.dart';
import 'package:dart_slack/src/slack.dart';
import 'package:mason_logger/mason_logger.dart';

/// `dart_slack edit --channel <id> --ts <timestamp> --text "new text"`
///
/// Edits an existing Slack message.
class EditCommand extends AuthenticatedCommand {
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
      )
      ..addOption(
        'text',
        abbr: 't',
        help: 'The new message text.',
        mandatory: true,
      );
  }

  @override
  String get description => 'Edit an existing Slack message.';

  @override
  String get name => 'edit';

  @override
  Future<int> runAuthenticated(Slack slack) async {
    final channel = argResults!['channel'] as String;
    final ts = argResults!['ts'] as String;
    final text = normalizeMessageText(argResults!['text'] as String);

    await slack.updateMessage(channel: channel, ts: ts, text: text);
    logger.success('Message $ts in $channel updated.');
    return ExitCode.success.code;
  }
}
