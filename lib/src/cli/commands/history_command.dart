import 'package:dart_slack/src/cli/commands/authenticated_command.dart';
import 'package:dart_slack/src/models/slack_message.dart';
import 'package:dart_slack/src/slack.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';

/// `dart_slack history --channel <id> [--limit <n> | --all] [--cursor <c>]`
/// `[--oldest <ts>] [--latest <ts>]`
///
/// Shows messages in a Slack channel. The command follows Slack's
/// `next_cursor` until it has `--limit` messages, the channel (or the
/// `--oldest`/`--latest` range) has no more messages, or the safety limit
/// is reached. It always ends with a summary line that gives the number of
/// messages returned and, when more exist, the cursor for the next request.
class HistoryCommand extends AuthenticatedCommand {
  /// Creates a [HistoryCommand].
  new({required super.logger, super.credentialsStore, super.httpClient}) {
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
        help:
            'Maximum number of messages to show. Values above one Slack '
            'page ($pageSize) are filled by following cursors.',
        defaultsTo: '20',
      )
      ..addFlag(
        'all',
        negatable: false,
        help:
            'Follow cursors until no more messages exist, or until the '
            'safety limit of $safetyLimit messages. Cannot be used with '
            '--limit.',
      )
      ..addOption(
        'cursor',
        help:
            'Start from this cursor. Use the cursor that a previous '
            '`history` run printed.',
      )
      ..addOption(
        'oldest',
        help:
            'Only messages after this Slack timestamp (for example '
            '1730000000.000100).',
      )
      ..addOption('latest', help: 'Only messages before this Slack timestamp.');
  }

  /// The number of messages asked for in one `conversations.history`
  /// request. Slack recommends no more than 200.
  @visibleForTesting
  static const pageSize = 200;

  /// The most messages one run reads. It also bounds `--limit` and the
  /// number of requests when Slack returns empty pages with a cursor.
  @visibleForTesting
  static const safetyLimit = 10000;

  /// The most requests one run makes.
  @visibleForTesting
  static const int maxPages = safetyLimit ~/ pageSize;

  @override
  String get description => 'Show messages in a channel, with pagination.';

  @override
  String get name => 'history';

  @override
  Future<int> runAuthenticated(Slack slack) async {
    final args = argResults!;
    final channel = args['channel'] as String;
    final all = args['all'] as bool;
    final rawLimit = args['limit'] as String;
    final cursor = _nonEmpty(args['cursor'] as String?);
    final oldest = _nonEmpty(args['oldest'] as String?);
    final latest = _nonEmpty(args['latest'] as String?);

    if (all && args.wasParsed('limit')) {
      return _usageError('Use either --all or --limit, not both.');
    }

    final limit = all ? safetyLimit : int.tryParse(rawLimit);
    if (limit == null || limit <= 0) {
      return _usageError(
        'Invalid --limit value: "$rawLimit". Use a positive integer.',
      );
    }
    if (limit > safetyLimit) {
      return _usageError(
        'Invalid --limit value: "$rawLimit". The maximum is $safetyLimit; '
        'use --cursor to read further.',
      );
    }
    for (final (option, value) in [('oldest', oldest), ('latest', latest)]) {
      if (value != null && double.tryParse(value) == null) {
        return _usageError(
          'Invalid --$option value: "$value". Use a Slack timestamp such '
          'as 1730000000.000100.',
        );
      }
    }

    final messages = <SlackMessage>[];
    var nextCursor = cursor;
    var hasMore = false;
    var pages = 0;

    while (true) {
      final page = await slack.conversationsHistory(
        channel: channel,
        limit: _min(limit - messages.length, pageSize),
        cursor: nextCursor,
        oldest: oldest,
        latest: latest,
      );
      pages++;
      messages.addAll(page.items);
      hasMore = page.hasMore;
      nextCursor = page.hasMore ? _nonEmpty(page.nextCursor) : null;

      if (nextCursor == null) break;
      if (messages.length >= limit) break;
      if (pages >= maxPages) break;
    }

    if (messages.isEmpty) {
      logger.info('No messages found.');
    }

    // Slack returns newest first; print the oldest first.
    for (final message in messages.reversed) {
      final user = message.user ?? 'unknown';
      final thread = message.replyCount != null
          ? ' [${message.replyCount} replies]'
          : '';
      logger.info(
        '[${message.ts}] <$user> ${message.text}'
        '${message.attachmentSuffix}$thread',
      );
    }

    logger.info(
      _summary(
        count: messages.length,
        hasMore: hasMore,
        nextCursor: nextCursor,
        stoppedBy: _stopReason(
          all: all,
          limit: limit,
          count: messages.length,
          pages: pages,
          nextCursor: nextCursor,
        ),
      ),
    );

    return ExitCode.success.code;
  }

  String? _stopReason({
    required bool all,
    required int limit,
    required int count,
    required int pages,
    required String? nextCursor,
  }) {
    if (nextCursor == null) return null;
    if (all) {
      return count >= safetyLimit
          ? 'stopped at the --all safety limit of $safetyLimit messages'
          : 'stopped at the --all safety limit of $maxPages requests';
    }
    if (count >= limit) return 'stopped at --limit $limit';
    return 'stopped at the safety limit of $maxPages requests';
  }

  static String _summary({
    required int count,
    required bool hasMore,
    required String? nextCursor,
    required String? stoppedBy,
  }) {
    final noun = count == 1 ? 'message' : 'messages';
    final parts = <String>['$count $noun returned'];
    if (stoppedBy != null) parts.add(stoppedBy);
    if (nextCursor != null) {
      parts.add('more messages available: use --cursor $nextCursor');
    } else if (hasMore) {
      parts.add('more messages available, but Slack returned no cursor');
    } else {
      parts.add('no more messages');
    }
    return '(${parts.join('; ')})';
  }

  int _usageError(String message) {
    logger
      ..err(message)
      ..info('')
      ..info(usage);
    return ExitCode.usage.code;
  }

  static int _min(int a, int b) => a < b ? a : b;

  static String? _nonEmpty(String? value) =>
      value == null || value.isEmpty ? null : value;
}
