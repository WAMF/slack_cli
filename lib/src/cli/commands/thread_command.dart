import 'package:dart_slack/src/cli/commands/authenticated_command.dart';
import 'package:dart_slack/src/slack.dart';
import 'package:mason_logger/mason_logger.dart';

/// `dart_slack thread --channel <id> --ts <ts>`
///
/// Shows thread replies for a message.
class ThreadCommand extends AuthenticatedCommand {
  /// Creates a [ThreadCommand].
  ThreadCommand({
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
        'ts',
        help: 'The thread parent timestamp.',
        mandatory: true,
      );
  }

  @override
  String get description => 'Show replies in a message thread.';

  @override
  String get name => 'thread';

  @override
  Future<int> runAuthenticated(Slack slack) async {
    final channel = argResults!['channel'] as String;
    final ts = argResults!['ts'] as String;
    String? cursor;
    var foundReply = false;

    do {
      final page = await slack.conversationsReplies(
        channel: channel,
        ts: ts,
        cursor: cursor,
      );

      for (final message in page.items) {
        if (message.ts == ts) continue;

        foundReply = true;
        final user = message.user ?? 'unknown';
        logger.info('<$user> ${message.text}');
      }

      cursor = page.nextCursor;
    } while (cursor != null);

    if (!foundReply) {
      logger.info('No replies found.');
    }

    return ExitCode.success.code;
  }
}
