import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_slack/src/auth/credentials.dart';
import 'package:dart_slack/src/auth/credentials_store.dart';
import 'package:dart_slack/src/cli/commands/canvas_command.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockCredentialsStore extends Mock implements CredentialsStore {}

class _MockHttpClient extends Mock implements http.Client {}

void main() {
  group('CanvasCommand', () {
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
      when(() => logger.err(any())).thenReturn(null);
      when(() => httpClient.close()).thenReturn(null);
      when(() => credentialsStore.load()).thenReturn(credentials);

      runner = CommandRunner<int>('test', 'test')
        ..addCommand(
          CanvasCommand(
            logger: logger,
            credentialsStore: credentialsStore,
            httpClient: httpClient,
          ),
        );
    });

    void stubPost(Map<String, dynamic> response) {
      when(
        () => httpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => http.Response(jsonEncode(response), 200));
    }

    Map<String, dynamic> capturedBody() {
      return jsonDecode(
            verify(
                  () => httpClient.post(
                    any(),
                    headers: any(named: 'headers'),
                    body: captureAny(named: 'body'),
                  ),
                ).captured.last
                as String,
          )
          as Map<String, dynamic>;
    }

    test('has correct name and description', () {
      final command = CanvasCommand(logger: logger);
      expect(command.name, equals('canvas'));
      expect(command.description, isNotEmpty);
    });

    test('registers create, read, edit, and delete subcommands', () {
      final command = CanvasCommand(logger: logger);
      expect(
        command.subcommands.keys,
        containsAll(<String>['create', 'read', 'edit', 'delete']),
      );
    });

    /// Stubs the two GETs a canvas read makes: `files.info` (returns the
    /// canvas file with a download URL) and the download of that URL
    /// (returns the canvas body).
    void stubCanvasRead({
      String? downloadUrl = 'https://files.slack.com/canvas-F1',
      String body = '# Huddle notes',
    }) {
      when(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((invocation) async {
        final uri = invocation.positionalArguments.first as Uri;
        if (uri.host == 'slack.com' && uri.path.contains('files.info')) {
          return http.Response(
            jsonEncode({
              'ok': true,
              'file': {
                'id': 'F1',
                'filetype': 'canvas',
                'url_private_download': ?downloadUrl,
              },
            }),
            200,
          );
        }
        return http.Response(body, 200);
      });
    }

    group('read', () {
      test('prints the canvas body fetched from its download URL', () async {
        when(() => logger.info(any())).thenReturn(null);
        stubCanvasRead(body: '# Huddle notes\n- point');

        final code = await runner.run(['canvas', 'read', '--canvas', 'F1']);

        expect(code, equals(ExitCode.success.code));
        verify(() => logger.info('# Huddle notes\n- point')).called(1);
      });

      test('looks the canvas up by id via files.info', () async {
        when(() => logger.info(any())).thenReturn(null);
        stubCanvasRead();

        await runner.run(['canvas', 'read', '--canvas', 'F1']);

        final uris = verify(
          () => httpClient.get(
            captureAny(),
            headers: any(named: 'headers'),
          ),
        ).captured.cast<Uri>();
        final infoUri = uris.firstWhere((u) => u.path.contains('files.info'));
        expect(infoUri.queryParameters['file'], equals('F1'));
      });

      test('writes to --output instead of stdout', () async {
        stubCanvasRead(body: '# Saved');
        final dir = Directory.systemTemp.createTempSync('canvas_read');
        addTearDown(() => dir.deleteSync(recursive: true));
        final out = '${dir.path}/canvas.md';

        final code = await runner.run([
          'canvas',
          'read',
          '--canvas',
          'F1',
          '-o',
          out,
        ]);

        expect(code, equals(ExitCode.success.code));
        expect(File(out).readAsStringSync(), equals('# Saved'));
        verify(() => logger.success('Canvas F1 written to $out')).called(1);
      });

      test('errors when the file has no downloadable content', () async {
        stubCanvasRead(downloadUrl: null);

        final code = await runner.run(['canvas', 'read', '--canvas', 'F1']);

        expect(code, equals(ExitCode.unavailable.code));
        verify(
          () => logger.err(any(that: contains('No readable content'))),
        ).called(1);
      });

      test('requires the canvas option', () {
        final command = CanvasReadCommand(logger: logger);
        expect(command.argParser.options['canvas']?.mandatory, isTrue);
      });
    });

    group('create', () {
      test('creates a standalone canvas from inline content', () async {
        stubPost({'ok': true, 'canvas_id': 'F1'});

        final code = await runner.run([
          'canvas',
          'create',
          '--title',
          'Doc',
          '-m',
          '# Hello',
        ]);

        expect(code, equals(ExitCode.success.code));
        final body = capturedBody();
        expect(body['title'], equals('Doc'));
        expect(
          (body['document_content'] as Map<String, dynamic>)['markdown'],
          equals('# Hello'),
        );
        verify(() => logger.success('Canvas created: F1')).called(1);
      });

      test('tabs the canvas into a channel when --channel is given', () async {
        stubPost({'ok': true, 'canvas_id': 'F2'});

        await runner.run(['canvas', 'create', '-c', 'C9', '-m', 'body']);

        expect(capturedBody()['channel_id'], equals('C9'));
      });

      test('reads content from --file', () async {
        stubPost({'ok': true, 'canvas_id': 'F3'});
        final dir = Directory.systemTemp.createTempSync('canvas_test');
        addTearDown(() => dir.deleteSync(recursive: true));
        final file = File('${dir.path}/body.md')
          ..writeAsStringSync('# From file');

        await runner.run(['canvas', 'create', '-f', file.path]);

        expect(
          (capturedBody()['document_content']
              as Map<String, dynamic>)['markdown'],
          equals('# From file'),
        );
      });

      test('errors when neither --content nor --file is given', () async {
        final code = await runner.run(['canvas', 'create']);

        expect(code, equals(ExitCode.usage.code));
        verify(
          () => logger.err('Provide exactly one of --content or --file.'),
        ).called(1);
        verifyNever(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        );
      });

      test('errors when both --content and --file are given', () async {
        final code = await runner.run([
          'canvas',
          'create',
          '-m',
          'x',
          '-f',
          'y.md',
        ]);

        expect(code, equals(ExitCode.usage.code));
        verify(
          () => logger.err('Provide exactly one of --content or --file.'),
        ).called(1);
      });

      test('errors when the --file path does not exist', () async {
        final code = await runner.run([
          'canvas',
          'create',
          '-f',
          '/no/such/file.md',
        ]);

        expect(code, equals(ExitCode.usage.code));
        verify(
          () => logger.err(any(that: startsWith('Failed to read file:'))),
        ).called(1);
        verifyNever(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        );
      });

      test('errors when the --file path is not a regular file', () async {
        // A directory cannot be read as a string, exercising the
        // FileSystemException path without depending on file permissions.
        final dir = Directory.systemTemp.createTempSync('canvas_test');
        addTearDown(() => dir.deleteSync(recursive: true));

        final code = await runner.run(['canvas', 'create', '-f', dir.path]);

        expect(code, equals(ExitCode.usage.code));
        verify(
          () => logger.err(any(that: startsWith('Failed to read file:'))),
        ).called(1);
        verifyNever(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        );
      });
    });

    group('edit', () {
      test('replaces content by default', () async {
        stubPost({'ok': true});

        final code = await runner.run([
          'canvas',
          'edit',
          '--canvas',
          'F1',
          '-m',
          'new body',
        ]);

        expect(code, equals(ExitCode.success.code));
        final body = capturedBody();
        expect(body['canvas_id'], equals('F1'));
        final change =
            (body['changes'] as List<dynamic>).first as Map<String, dynamic>;
        expect(change['operation'], equals('replace'));
        verify(() => logger.success('Canvas F1 updated.')).called(1);
      });

      test('maps --mode append to insert_at_end', () async {
        stubPost({'ok': true});

        await runner.run([
          'canvas',
          'edit',
          '--canvas',
          'F1',
          '--mode',
          'append',
          '-m',
          'more',
        ]);

        final change =
            (capturedBody()['changes'] as List<dynamic>).first
                as Map<String, dynamic>;
        expect(change['operation'], equals('insert_at_end'));
      });

      test('requires the canvas option', () {
        final command = CanvasEditCommand(logger: logger);
        expect(command.argParser.options['canvas']?.mandatory, isTrue);
      });
    });

    group('delete', () {
      test('deletes a canvas', () async {
        stubPost({'ok': true});

        final code = await runner.run([
          'canvas',
          'delete',
          '--canvas',
          'F1',
        ]);

        expect(code, equals(ExitCode.success.code));
        expect(capturedBody()['canvas_id'], equals('F1'));
        verify(() => logger.success('Canvas F1 deleted.')).called(1);
      });

      test('requires the canvas option', () {
        final command = CanvasDeleteCommand(logger: logger);
        expect(command.argParser.options['canvas']?.mandatory, isTrue);
      });
    });
  });
}
