import 'package:dart_slack/src/cli/commands/authenticated_command.dart';
import 'package:dart_slack/src/slack.dart';
import 'package:mason_logger/mason_logger.dart';

/// `dart_slack channels`
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
  Future<int> runAuthenticated(Slack slack) async {
    final channels = await slack.listChannels();

    if (channels.isEmpty) {
      logger.info('No channels found.');
      return ExitCode.success.code;
    }

    for (final channel in channels) {
      final prefix = channel.isPrivate ? '🔒' : '#';
      logger.info('$prefix ${channel.name}  (${channel.id})');
    }

    return ExitCode.success.code;
  }
}
