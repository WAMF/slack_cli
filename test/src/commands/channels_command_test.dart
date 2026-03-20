import 'dart:convert';

import 'package:dart_slack/src/auth/credentials.dart';
import 'package:dart_slack/src/auth/credentials_store.dart';
import 'package:dart_slack/src/cli/commands/channels_command.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockCredentialsStore extends Mock implements CredentialsStore {}

class _MockHttpClient extends Mock implements http.Client {}

void main() {
  group('ChannelsCommand', () {
    late _MockLogger logger;
    late _MockCredentialsStore credentialsStore;
    late _MockHttpClient httpClient;
    late ChannelsCommand command;

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

      command = ChannelsCommand(
        logger: logger,
        credentialsStore: credentialsStore,
        httpClient: httpClient,
      );
    });

    test('has correct name and description', () {
      expect(command.name, equals('channels'));
      expect(command.description, isNotEmpty);
    });

    test('lists channels with correct prefixes', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);
      when(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'ok': true,
            'channels': [
              {'id': 'C1', 'name': 'general', 'is_private': false},
              {'id': 'G2', 'name': 'secret', 'is_private': true},
            ],
          }),
          200,
        ),
      );

      final result = await command.run();

      expect(result, equals(ExitCode.success.code));
      verify(() => logger.info('# general  (C1)')).called(1);
      verify(() => logger.info('🔒 secret  (G2)')).called(1);
    });

    test('shows info message when no channels found', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);
      when(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'ok': true,
            'channels': <Map<String, dynamic>>[],
          }),
          200,
        ),
      );

      final result = await command.run();

      expect(result, equals(ExitCode.success.code));
      verify(() => logger.info('No channels found.')).called(1);
    });

    test('lists channels from later pages too', () async {
      var callCount = 0;
      when(() => credentialsStore.load()).thenReturn(credentials);
      when(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer(
        (_) async {
          callCount++;
          return http.Response(
            jsonEncode({
              'ok': true,
              'channels': [
                if (callCount == 1)
                  {'id': 'C1', 'name': 'general', 'is_private': false}
                else
                  {'id': 'G2', 'name': 'secret', 'is_private': true},
              ],
              'response_metadata': {
                'next_cursor': callCount == 1 ? 'cursor-1' : '',
              },
            }),
            200,
          );
        },
      );

      final result = await command.run();

      expect(result, equals(ExitCode.success.code));
      verify(() => logger.info('# general  (C1)')).called(1);
      verify(() => logger.info('🔒 secret  (G2)')).called(1);
    });
  });
}
