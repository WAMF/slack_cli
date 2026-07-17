import 'package:dart_slack/src/cli/commands/authenticated_command.dart';
import 'package:dart_slack/src/slack.dart';
import 'package:mason_logger/mason_logger.dart';

/// `dart_slack info --channel <id>`
///
/// Shows detailed information about a channel.
class InfoCommand extends AuthenticatedCommand {
  /// Creates an [InfoCommand].
  InfoCommand({
    required super.logger,
    super.credentialsStore,
    super.httpClient,
  }) {
    argParser.addOption(
      'channel',
      abbr: 'c',
      help: 'The channel ID to get info for.',
      mandatory: true,
    );
  }

  @override
  String get description => 'Show details about a channel.';

  @override
  String get name => 'info';

  @override
  Future<int> runAuthenticated(Slack slack) async {
    final channelId = argResults!['channel'] as String;
    final channel = await slack.conversationsInfo(channel: channelId);
    final memberCount = await _countMembers(slack, channelId);

    final prefix = channel.isPrivate ? '\u{1F512}' : '#';
    logger.info('$prefix ${channel.name}  (${channel.id})');
    if (channel.topic.isNotEmpty) {
      logger.info('  Topic: ${channel.topic}');
    }
    if (channel.purpose.isNotEmpty) {
      logger.info('  Purpose: ${channel.purpose}');
    }
    logger.info('  Members: $memberCount');
    if (channel.isArchived) {
      logger.info('  Archived: yes');
    }

    return ExitCode.success.code;
  }

  /// Counts channel members by paginating `conversations.members` — the
  /// same call `dart_slack members` uses. `conversations.info`'s
  /// `num_members` field is frequently stale or unpopulated (it reported
  /// `0` for channels that demonstrably have members), so `info` counts the
  /// same way `members` lists, keeping the two commands consistent.
  Future<int> _countMembers(Slack slack, String channelId) async {
    var count = 0;
    String? cursor;

    while (true) {
      final page = await slack.conversationsMembers(
        channel: channelId,
        limit: 1000,
        cursor: cursor,
      );
      count += page.items.length;
      if (!page.hasMore) break;
      cursor = page.nextCursor;
    }

    return count;
  }
}
