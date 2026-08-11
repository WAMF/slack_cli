import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:dart_slack/src/auth/credentials.dart';
import 'package:dart_slack/src/auth/credentials_store.dart';
import 'package:dart_slack/src/cli/commands/edit_command.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockCredentialsStore extends Mock implements CredentialsStore {}

class _MockHttpClient extends Mock implements http.Client {}

void main() {
  group('EditCommand', () {
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
          EditCommand(
            logger: logger,
            credentialsStore: credentialsStore,
            httpClient: httpClient,
          ),
        );
    });

    test('has correct name and description', () {
      final command = EditCommand(logger: logger);
      expect(command.name, equals('edit'));
      expect(command.description, isNotEmpty);
    });

    test('updates a message', () async {
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
            'ts': '1.0',
            'message': {'text': 'updated'},
          }),
          200,
        ),
      );

      await runner.run(['edit', '-c', 'C1', '--ts', '1.0', '-t', 'updated']);

      verify(
        () => logger.success('Message 1.0 in C1 updated.'),
      ).called(1);
    });
  });

  group('EditCommand text normalization', () {
    late _MockLogger logger;
    late _MockCredentialsStore credentialsStore;
    late _MockHttpClient httpClient;
    late CommandRunner<int> runner;
    late List<String> sentBodies;

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
      sentBodies = <String>[];

      when(() => logger.success(any())).thenReturn(null);
      when(() => logger.err(any())).thenReturn(null);
      when(() => httpClient.close()).thenReturn(null);
      when(() => credentialsStore.load()).thenReturn(credentials);
      when(
        () => httpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((invocation) async {
        sentBodies.add(invocation.namedArguments[#body] as String);
        return http.Response(
          jsonEncode({
            'ok': true,
            'channel': 'C1',
            'ts': '1.0',
            'message': {'text': 'x'},
          }),
          200,
        );
      });

      runner = CommandRunner<int>('test', 'test')
        ..addCommand(
          EditCommand(
            logger: logger,
            credentialsStore: credentialsStore,
            httpClient: httpClient,
          ),
        );
    });

    String sentText() =>
        (jsonDecode(sentBodies.last) as Map<String, dynamic>)['text'] as String;

    test('converts a literal escape sequence to a real newline', () async {
      await runner.run([
        'edit',
        '-c',
        'C1',
        '--ts',
        '1.0',
        '-t',
        r'line1\nline2',
      ]);

      expect(sentText(), equals('line1\nline2'));
    });

    test('sends plain text unchanged', () async {
      await runner.run(['edit', '-c', 'C1', '--ts', '1.0', '-t', 'plain text']);

      expect(sentText(), equals('plain text'));
    });
  });
}
