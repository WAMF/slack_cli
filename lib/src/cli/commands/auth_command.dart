import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:dart_slack/src/auth/credentials_store.dart';
import 'package:dart_slack/src/cli/commands/authenticated_command.dart';
import 'package:dart_slack/src/slack.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';

/// `dart_slack auth <test>`
///
/// Groups commands for inspecting and validating Slack authentication.
class AuthCommand extends Command<int> {
  /// Creates an [AuthCommand].
  AuthCommand({
    required Logger logger,
    CredentialsStore? credentialsStore,
    http.Client? httpClient,
  }) {
    addSubcommand(
      AuthTestCommand(
        logger: logger,
        credentialsStore: credentialsStore,
        httpClient: httpClient,
      ),
    );
  }

  @override
  String get description => 'Inspect and validate Slack authentication.';

  @override
  String get name => 'auth';
}

/// `dart_slack auth test`
///
/// Validates the current token via `auth.test` and prints identity
/// details. This gives a pre-flight health check that consumers can run
/// before sending, instead of inferring token health from the exit code of
/// an unrelated command like `channels`.
class AuthTestCommand extends AuthenticatedCommand {
  /// Creates an [AuthTestCommand].
  AuthTestCommand({
    required super.logger,
    super.credentialsStore,
    super.httpClient,
  });

  @override
  String get description =>
      'Validate the current token and print identity details.';

  @override
  String get name => 'test';

  @override
  Future<int> runAuthenticated(Slack slack) async {
    final identity = await slack.authTest();

    logger
      ..success(
        'Authenticated as ${identity.user} (${identity.userId}) on '
        '${identity.team} (${identity.teamId}).',
      )
      ..info(
        jsonEncode({
          'ok': true,
          'user': identity.user,
          'user_id': identity.userId,
          'team': identity.team,
          'team_id': identity.teamId,
        }),
      );

    return ExitCode.success.code;
  }
}
