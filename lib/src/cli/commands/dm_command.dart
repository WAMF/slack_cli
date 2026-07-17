import 'package:dart_slack/src/cli/commands/authenticated_command.dart';
import 'package:dart_slack/src/slack.dart';
import 'package:mason_logger/mason_logger.dart';

/// `dart_slack dm --user <id> --text "message"`
///
/// Sends a direct message to a Slack user.
class DmCommand extends AuthenticatedCommand {
  /// Creates a [DmCommand].
  DmCommand({
    required super.logger,
    super.credentialsStore,
    super.httpClient,
  }) {
    argParser
      ..addOption(
        'user',
        abbr: 'u',
        help: 'The user ID to message.',
        mandatory: true,
      )
      ..addOption(
        'text',
        abbr: 't',
        help: 'The message text.',
        mandatory: true,
      );
  }

  @override
  String get description => 'Send a direct message to a Slack user.';

  @override
  String get name => 'dm';

  @override
  Future<int> runAuthenticated(Slack slack) async {
    final user = argResults!['user'] as String;
    final text = argResults!['text'] as String;

    final message = await slack.postMessage(channel: user, text: text);
    logger.success('DM sent to $user (ts: ${message.ts}).');
    return ExitCode.success.code;
  }
}
