import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:dart_slack/src/auth/credentials.dart';
import 'package:dart_slack/src/auth/credentials_store.dart';
import 'package:dart_slack/src/cli/commands/members_command.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockCredentialsStore extends Mock implements CredentialsStore {}

class _MockHttpClient extends Mock implements http.Client {}

void main() {
  group('MembersCommand', () {
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
          MembersCommand(
            logger: logger,
            credentialsStore: credentialsStore,
            httpClient: httpClient,
          ),
        );
    });

    test('has correct name and description', () {
      final command = MembersCommand(logger: logger);
      expect(command.name, equals('members'));
      expect(command.description, isNotEmpty);
    });

    test('lists member IDs', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);
      when(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'ok': true,
            'members': ['U1', 'U2', 'U3'],
            'response_metadata': {'next_cursor': ''},
          }),
          200,
        ),
      );

      await runner.run(['members', '-c', 'C1']);

      verify(() => logger.info('U1')).called(1);
      verify(() => logger.info('U2')).called(1);
      verify(() => logger.info('U3')).called(1);
    });

    test('paginates through all channel members', () async {
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
              'members': ['U1', 'U2'],
              'response_metadata': {'next_cursor': 'page-2'},
            }),
            200,
          );
        }

        expect(cursor, equals('page-2'));
        return http.Response(
          jsonEncode({
            'ok': true,
            'members': ['U3'],
            'response_metadata': {'next_cursor': ''},
          }),
          200,
        );
      });

      await runner.run(['members', '-c', 'C1']);

      verify(() => logger.info('U1')).called(1);
      verify(() => logger.info('U2')).called(1);
      verify(() => logger.info('U3')).called(1);
      verify(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      ).called(2);
      verifyNever(() => logger.info('(more members available)'));
    });

    test('shows empty state message', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);
      when(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'ok': true,
            'members': <String>[],
            'response_metadata': {'next_cursor': ''},
          }),
          200,
        ),
      );

      await runner.run(['members', '-c', 'C1']);

      verify(() => logger.info('No members found.')).called(1);
    });
  });
}
