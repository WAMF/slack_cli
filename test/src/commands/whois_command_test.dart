import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:dart_slack/src/auth/credentials.dart';
import 'package:dart_slack/src/auth/credentials_store.dart';
import 'package:dart_slack/src/cli/commands/whois_command.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockCredentialsStore extends Mock implements CredentialsStore {}

class _MockHttpClient extends Mock implements http.Client {}

void main() {
  group('WhoisCommand', () {
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
          WhoisCommand(
            logger: logger,
            credentialsStore: credentialsStore,
            httpClient: httpClient,
          ),
        );
    });

    test('has correct name and description', () {
      final command = WhoisCommand(logger: logger);
      expect(command.name, equals('whois'));
      expect(command.description, isNotEmpty);
    });

    test('displays user profile', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);
      when(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'ok': true,
            'user': {
              'id': 'U1',
              'name': 'jane',
              'real_name': 'Jane Doe',
              'is_bot': false,
              'deleted': false,
              'profile': {
                'display_name': 'Jane',
                'email': 'jane@example.com',
              },
            },
          }),
          200,
        ),
      );

      await runner.run(['whois', '-u', 'U1']);

      verify(() => logger.info('Jane Doe (@jane)')).called(1);
      verify(() => logger.info('  Display name: Jane')).called(1);
      verify(
        () => logger.info('  Email: jane@example.com'),
      ).called(1);
    });

    test('shows bot and deactivated flags', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);
      when(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'ok': true,
            'user': {
              'id': 'U2',
              'name': 'oldbot',
              'real_name': 'Old Bot',
              'is_bot': true,
              'deleted': true,
              'profile': {'display_name': ''},
            },
          }),
          200,
        ),
      );

      await runner.run(['whois', '-u', 'U2']);

      verify(() => logger.info('Old Bot (@oldbot)')).called(1);
      verify(() => logger.info('  Bot: yes')).called(1);
      verify(() => logger.info('  Deactivated: yes')).called(1);
    });
  });
}
