import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_slack/src/auth/credentials.dart';
import 'package:dart_slack/src/auth/credentials_store.dart';
import 'package:dart_slack/src/slack.dart';
import 'package:dart_slack/src/slack_api/slack_api_client.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';

/// Environment variable consulted for a Slack token when no credentials
/// file is present.
const String _slackTokenEnvVar = 'SLACK_TOKEN';

/// Base class for commands that require Slack authentication.
///
/// Resolves a token from, in order, the [CredentialsStore] (written by
/// `dart_slack login`) and then the `SLACK_TOKEN` environment variable.
/// The environment fallback lets the CLI run in non-interactive contexts —
/// CI, containers, agent workspaces — where a token is injected rather
/// than obtained through an interactive login.
///
/// Creates a [Slack] facade and delegates to [runAuthenticated]. Handles
/// missing credentials and [SlackApiException] errors centrally.
abstract class AuthenticatedCommand extends Command<int> {
  /// Creates an [AuthenticatedCommand].
  AuthenticatedCommand({
    required this.logger,
    CredentialsStore? credentialsStore,
    this.httpClient,
    Map<String, String>? environment,
  }) : credentialsStore = credentialsStore ?? CredentialsStore(),
       environment = environment ?? Platform.environment;

  /// Logger for user-facing output.
  final Logger logger;

  /// Store for reading persisted credentials.
  final CredentialsStore credentialsStore;

  /// Optional HTTP client override for testing.
  final http.Client? httpClient;

  /// Environment used for the token fallback. Defaults to the process
  /// environment; injectable for testing.
  final Map<String, String> environment;

  @override
  Future<int> run() async {
    final credentials =
        credentialsStore.load() ?? _credentialsFromEnvironment();
    if (credentials == null) {
      logger.err(
        "Not logged in. Run 'dart_slack login' first, "
        'or set the $_slackTokenEnvVar environment variable.',
      );
      return ExitCode.noUser.code;
    }

    final slack = Slack(
      token: credentials.accessToken,
      httpClient: httpClient,
    );

    try {
      return await runAuthenticated(slack);
    } on SlackApiException catch (e) {
      logger.err('Slack API error: ${e.error}');
      if (e.needed != null) {
        logger.err(
          "Missing scope '${e.needed}'. "
          "Run 'dart_slack login' to re-authorize.",
        );
      }
      return ExitCode.software.code;
    } on SocketException catch (_) {
      logger.err('Network error: cannot reach the Slack API.');
      return ExitCode.software.code;
    } finally {
      slack.close();
    }
  }

  /// Subclasses implement this with their specific Slack API logic.
  Future<int> runAuthenticated(Slack slack);

  Credentials? _credentialsFromEnvironment() {
    final token = environment[_slackTokenEnvVar];
    if (token != null && token.isNotEmpty) {
      return Credentials(accessToken: token);
    }
    return null;
  }
}
