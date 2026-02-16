import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:slackcli/src/auth/credentials.dart';
import 'package:slackcli/src/slack_api/slack_scopes.dart';
import 'package:slackcli/src/slack_api/slack_urls.dart';

/// The port on which the local OAuth callback server listens.
const int _callbackPort = 8585;

/// The path segment of the OAuth redirect URI.
const String _callbackPath = '/callback';

/// Maximum time to wait for the user to authorize in the browser.
const Duration _authTimeout = Duration(minutes: 5);

/// Thrown when the OAuth authorization flow fails.
class OAuthException implements Exception {
  /// Creates an [OAuthException] with the given [message].
  const OAuthException(this.message);

  /// A human-readable description of the failure.
  final String message;

  @override
  String toString() => 'OAuthException: $message';
}

/// Performs the Slack OAuth 2.0 V2 authorization flow over HTTPS.
///
/// 1. Ensures a self-signed TLS certificate exists in the config directory.
/// 2. Starts a local HTTPS server to receive the redirect callback.
/// 3. Opens the user's browser to the Slack authorize URL.
/// 4. Receives the redirect callback with the authorization code.
/// 5. Exchanges the code for an access token via the Slack API.
class OAuthFlow {
  /// Creates an [OAuthFlow].
  ///
  /// The [processStarter] parameter exists for testability — override it
  /// to prevent a real browser from opening during tests.
  ///
  /// The [configDirectory] is where the self-signed TLS certificate and
  /// key are stored. Defaults to `~/.slackcli`.
  OAuthFlow({
    required String clientId,
    required String clientSecret,
    required Logger logger,
    http.Client? httpClient,
    Future<Process> Function(String, List<String>)? processStarter,
    Directory? configDirectory,
  }) : _clientId = clientId,
       _clientSecret = clientSecret,
       _logger = logger,
       _httpClient = httpClient ?? http.Client(),
       _processStarter = processStarter ?? Process.start,
       _configDirectory =
           configDirectory ??
           Directory('${Platform.environment['HOME']}/.slackcli');

  final String _clientId;
  final String _clientSecret;
  final Logger _logger;
  final http.Client _httpClient;
  final Future<Process> Function(String, List<String>) _processStarter;
  final Directory _configDirectory;

  File get _certFile => File('${_configDirectory.path}/cert.pem');
  File get _keyFile => File('${_configDirectory.path}/key.pem');

  /// Runs the full OAuth flow and returns [Credentials] on success.
  Future<Credentials> execute() async {
    _ensureCertificate();

    final context = SecurityContext()
      ..useCertificateChain(_certFile.path)
      ..usePrivateKey(_keyFile.path);

    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      _callbackPort,
      context,
    );
    const redirectUri =
        'https://localhost:$_callbackPort$_callbackPath';

    try {
      final authorizeUrl = SlackUrls.authorize.replace(
        queryParameters: {
          'client_id': _clientId,
          'user_scope': SlackScopes.joined,
          'redirect_uri': redirectUri,
          'response_type': 'code',
        },
      );

      _logger.info('Opening browser for Slack authorization...');
      await _openBrowser(authorizeUrl.toString());
      _logger.info('Waiting for authorization callback...');

      final code = await _waitForCallback(server);
      return _exchangeCodeForToken(
        code: code,
        redirectUri: redirectUri,
      );
    } finally {
      await server.close();
    }
  }

  void _ensureCertificate() {
    if (_certFile.existsSync() && _keyFile.existsSync()) return;

    _configDirectory.createSync(recursive: true);

    final result = Process.runSync('openssl', [
      'req',
      '-x509',
      '-newkey',
      'rsa:2048',
      '-keyout',
      _keyFile.path,
      '-out',
      _certFile.path,
      '-days',
      '3650',
      '-nodes',
      '-subj',
      '/CN=localhost',
    ]);

    if (result.exitCode != 0) {
      throw OAuthException(
        'Failed to generate TLS certificate: ${result.stderr}',
      );
    }

    if (Platform.isMacOS || Platform.isLinux) {
      Process.runSync('chmod', ['600', _keyFile.path]);
      Process.runSync('chmod', ['600', _certFile.path]);
    }
  }

  Future<void> _openBrowser(String url) async {
    final String command;
    if (Platform.isMacOS) {
      command = 'open';
    } else if (Platform.isLinux) {
      command = 'xdg-open';
    } else {
      _logger.info('Open this URL in your browser:\n$url');
      return;
    }
    await _processStarter(command, [url]);
  }

  Future<String> _waitForCallback(HttpServer server) async {
    final completer = Completer<String>();

    final subscription = server.listen((request) {
      if (request.uri.path != _callbackPath) {
        request.response.statusCode = HttpStatus.notFound;
        unawaited(request.response.close());
        return;
      }

      final code = request.uri.queryParameters['code'];
      final error = request.uri.queryParameters['error'];

      if (error != null) {
        _respondWithHtml(
          request.response,
          'Authorization failed: $error',
        );
        completer.completeError(OAuthException(error));
      } else if (code != null) {
        _respondWithHtml(
          request.response,
          'Authorization successful! You can close this tab.',
        );
        completer.complete(code);
      } else {
        _respondWithHtml(
          request.response,
          'Unexpected callback — missing code parameter.',
        );
        completer.completeError(
          const OAuthException(
            'Missing authorization code in callback',
          ),
        );
      }
    });

    try {
      return await completer.future.timeout(
        _authTimeout,
        onTimeout: () => throw const OAuthException(
          'Authorization timed out after 5 minutes',
        ),
      );
    } finally {
      await subscription.cancel();
    }
  }

  void _respondWithHtml(HttpResponse response, String body) {
    response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.html
      ..write(
        '<html><body style="font-family:sans-serif;text-align:center;'
        ' padding:40px"><h2>$body</h2></body></html>',
      );
    unawaited(response.close());
  }

  Future<Credentials> _exchangeCodeForToken({
    required String code,
    required String redirectUri,
  }) async {
    final response = await _httpClient.post(
      SlackUrls.tokenExchange,
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'client_id': _clientId,
        'client_secret': _clientSecret,
        'code': code,
        'redirect_uri': redirectUri,
      },
    );

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw OAuthException(
        'Token exchange failed: ${json['error']}',
      );
    }

    final team = json['team'] as Map<String, dynamic>;
    final authedUser =
        json['authed_user'] as Map<String, dynamic>;

    return Credentials(
      accessToken: authedUser['access_token'] as String,
      teamId: team['id'] as String,
      teamName: team['name'] as String,
      userId: authedUser['id'] as String?,
    );
  }
}
