import 'package:mason_logger/mason_logger.dart';
import 'package:slackcli/src/cli/commands/authenticated_command.dart';
import 'package:slackcli/src/slack_api/slack_api_client.dart';

/// `slackcli send --channel <id> --text "message"`
///
/// Posts a message to a Slack channel.
class SendCommand extends AuthenticatedCommand {
  /// Creates a [SendCommand].
  SendCommand({
    required super.logger,
    super.credentialsStore,
    super.httpClient,
  }) {
    argParser
      ..addOption(
        'channel',
        abbr: 'c',
        help: 'The channel ID to post to.',
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
  String get description => 'Post a message to a Slack channel.';

  @override
  String get name => 'send';

  @override
  Future<int> runAuthenticated(SlackApiClient client) async {
    final channel = argResults!['channel'] as String;
    final text = argResults!['text'] as String;

    await client.postMessage(channel: channel, text: text);
    logger.success('Message sent to $channel.');
    return ExitCode.success.code;
  }
}
