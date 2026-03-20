import 'package:dart_slack/src/cli/commands/authenticated_command.dart';
import 'package:dart_slack/src/slack.dart';
import 'package:mason_logger/mason_logger.dart';

/// `dart_slack users`
///
/// Lists workspace users.
class UsersCommand extends AuthenticatedCommand {
  /// Creates a [UsersCommand].
  UsersCommand({
    required super.logger,
    super.credentialsStore,
    super.httpClient,
  });

  @override
  String get description => 'List workspace users.';

  @override
  String get name => 'users';

  @override
  Future<int> runAuthenticated(Slack slack) async {
    final page = await slack.usersList();

    if (page.items.isEmpty) {
      logger.info('No users found.');
      return ExitCode.success.code;
    }

    for (final user in page.items) {
      final bot = user.isBot ? ' (bot)' : '';
      final deleted = user.isDeleted ? ' [deactivated]' : '';
      logger.info('${user.realName} @${user.name}$bot$deleted  (${user.id})');
    }

    if (page.hasMore) {
      logger.info('(more users available)');
    }

    return ExitCode.success.code;
  }
}
