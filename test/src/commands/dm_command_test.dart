import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:dart_slack/src/auth/credentials.dart';
import 'package:dart_slack/src/auth/credentials_store.dart';
import 'package:dart_slack/src/cli/commands/dm_command.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockCredentialsStore extends Mock implements CredentialsStore {}

class _MockHttpClient extends Mock implements http.Client {}

void main() {
  group('DmCommand', () {
    late Logger logger;
    late DmCommand command;

    setUp(() {
      logger = _MockLogger();
      command = DmCommand(logger: logger);
    });

    test('has correct name and description', () {
      expect(command.name, equals('dm'));
      expect(command.description, isNotEmpty);
    });

    test('requires user and text options', () {
      final options = command.argParser.options;
      expect(options['user']?.mandatory, isTrue);
      expect(options['text']?.mandatory, isTrue);
    });

    test('has correct abbreviations', () {
      final options = command.argParser.options;
      expect(options['user']?.abbr, equals('u'));
      expect(options['text']?.abbr, equals('t'));
    });
  });

  group('DmCommand output', () {
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

      when(() => logger.success(any())).thenReturn(null);
      when(() => httpClient.close()).thenReturn(null);

      runner = CommandRunner<int>('test', 'test')
        ..addCommand(
          DmCommand(
            logger: logger,
            credentialsStore: credentialsStore,
            httpClient: httpClient,
          ),
        );
    });

    test('surfaces the posted message ts on success', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);
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
            'channel': 'D1',
            'ts': '1784206000.222000',
            'message': {'text': 'hey'},
          }),
          200,
        ),
      );

      await runner.run(['dm', '-u', 'U9', '-t', 'hey']);

      verify(
        () => logger.success('DM sent to U9 (ts: 1784206000.222000).'),
      ).called(1);
    });
  });
}
