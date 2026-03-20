import 'package:dart_slack/src/cli/commands/authenticated_command.dart';
import 'package:dart_slack/src/slack.dart';
import 'package:mason_logger/mason_logger.dart';

/// `dart_slack whois --user <id>`
///
/// Shows profile details for a user.
class WhoisCommand extends AuthenticatedCommand {
  /// Creates a [WhoisCommand].
  WhoisCommand({
    required super.logger,
    super.credentialsStore,
    super.httpClient,
  }) {
    argParser.addOption(
      'user',
      abbr: 'u',
      help: 'The user ID to look up.',
      mandatory: true,
    );
  }

  @override
  String get description => 'Show profile details for a user.';

  @override
  String get name => 'whois';

  @override
  Future<int> runAuthenticated(Slack slack) async {
    final userId = argResults!['user'] as String;
    final user = await slack.usersInfo(user: userId);

    logger.info('${user.realName} (@${user.name})');
    if (user.displayName.isNotEmpty) {
      logger.info('  Display name: ${user.displayName}');
    }
    if (user.email != null) {
      logger.info('  Email: ${user.email}');
    }
    if (user.isBot) {
      logger.info('  Bot: yes');
    }
    if (user.isDeleted) {
      logger.info('  Deactivated: yes');
    }

    return ExitCode.success.code;
  }
}
