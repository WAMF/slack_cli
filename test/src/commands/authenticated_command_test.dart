import 'dart:convert';
import 'dart:io';

import 'package:dart_slack/src/auth/credentials.dart';
import 'package:dart_slack/src/auth/credentials_store.dart';
import 'package:dart_slack/src/cli/commands/authenticated_command.dart';
import 'package:dart_slack/src/slack.dart';
import 'package:dart_slack/src/slack_api/slack_api_client.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockCredentialsStore extends Mock implements CredentialsStore {}

class _MockHttpClient extends Mock implements http.Client {}

/// Issues one Slack request so the token reaches the mock HTTP client,
/// where [_capturedBearerToken] can read it from the `Authorization`
/// header.
Future<int> _probeToken(Slack slack) async {
  await slack.listChannels();
  return ExitCode.success.code;
}

/// Pulls the bearer token out of the `Authorization` header captured by
/// the mock HTTP client's most recent `get` call.
String _capturedBearerToken(_MockHttpClient httpClient) {
  final headers =
      verify(
            () => httpClient.get(any(), headers: captureAny(named: 'headers')),
          ).captured.last
          as Map<String, String>;
  return headers['Authorization']!.replaceFirst('Bearer ', '');
}

class _TestCommand extends AuthenticatedCommand {
  _TestCommand({
    required super.logger,
    super.credentialsStore,
    super.httpClient,
    super.environment,
    this.onRun,
  });

  final Future<int> Function(Slack slack)? onRun;

  @override
  String get description => 'Test command';

  @override
  String get name => 'test-cmd';

  @override
  Future<int> runAuthenticated(Slack slack) async {
    return onRun?.call(slack) ?? ExitCode.success.code;
  }
}

