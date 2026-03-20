import 'package:dart_slack/src/cli/commands/authenticated_command.dart';
import 'package:dart_slack/src/slack.dart';
import 'package:mason_logger/mason_logger.dart';

/// `dart_slack members --channel <id>`
///
/// Lists member user IDs in a channel.
class MembersCommand extends AuthenticatedCommand {
  /// Creates a [MembersCommand].
  MembersCommand({
    required super.logger,
    super.credentialsStore,
    super.httpClient,
  }) {
    argParser.addOption(
      'channel',
      abbr: 'c',
      help: 'The channel ID to list members for.',
      mandatory: true,
    );
  }

  @override
  String get description => 'List members of a channel.';

  @override
  String get name => 'members';

  @override
  Future<int> runAuthenticated(Slack slack) async {
    final channel = argResults!['channel'] as String;
    String? cursor;
    var foundMembers = false;

    do {
      final page = await slack.conversationsMembers(
        channel: channel,
        cursor: cursor,
      );

      for (final member in page.items) {
        foundMembers = true;
        logger.info(member);
      }

      cursor = page.nextCursor;
    } while (cursor != null);

    if (!foundMembers) {
      logger.info('No members found.');
    }

    return ExitCode.success.code;
  }
}
