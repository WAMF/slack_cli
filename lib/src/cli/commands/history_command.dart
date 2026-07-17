import 'package:dart_slack/src/cli/commands/authenticated_command.dart';
import 'package:dart_slack/src/slack.dart';
import 'package:mason_logger/mason_logger.dart';

/// `dart_slack history --channel <id> [--limit <n>]`
///
/// Shows recent messages in a Slack channel.
class HistoryCommand extends AuthenticatedCommand {
  /// Creates a [HistoryCommand].
  HistoryCommand({
    required super.logger,
    super.credentialsStore,
    super.httpClient,
  }) {
    argParser
      ..addOption(
        'channel',
        abbr: 'c',
        help: 'The channel ID to fetch history from.',
        mandatory: true,
      )
      ..addOption(
        'limit',
        abbr: 'l',
        help: 'Maximum number of messages to show.',
        defaultsTo: '20',
      );
  }

  @override
  String get description => 'Show recent messages in a channel.';

  @override
  String get name => 'history';

  @override
  Future<int> runAuthenticated(Slack slack) async {
    final channel = argResults!['channel'] as String;
    final rawLimit = argResults!['limit'] as String;
    final limit = int.tryParse(rawLimit);
    if (limit == null || limit <= 0) {
      logger
        ..err('Invalid --limit value: "$rawLimit". Use a positive integer.')
        ..info('')
        ..info(usage);
      return ExitCode.usage.code;
    }

    final page = await slack.conversationsHistory(
      channel: channel,
      limit: limit,
    );

    if (page.items.isEmpty) {
      logger.info('No messages found.');
      return ExitCode.success.code;
    }

    for (final message in page.items.reversed) {
      final user = message.user ?? 'unknown';
      final thread = message.replyCount != null
          ? ' [${message.replyCount} replies]'
          : '';
      logger.info('[${message.ts}] <$user> ${message.text}$thread');
    }

    if (page.hasMore) {
      logger.info('(more messages available)');
    }

    return ExitCode.success.code;
  }
}
