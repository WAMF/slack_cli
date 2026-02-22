import 'package:dart_slack/src/cli/commands/authenticated_command.dart';
import 'package:dart_slack/src/slack.dart';
import 'package:mason_logger/mason_logger.dart';

/// `dart_slack delete --channel <id> --ts <timestamp>`
///
/// Deletes a Slack message.
class DeleteCommand extends AuthenticatedCommand {
  /// Creates a [DeleteCommand].
  DeleteCommand({
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
        help: 'The message timestamp to delete.',
        mandatory: true,
      );
  }

  @override
  String get description => 'Delete a Slack message.';

  @override
  String get name => 'delete';

  @override
  Future<int> runAuthenticated(Slack slack) async {
    final channel = argResults!['channel'] as String;
    final ts = argResults!['ts'] as String;

    await slack.deleteMessage(channel: channel, ts: ts);
    logger.success('Message $ts in $channel deleted.');
    return ExitCode.success.code;
  }
}
