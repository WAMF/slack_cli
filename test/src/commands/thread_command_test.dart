import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:dart_slack/src/auth/credentials.dart';
import 'package:dart_slack/src/auth/credentials_store.dart';
import 'package:dart_slack/src/cli/commands/thread_command.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockCredentialsStore extends Mock implements CredentialsStore {}

class _MockHttpClient extends Mock implements http.Client {}

void main() {
  group('ThreadCommand', () {
    late _MockLogger logger;
    late _MockCredentialsStore credentialsStore;
    late _MockHttpClient httpClient;
    late CommandRunner<int> runner;

    const credentials = Credentials(
      accessToken: 'xoxp-test',
      teamId: 'T123',
      teamName: 'Test Team',
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
          ThreadCommand(
            logger: logger,
            credentialsStore: credentialsStore,
            httpClient: httpClient,
          ),
        );
    });

    test('has correct name and description', () {
      final command = ThreadCommand(logger: logger);
      expect(command.name, equals('thread'));
      expect(command.description, isNotEmpty);
    });

    test('displays thread replies', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);
      when(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'ok': true,
            'messages': [
              {'ts': '1.0', 'text': 'Parent', 'user': 'U1'},
              {'ts': '1.1', 'text': 'Reply', 'user': 'U2'},
            ],
            'has_more': false,
          }),
          200,
        ),
      );

      await runner.run(['thread', '-c', 'C1', '--ts', '1.0']);

      verify(() => logger.info('<U1> Parent')).called(1);
      verify(() => logger.info('<U2> Reply')).called(1);
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

      await runner.run(['thread', '-c', 'C1', '--ts', '1.0']);

      verify(() => logger.info('No replies found.')).called(1);
    });
  });
}
