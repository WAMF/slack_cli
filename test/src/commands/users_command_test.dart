import 'dart:convert';

import 'package:dart_slack/src/auth/credentials.dart';
import 'package:dart_slack/src/auth/credentials_store.dart';
import 'package:dart_slack/src/cli/commands/users_command.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockCredentialsStore extends Mock implements CredentialsStore {}

class _MockHttpClient extends Mock implements http.Client {}

void main() {
  group('UsersCommand', () {
    late _MockLogger logger;
    late _MockCredentialsStore credentialsStore;
    late _MockHttpClient httpClient;
    late UsersCommand command;

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

      command = UsersCommand(
        logger: logger,
        credentialsStore: credentialsStore,
        httpClient: httpClient,
      );
    });

    test('has correct name and description', () {
      expect(command.name, equals('users'));
      expect(command.description, isNotEmpty);
    });

    test('lists users with roles', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);
      when(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'ok': true,
            'members': [
              {
                'id': 'U1',
                'name': 'jane',
                'real_name': 'Jane Doe',
                'is_bot': false,
                'deleted': false,
                'profile': {'display_name': 'Jane'},
              },
              {
                'id': 'U2',
                'name': 'bot',
                'real_name': 'Bot User',
                'is_bot': true,
                'deleted': false,
                'profile': {'display_name': 'Bot'},
              },
            ],
            'response_metadata': {'next_cursor': ''},
          }),
          200,
        ),
      );

      final result = await command.run();

      expect(result, equals(ExitCode.success.code));
      verify(
        () => logger.info('Jane Doe @jane  (U1)'),
      ).called(1);
      verify(
        () => logger.info('Bot User @bot (bot)  (U2)'),
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
            'members': <Map<String, dynamic>>[],
            'response_metadata': {'next_cursor': ''},
          }),
          200,
        ),
      );

      final result = await command.run();

      expect(result, equals(ExitCode.success.code));
      verify(() => logger.info('No users found.')).called(1);
    });
  });
}
