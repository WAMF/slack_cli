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
    String? cursor;
    var foundUsers = false;

    do {
      final page = await slack.usersList(cursor: cursor);

      for (final user in page.items) {
        foundUsers = true;
        final bot = user.isBot ? ' (bot)' : '';
        final deleted = user.isDeleted ? ' [deactivated]' : '';
        logger.info('${user.realName} @${user.name}$bot$deleted  (${user.id})');
      }

      cursor = page.nextCursor;
    } while (cursor != null);

    if (!foundUsers) {
      logger.info('No users found.');
    }

    return ExitCode.success.code;
  }
}
