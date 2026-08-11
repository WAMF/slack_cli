import 'dart:convert';
import 'dart:io';

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
      expect(options['file']?.abbr, equals('f'));
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
      registerFallbackValue(
        http.Request('GET', Uri.parse('https://example.com')),
      );
    });

    setUp(() {
      logger = _MockLogger();
      credentialsStore = _MockCredentialsStore();
      httpClient = _MockHttpClient();

      when(() => logger.success(any())).thenReturn(null);
      when(() => logger.err(any())).thenReturn(null);
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

    test('uploads and attaches a file when --file is given', () async {
      final tempFile = File(
        '${Directory.systemTemp.path}/dart_slack_send_test.txt',
      )..writeAsStringSync('contents');
      addTearDown(tempFile.deleteSync);

      when(() => credentialsStore.load()).thenReturn(credentials);
      when(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'ok': true,
            'upload_url': 'https://files.slack.com/upload/v1/abc',
            'file_id': 'F123',
          }),
          200,
        ),
      );
      when(() => httpClient.send(any())).thenAnswer(
        (_) async =>
            http.StreamedResponse(Stream.value(utf8.encode('OK')), 200),
      );
      when(
        () => httpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({'ok': true, 'files': <Map<String, dynamic>>[]}),
          200,
        ),
      );

      await runner.run(
        ['send', '-c', 'C1', '-t', 'here you go', '-f', tempFile.path],
      );

      verify(
        () => logger.success(
          'File "dart_slack_send_test.txt" sent to C1.',
        ),
      ).called(1);
    });

    test('reports a clean error when the file does not exist', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);

      final exitCode = await runner.run(
        ['send', '-c', 'C1', '-t', 'hi', '-f', '/no/such/file.txt'],
      );

      expect(exitCode, equals(ExitCode.noInput.code));
      verify(() => logger.err('File not found: /no/such/file.txt')).called(1);
      verifyNever(
        () => httpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      );
    });
  });

  group('SendCommand text normalization', () {
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
          SendCommand(
            logger: logger,
            credentialsStore: credentialsStore,
            httpClient: httpClient,
          ),
        );
    });

    String sentText() =>
        (jsonDecode(sentBodies.last) as Map<String, dynamic>)['text'] as String;

    test('converts a literal escape sequence to a real newline', () async {
      await runner.run(['send', '-c', 'C1', '-t', r'line1\nline2']);

      expect(sentText(), equals('line1\nline2'));
    });

    test('sends plain text unchanged', () async {
      await runner.run(['send', '-c', 'C1', '-t', 'plain text']);

      expect(sentText(), equals('plain text'));
    });
  });
}
