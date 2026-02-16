import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_slack/src/auth/credentials_store.dart';
import 'package:dart_slack/src/slack.dart';
import 'package:dart_slack/src/slack_api/slack_api_client.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';

/// Base class for commands that require Slack authentication.
///
/// Loads credentials from [CredentialsStore], creates a [Slack] facade,
/// and delegates to [runAuthenticated]. Handles missing credentials and
/// [SlackApiException] errors centrally.
abstract class AuthenticatedCommand extends Command<int> {
  /// Creates an [AuthenticatedCommand].
  AuthenticatedCommand({
    required this.logger,
    CredentialsStore? credentialsStore,
    this.httpClient,
  }) : credentialsStore = credentialsStore ?? CredentialsStore();

  /// Logger for user-facing output.
  final Logger logger;

  /// Store for reading persisted credentials.
  final CredentialsStore credentialsStore;

  /// Optional HTTP client override for testing.
  final http.Client? httpClient;

  @override
  Future<int> run() async {
    final credentials = credentialsStore.load();
    if (credentials == null) {
      logger.err("Not logged in. Run 'dart_slack login' first.");
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
}