void main() {
  group('AuthenticatedCommand', () {
    late _MockLogger logger;
    late _MockCredentialsStore credentialsStore;
    late _MockHttpClient httpClient;

    const credentials = Credentials(
      accessToken: 'xoxp-test',
      userId: 'U123',
    );

    setUpAll(() {
      registerFallbackValue(Uri.parse('https://example.com'));
    });

    setUp(() {
      logger = _MockLogger();
      credentialsStore = _MockCredentialsStore();
      httpClient = _MockHttpClient();

      when(() => logger.err(any())).thenReturn(null);
      when(() => httpClient.close()).thenReturn(null);
      when(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'ok': true,
            'channels': <dynamic>[],
            'response_metadata': {'next_cursor': ''},
          }),
          200,
        ),
      );
    });

    test('returns noUser exit code when no credentials exist', () async {
      when(() => credentialsStore.load()).thenReturn(null);

      final command = _TestCommand(
        logger: logger,
        credentialsStore: credentialsStore,
        httpClient: httpClient,
        environment: const {},
      );

      final result = await command.run();

      expect(result, equals(ExitCode.noUser.code));
      verify(
        () => logger.err(
          "Not logged in. Run 'dart_slack login' first, "
          'or set the SLACK_TOKEN environment variable.',
        ),
      ).called(1);
    });

    test('falls back to SLACK_TOKEN when no credentials file exists', () async {
      when(() => credentialsStore.load()).thenReturn(null);

      final command = _TestCommand(
        logger: logger,
        credentialsStore: credentialsStore,
        httpClient: httpClient,
        environment: const {'SLACK_TOKEN': 'xoxp-from-env'},
        onRun: _probeToken,
      );

      final result = await command.run();

      expect(result, equals(ExitCode.success.code));
      expect(_capturedBearerToken(httpClient), equals('xoxp-from-env'));
    });

    test('credentials file takes precedence over the environment', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);

      final command = _TestCommand(
        logger: logger,
        credentialsStore: credentialsStore,
        httpClient: httpClient,
        environment: const {'SLACK_TOKEN': 'xoxp-from-env'},
        onRun: _probeToken,
      );

      final result = await command.run();

      expect(result, equals(ExitCode.success.code));
      expect(_capturedBearerToken(httpClient), equals('xoxp-test'));
    });

    test('ignores an empty token environment variable', () async {
      when(() => credentialsStore.load()).thenReturn(null);

      final command = _TestCommand(
        logger: logger,
        credentialsStore: credentialsStore,
        httpClient: httpClient,
        environment: const {'SLACK_TOKEN': ''},
      );

      final result = await command.run();

      expect(result, equals(ExitCode.noUser.code));
    });

    test('ignores a whitespace-only token environment variable', () async {
      when(() => credentialsStore.load()).thenReturn(null);

      final command = _TestCommand(
        logger: logger,
        credentialsStore: credentialsStore,
        httpClient: httpClient,
        environment: const {'SLACK_TOKEN': '   '},
      );

      final result = await command.run();

      expect(result, equals(ExitCode.noUser.code));
    });

    test('trims surrounding whitespace from the token', () async {
      when(() => credentialsStore.load()).thenReturn(null);

      final command = _TestCommand(
        logger: logger,
        credentialsStore: credentialsStore,
        httpClient: httpClient,
        environment: const {'SLACK_TOKEN': '  xoxp-padded\n'},
        onRun: _probeToken,
      );

      final result = await command.run();

      expect(result, equals(ExitCode.success.code));
      expect(_capturedBearerToken(httpClient), equals('xoxp-padded'));
    });

    test('calls runAuthenticated when credentials exist', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);

      var wasInvoked = false;
      final command = _TestCommand(
        logger: logger,
        credentialsStore: credentialsStore,
        httpClient: httpClient,
        onRun: (slack) async {
          wasInvoked = true;
          return ExitCode.success.code;
        },
      );

      final result = await command.run();

      expect(result, equals(ExitCode.success.code));
      expect(wasInvoked, isTrue);
    });

    test('catches SlackApiException and returns software exit code', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);

      final command = _TestCommand(
        logger: logger,
        credentialsStore: credentialsStore,
        httpClient: httpClient,
        onRun: (_) => throw const SlackApiException('invalid_auth'),
      );

      final result = await command.run();

      expect(result, equals(ExitCode.software.code));
      verify(
        () => logger.err('Slack API error: invalid_auth'),
      ).called(1);
    });

    test('catches SocketException and returns software exit code', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);

      final command = _TestCommand(
        logger: logger,
        credentialsStore: credentialsStore,
        httpClient: httpClient,
        onRun: (_) => throw const SocketException('Connection refused'),
      );

      final result = await command.run();

      expect(result, equals(ExitCode.software.code));
      verify(
        () => logger.err('Network error: cannot reach the Slack API.'),
      ).called(1);
    });

    test('shows needed scope on missing_scope error', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);

      final command = _TestCommand(
        logger: logger,
        credentialsStore: credentialsStore,
        httpClient: httpClient,
        onRun: (_) => throw const SlackApiException(
          'missing_scope',
          needed: 'channels:history',
        ),
      );

      final result = await command.run();

      expect(result, equals(ExitCode.software.code));
      verify(
        () => logger.err('Slack API error: missing_scope'),
      ).called(1);
      verify(
        () => logger.err(
          "Missing scope 'channels:history'. "
          "Run 'dart_slack login' to re-authorize.",
        ),
      ).called(1);
    });

    test('closes Slack client after successful execution', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);

      final command = _TestCommand(
        logger: logger,
        credentialsStore: credentialsStore,
        httpClient: httpClient,
      );

      await command.run();

      verify(() => httpClient.close()).called(1);
    });

    test('closes Slack client after exception', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);

      final command = _TestCommand(
        logger: logger,
        credentialsStore: credentialsStore,
        httpClient: httpClient,
        onRun: (_) => throw const SlackApiException('some_error'),
      );

      await command.run();

      verify(() => httpClient.close()).called(1);
    });
  });
}
