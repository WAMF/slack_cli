import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:dart_slack/src/auth/credentials.dart';
import 'package:dart_slack/src/auth/credentials_store.dart';
import 'package:dart_slack/src/cli/commands/auth_command.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockCredentialsStore extends Mock implements CredentialsStore {}

class _MockHttpClient extends Mock implements http.Client {}

void main() {
  group('AuthCommand', () {
    late _MockLogger logger;
    late _MockCredentialsStore credentialsStore;
    late _MockHttpClient httpClient;
    late CommandRunner<int> runner;

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

      when(() => logger.info(any())).thenReturn(null);
      when(() => logger.err(any())).thenReturn(null);
      when(() => logger.success(any())).thenReturn(null);
      when(() => httpClient.close()).thenReturn(null);
      when(() => credentialsStore.load()).thenReturn(credentials);

      runner = CommandRunner<int>('test', 'test')
        ..addCommand(
          AuthCommand(
            logger: logger,
            credentialsStore: credentialsStore,
            httpClient: httpClient,
          ),
        );
    });

    test('has correct name and description', () {
      final command = AuthCommand(logger: logger);
      expect(command.name, equals('auth'));
      expect(command.description, isNotEmpty);
      expect(command.subcommands.keys, contains('test'));
    });

    group('test', () {
      test('prints identity and a success JSON line, exits 0', () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'team': 'WAAF',
              'team_id': 'T123',
              'user': 'clayton',
              'user_id': 'U123',
            }),
            200,
          ),
        );

        final exitCode = await runner.run(['auth', 'test']);

        expect(exitCode, equals(ExitCode.success.code));
        verify(
          () => logger.success(
            'Authenticated as clayton (U123) on WAAF (T123).',
          ),
        ).called(1);
        verify(
          () => logger.info(
            jsonEncode({
              'ok': true,
              'user': 'clayton',
              'user_id': 'U123',
              'team': 'WAAF',
              'team_id': 'T123',
            }),
          ),
        ).called(1);
      });

      test(
        'exits non-zero and reports structured JSON on invalid_auth',
        () async {
          // Regression for #23: a dead/revoked token must fail loudly
          // (non-zero exit + JSON) rather than silently succeeding.
          when(
            () => httpClient.post(
              any(),
              headers: any(named: 'headers'),
              body: any(named: 'body'),
            ),
          ).thenAnswer(
            (_) async => http.Response(
              jsonEncode({'ok': false, 'error': 'invalid_auth'}),
              200,
            ),
          );

          final exitCode = await runner.run(['auth', 'test']);

          expect(exitCode, isNot(equals(ExitCode.success.code)));
          verify(
            () => logger.err(
              jsonEncode({'ok': false, 'error': 'invalid_auth'}),
            ),
          ).called(1);
        },
      );
    });
  });
}
