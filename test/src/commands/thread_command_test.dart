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

      verify(() => logger.info('<U2> Reply')).called(1);
      verifyNever(() => logger.info('<U1> Parent'));
    });

    test(
      'paginates replies and omits the parent message on each page',
      () async {
        when(() => credentialsStore.load()).thenReturn(credentials);
        when(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer((invocation) async {
          final uri = invocation.positionalArguments.first as Uri;
          final cursor = uri.queryParameters['cursor'];

          if (cursor == null) {
            return http.Response(
              jsonEncode({
                'ok': true,
                'messages': [
                  {'ts': '1.0', 'text': 'Parent', 'user': 'U1'},
                  {'ts': '1.1', 'text': 'First reply', 'user': 'U2'},
                ],
                'has_more': true,
                'response_metadata': {'next_cursor': 'page-2'},
              }),
              200,
            );
          }

          expect(cursor, equals('page-2'));
          return http.Response(
            jsonEncode({
              'ok': true,
              'messages': [
                {'ts': '1.0', 'text': 'Parent duplicate', 'user': 'U1'},
                {'ts': '1.2', 'text': 'Second reply', 'user': 'U3'},
              ],
              'has_more': false,
              'response_metadata': {'next_cursor': ''},
            }),
            200,
          );
        });

        await runner.run(['thread', '-c', 'C1', '--ts', '1.0']);

        verify(() => logger.info('<U2> First reply')).called(1);
        verify(() => logger.info('<U3> Second reply')).called(1);
        verifyNever(() => logger.info('<U1> Parent'));
        verifyNever(() => logger.info('<U1> Parent duplicate'));
        verify(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).called(2);
      },
    );

    test(
      'shows empty state when thread only contains parent message',
      () async {
        when(() => credentialsStore.load()).thenReturn(credentials);
        when(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'messages': [
                {'ts': '1.0', 'text': 'Parent', 'user': 'U1'},
              ],
              'has_more': false,
            }),
            200,
          ),
        );

        await runner.run(['thread', '-c', 'C1', '--ts', '1.0']);

        verify(() => logger.info('No replies found.')).called(1);
        verifyNever(() => logger.info('<U1> Parent'));
      },
    );

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
