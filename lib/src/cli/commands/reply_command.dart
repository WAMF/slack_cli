import 'package:dart_slack/src/cli/commands/authenticated_command.dart';
import 'package:dart_slack/src/slack.dart';
import 'package:mason_logger/mason_logger.dart';

/// `dart_slack reply --channel <id> --thread <ts> --text "message"`
///
/// Replies to a message thread in a Slack channel.
class ReplyCommand extends AuthenticatedCommand {
  /// Creates a [ReplyCommand].
  ReplyCommand({
    required super.logger,
    super.credentialsStore,
    super.httpClient,
  }) {
    argParser
      ..addOption(
        'channel',
        abbr: 'c',
        help: 'The channel ID containing the thread.',
        mandatory: true,
      )
      ..addOption(
        'thread',
        abbr: 'r',
        help: 'The thread timestamp (thread_ts) to reply to.',
        mandatory: true,
      )
      ..addOption(
        'text',
        abbr: 't',
        help: 'The reply text.',
        mandatory: true,
      );
  }

  @override
  String get description => 'Reply to a message thread in a Slack channel.';

  @override
  String get name => 'reply';

  @override
  Future<int> runAuthenticated(Slack slack) async {
    final channel = argResults!['channel'] as String;
    final thread = argResults!['thread'] as String;
    final text = argResults!['text'] as String;

    final message = await slack.postMessage(
      channel: channel,
      text: text,
      threadTs: thread,
    );
    logger.success(
      'Reply sent to thread $thread in $channel (ts: ${message.ts}).',
    );
    return ExitCode.success.code;
  }
}
