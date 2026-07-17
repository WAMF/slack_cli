import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:dart_slack/src/auth/credentials.dart';
import 'package:dart_slack/src/auth/credentials_store.dart';
import 'package:dart_slack/src/cli/commands/history_command.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockCredentialsStore extends Mock implements CredentialsStore {}

class _MockHttpClient extends Mock implements http.Client {}

void main() {
  group('HistoryCommand', () {
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
      when(() => httpClient.close()).thenReturn(null);

      runner = CommandRunner<int>('test', 'test')
        ..addCommand(
          HistoryCommand(
            logger: logger,
            credentialsStore: credentialsStore,
            httpClient: httpClient,
          ),
        );
    });

    test('has correct name and description', () {
      final command = HistoryCommand(logger: logger);
      expect(command.name, equals('history'));
      expect(command.description, isNotEmpty);
    });

    test('displays messages in chronological order', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);
      when(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'ok': true,
            'messages': [
              {'ts': '2.0', 'text': 'Second', 'user': 'U2'},
              {'ts': '1.0', 'text': 'First', 'user': 'U1'},
            ],
            'has_more': false,
          }),
          200,
        ),
      );

      await runner.run(['history', '-c', 'C1']);

      final logged = verify(() => logger.info(captureAny())).captured;
      expect(logged, contains('[1.0] <U1> First'));
      expect(logged, contains('[2.0] <U2> Second'));
      expect(
        logged.indexOf('[1.0] <U1> First'),
        lessThan(logged.indexOf('[2.0] <U2> Second')),
      );
    });

    test('shows thread reply count', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);
      when(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'ok': true,
            'messages': [
              {
                'ts': '1.0',
                'text': 'Thread parent',
                'user': 'U1',
                'reply_count': 5,
              },
            ],
            'has_more': false,
          }),
          200,
        ),
      );

      await runner.run(['history', '-c', 'C1']);

      verify(
        () => logger.info('[1.0] <U1> Thread parent [5 replies]'),
      ).called(1);
    });

    test('shows empty state message', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);
      when(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'ok': true,
            'messages': <Map<String, dynamic>>[],
            'has_more': false,
          }),
          200,
        ),
      );

      await runner.run(['history', '-c', 'C1']);

      verify(() => logger.info('No messages found.')).called(1);
    });

    test('rejects invalid limit values', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);
      when(() => logger.err(any())).thenReturn(null);

      final exitCode = await runner.run(['history', '-c', 'C1', '-l', '0']);

      expect(exitCode, equals(ExitCode.usage.code));
      verify(
        () => logger.err(
          'Invalid --limit value: "0". Use a positive integer.',
        ),
      ).called(1);
      verifyNever(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      );
    });
  });
}
