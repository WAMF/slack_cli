import 'package:args/command_runner.dart';
import 'package:dart_slack/src/auth/credentials_store.dart';
import 'package:dart_slack/src/auth/oauth_flow.dart';
import 'package:dart_slack/src/cli/slack_app.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';

/// `dart_slack login`
///
/// Authenticates with Slack via OAuth 2.0 and stores the access token.
class LoginCommand extends Command<int> {
  /// Creates a [LoginCommand].
  LoginCommand({
    required Logger logger,
    CredentialsStore? credentialsStore,
    OAuthFlow? oauthFlow,
    http.Client? httpClient,
  }) : _logger = logger,
       _credentialsStore = credentialsStore ?? CredentialsStore(),
       _oauthFlow = oauthFlow,
       _httpClient = httpClient;

  @override
  String get description => 'Authenticate with Slack via OAuth 2.0.';

  @override
  String get name => 'login';

  final Logger _logger;
  final CredentialsStore _credentialsStore;
  final OAuthFlow? _oauthFlow;
  final http.Client? _httpClient;

  @override
  Future<int> run() async {
    if (_credentialsStore.hasCredentials) {
      final credentials = _credentialsStore.load()!;
      final reauth = _logger.confirm(
        'Already logged in to ${credentials.teamName}. Re-authenticate?',
      );
      if (!reauth) return ExitCode.success.code;
    }

    final flow = _oauthFlow ??
        OAuthFlow(
          clientId: SlackApp.clientId,
          clientSecret: SlackApp.clientSecret,
          logger: _logger,
          httpClient: _httpClient,
        );

    try {
      final credentials = await flow.execute();
      _credentialsStore.save(credentials);
      _logger.success('Logged in to ${credentials.teamName}.');
      return ExitCode.success.code;
    } on OAuthException catch (e) {
      _logger.err('Authentication failed: ${e.message}');
      return ExitCode.software.code;
    }
  }
}
