import 'dart:convert';
import 'dart:io';

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
      expect(options['file']?.abbr, equals('f'));
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

    test('uploads and attaches a file when --file is given', () async {
      final tempFile = File(
        '${Directory.systemTemp.path}/dart_slack_dm_test.txt',
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
      ).thenAnswer((invocation) async {
        final uri = invocation.positionalArguments.first as Uri;
        if (uri.path.contains('conversations.open')) {
          return http.Response(
            jsonEncode({
              'ok': true,
              'channel': {'id': 'D9'},
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({'ok': true, 'files': <Map<String, dynamic>>[]}),
          200,
        );
      });

      await runner.run([
        'dm',
        '-u',
        'U9',
        '-t',
        'here you go',
        '-f',
        tempFile.path,
      ]);

      verify(
        () => logger.success('File "dart_slack_dm_test.txt" sent to U9.'),
      ).called(1);

      final completeBody =
          jsonDecode(
                verify(
                      () => httpClient.post(
                        captureAny(),
                        headers: any(named: 'headers'),
                        body: captureAny(named: 'body'),
                      ),
                    ).captured[3]
                    as String,
              )
              as Map<String, dynamic>;
      expect(completeBody['channel_id'], equals('D9'));
    });

    test('reports a clean error when the file does not exist', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);

      final exitCode = await runner.run(
        ['dm', '-u', 'U9', '-t', 'hey', '-f', '/no/such/file.txt'],
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
}
