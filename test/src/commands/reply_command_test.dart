import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:dart_slack/src/auth/credentials.dart';
import 'package:dart_slack/src/auth/credentials_store.dart';
import 'package:dart_slack/src/cli/commands/reply_command.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockCredentialsStore extends Mock implements CredentialsStore {}

class _MockHttpClient extends Mock implements http.Client {}

void main() {
  group('ReplyCommand', () {
    late Logger logger;
    late ReplyCommand command;

    setUp(() {
      logger = _MockLogger();
      command = ReplyCommand(logger: logger);
    });

    test('has correct name and description', () {
      expect(command.name, equals('reply'));
      expect(command.description, isNotEmpty);
    });

    test('requires channel, thread, and text options', () {
      final options = command.argParser.options;
      expect(options['channel']?.mandatory, isTrue);
      expect(options['thread']?.mandatory, isTrue);
      expect(options['text']?.mandatory, isTrue);
    });

    test('has correct abbreviations', () {
      final options = command.argParser.options;
      expect(options['channel']?.abbr, equals('c'));
      expect(options['thread']?.abbr, equals('r'));
      expect(options['text']?.abbr, equals('t'));
    });
  });

  group('ReplyCommand output', () {
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
          ReplyCommand(
            logger: logger,
            credentialsStore: credentialsStore,
            httpClient: httpClient,
          ),
        );
    });

    test('surfaces the posted reply ts on success', () async {
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
            'ts': '1784205999.111000',
            'message': {'text': 'yo'},
          }),
          200,
        ),
      );

      await runner.run(
        ['reply', '-c', 'C1', '-r', '1784205912.550099', '-t', 'yo'],
      );

      verify(
        () => logger.success(
          'Reply sent to thread 1784205912.550099 in C1 '
          '(ts: 1784205999.111000).',
        ),
      ).called(1);
    });
  });
}
