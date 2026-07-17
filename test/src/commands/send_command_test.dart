import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:dart_slack/src/auth/credentials.dart';
import 'package:dart_slack/src/auth/credentials_store.dart';
import 'package:dart_slack/src/cli/commands/send_command.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockCredentialsStore extends Mock implements CredentialsStore {}

class _MockHttpClient extends Mock implements http.Client {}

void main() {
  group('SendCommand', () {
    late Logger logger;
    late SendCommand command;

    setUp(() {
      logger = _MockLogger();
      command = SendCommand(logger: logger);
    });

    test('has correct name and description', () {
      expect(command.name, equals('send'));
      expect(command.description, isNotEmpty);
    });

    test('requires channel and text options', () {
      final options = command.argParser.options;
      expect(options['channel']?.mandatory, isTrue);
      expect(options['text']?.mandatory, isTrue);
    });

    test('has correct abbreviations', () {
      final options = command.argParser.options;
      expect(options['channel']?.abbr, equals('c'));
      expect(options['text']?.abbr, equals('t'));
    });
  });

  group('SendCommand output', () {
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
          SendCommand(
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
            'channel': 'C1',
            'ts': '1784205912.550099',
            'message': {'text': 'hi'},
          }),
          200,
        ),
      );

      await runner.run(['send', '-c', 'C1', '-t', 'hi']);

      verify(
        () => logger.success('Message sent to C1 (ts: 1784205912.550099).'),
      ).called(1);
    });
  });
}
