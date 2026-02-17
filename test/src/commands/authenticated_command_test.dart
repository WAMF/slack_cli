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

class _TestCommand extends AuthenticatedCommand {
  _TestCommand({
    required super.logger,
    super.credentialsStore,
    super.httpClient,
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
      teamId: 'T123',
      teamName: 'Test Team',
      userId: 'U123',
    );

    setUp(() {
      logger = _MockLogger();
      credentialsStore = _MockCredentialsStore();
      httpClient = _MockHttpClient();

      when(() => logger.err(any())).thenReturn(null);
      when(() => httpClient.close()).thenReturn(null);
    });

    test('returns noUser exit code when no credentials exist', () async {
      when(() => credentialsStore.load()).thenReturn(null);

      final command = _TestCommand(
        logger: logger,
        credentialsStore: credentialsStore,
        httpClient: httpClient,
      );

      final result = await command.run();

      expect(result, equals(ExitCode.noUser.code));
      verify(
        () => logger.err("Not logged in. Run 'dart_slack login' first."),
      ).called(1);
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

    test('catches SlackApiException and returns software exit code',
        () async {
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

    test('catches SocketException and returns software exit code',
        () async {
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
