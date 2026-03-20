import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:dart_slack/src/auth/credentials.dart';
import 'package:dart_slack/src/auth/credentials_store.dart';
import 'package:dart_slack/src/cli/commands/info_command.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockCredentialsStore extends Mock implements CredentialsStore {}

class _MockHttpClient extends Mock implements http.Client {}

void main() {
  group('InfoCommand', () {
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
          InfoCommand(
            logger: logger,
            credentialsStore: credentialsStore,
            httpClient: httpClient,
          ),
        );
    });

    test('has correct name and description', () {
      final command = InfoCommand(logger: logger);
      expect(command.name, equals('info'));
      expect(command.description, isNotEmpty);
    });

    test('displays channel details', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);
      when(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'ok': true,
            'channel': {
              'id': 'C1',
              'name': 'general',
              'is_private': false,
              'topic': {'value': 'Announcements'},
              'purpose': {'value': 'General chat'},
              'num_members': 42,
              'is_archived': false,
            },
          }),
          200,
        ),
      );

      await runner.run(['info', '-c', 'C1']);

      verify(() => logger.info('# general  (C1)')).called(1);
      verify(() => logger.info('  Topic: Announcements')).called(1);
      verify(() => logger.info('  Purpose: General chat')).called(1);
      verify(() => logger.info('  Members: 42')).called(1);
    });

    test('shows archived status', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);
      when(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'ok': true,
            'channel': {
              'id': 'C2',
              'name': 'old',
              'is_private': false,
              'is_archived': true,
              'num_members': 0,
            },
          }),
          200,
        ),
      );

      await runner.run(['info', '-c', 'C2']);

      verify(() => logger.info('  Archived: yes')).called(1);
    });
  });
}
