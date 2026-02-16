import 'package:mason_logger/mason_logger.dart';
import 'package:slackcli/src/cli/commands/authenticated_command.dart';
import 'package:slackcli/src/slack_api/slack_api_client.dart';

/// `slackcli channels`
///
/// Lists Slack channels the authenticated user has access to.
class ChannelsCommand extends AuthenticatedCommand {
  /// Creates a [ChannelsCommand].
  ChannelsCommand({required super.logger});

  @override
  String get description =>
      'List channels you have access to.';

  @override
  String get name => 'channels';

  @override
  Future<int> runAuthenticated(SlackApiClient client) async {
    final channels = await client.listChannels();

    if (channels.isEmpty) {
      logger.info('No channels found.');
      return ExitCode.success.code;
    }

    for (final channel in channels) {
      final id = channel['id'] as String;
      final name = channel['name'] as String;
      final isPrivate = channel['is_private'] as bool? ?? false;
      final prefix = isPrivate ? '🔒' : '#';
      logger.info('$prefix $name  ($id)');
    }

    return ExitCode.success.code;
  }
}
