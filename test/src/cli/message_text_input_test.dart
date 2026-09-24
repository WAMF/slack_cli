import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_slack/src/auth/credentials.dart';
import 'package:dart_slack/src/auth/credentials_store.dart';
import 'package:dart_slack/src/cli/commands/authenticated_command.dart';
import 'package:dart_slack/src/cli/commands/dm_command.dart';
import 'package:dart_slack/src/cli/commands/edit_command.dart';
import 'package:dart_slack/src/cli/commands/reply_command.dart';
import 'package:dart_slack/src/cli/commands/send_command.dart';
import 'package:dart_slack/src/cli/message_text_input.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockCredentialsStore extends Mock implements CredentialsStore {}

class _MockHttpClient extends Mock implements http.Client {}

/// One message-writing command, with the arguments that address it.
class _Subject {
  const _Subject(this.name, this.build, this.address);

  final String name;
  final AuthenticatedCommand Function({
    required Logger logger,
    CredentialsStore? credentialsStore,
    http.Client? httpClient,
  })
  build;

  /// The arguments before the text options, `send` excluded.
  final List<String> address;
}

const _subjects = <_Subject>[
  _Subject('send', SendCommand.new, ['-c', 'C1']),
  _Subject('reply', ReplyCommand.new, ['-c', 'C1', '-r', '1.0']),
  _Subject('dm', DmCommand.new, ['-u', 'U1']),
  _Subject('edit', EditCommand.new, ['-c', 'C1', '--ts', '1.0']),
];

const _credentials = Credentials(accessToken: 'xoxp-test', userId: 'U123');

void main() {
  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  for (final subject in _subjects) {
    group('${subject.name} message text input', () {
      late _MockLogger logger;
      late _MockCredentialsStore credentialsStore;
      late _MockHttpClient httpClient;
      late AuthenticatedCommand command;
      late CommandRunner<int> runner;
      late List<String> sentBodies;

      setUp(() {
        logger = _MockLogger();
        credentialsStore = _MockCredentialsStore();
        httpClient = _MockHttpClient();
        sentBodies = <String>[];

        when(() => logger.success(any())).thenReturn(null);
        when(() => logger.err(any())).thenReturn(null);
        when(() => logger.warn(any())).thenReturn(null);
        when(() => logger.info(any())).thenReturn(null);
        when(() => httpClient.close()).thenReturn(null);
        when(() => credentialsStore.load()).thenReturn(_credentials);
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

        command = subject.build(
          logger: logger,
          credentialsStore: credentialsStore,
          httpClient: httpClient,
        );
        runner = CommandRunner<int>('test', 'test')..addCommand(command);
      });

      Future<int?> run(List<String> textArgs) =>
          runner.run([subject.name, ...subject.address, ...textArgs]);

      String sentText() =>
          (jsonDecode(sentBodies.last) as Map<String, dynamic>)['text']
              as String;

      void readsStdin(String value) {
        (command as MessageTextCommand).readMessageStdin = () => value;
      }

      File writeTextFile(String contents) {
        final file = File(
          '${Directory.systemTemp.createTempSync('dart_slack_text').path}'
          '/message.txt',
        )..writeAsStringSync(contents);
        addTearDown(() => file.parent.deleteSync(recursive: true));
        return file;
      }

      test('declares the three text sources and no longer forces --text', () {
        final options = command.argParser.options;

        // `--text` was `mandatory: true`. That is what forced every caller
        // through a shell argument, so it has to be false now. The other two
        // options are the safe paths this issue adds.
        expect(options[textOption]?.mandatory, isFalse);
        expect(options[textOption]?.abbr, equals('t'));
        expect(options[textFileOption], isNotNull);
        expect(options[textFileOption]?.abbr, isNull);
        expect(options[textStdinFlag], isNotNull);
      });

      test('--text-file delivers the bytes unchanged', () async {
        // Every character the shell would have eaten, in one file.
        const raw =
            'a `printf changed` b \$(id) c \${HOME} d "q" e \'s\'\n'
            'second line\ttab';
        final file = writeTextFile(raw);

        final exitCode = await run(['--text-file', file.path]);

        expect(exitCode, equals(ExitCode.success.code));
        expect(sentText(), equals(raw));
      });

      test('--text-stdin delivers the bytes unchanged', () async {
        const raw = 'x `printf changed` y \$(id)\nz';
        readsStdin(raw);

        final exitCode = await run(['--text-stdin']);

        expect(exitCode, equals(ExitCode.success.code));
        expect(sentText(), equals(raw));
      });

      test('--text-file - reads standard input', () async {
        readsStdin('from stdin');

        final exitCode = await run(['--text-file', '-']);

        expect(exitCode, equals(ExitCode.success.code));
        expect(sentText(), equals('from stdin'));
      });

      test('file text keeps a literal backslash-n', () async {
        // The inline path unescapes this, because a shell cannot pass a real
        // newline in a double-quoted argument. A file can, so unescaping file
        // bytes would corrupt a code sample that contains the two characters.
        final file = writeTextFile(r'line1\nline2');

        await run(['--text-file', file.path]);

        expect(sentText(), equals(r'line1\nline2'));
        expect(sentText(), isNot(contains('\n')));
      });

      test('inline text is still repaired, as before', () async {
        await run(['-t', r'line1\nline2']);

        expect(sentText(), equals('line1\nline2'));
      });

      test('rejects --text together with --text-file', () async {
        final file = writeTextFile('from file');

        final exitCode = await run(['-t', 'inline', '--text-file', file.path]);

        expect(exitCode, equals(ExitCode.usage.code));
        expect(sentBodies, isEmpty);
      });

      test('rejects --text together with --text-stdin', () async {
        readsStdin('from stdin');

        final exitCode = await run(['-t', 'inline', '--text-stdin']);

        expect(exitCode, equals(ExitCode.usage.code));
        expect(sentBodies, isEmpty);
      });

      test('rejects --text-file together with --text-stdin', () async {
        final file = writeTextFile('from file');

        final exitCode = await run([
          '--text-file',
          file.path,
          '--text-stdin',
        ]);

        expect(exitCode, equals(ExitCode.usage.code));
        expect(sentBodies, isEmpty);
      });

      test('accepts --text-file - with --text-stdin, one source', () async {
        readsStdin('one source');

        final exitCode = await run(['--text-file', '-', '--text-stdin']);

        expect(exitCode, equals(ExitCode.success.code));
        expect(sentText(), equals('one source'));
      });

      test('rejects no text source at all', () async {
        final exitCode = await run([]);

        expect(exitCode, equals(ExitCode.usage.code));
        expect(sentBodies, isEmpty);
      });

      test('reports a missing text file and sends nothing', () async {
        final exitCode = await run([
          '--text-file',
          '${Directory.systemTemp.path}/dart_slack_absent_message.txt',
        ]);

        expect(exitCode, equals(ExitCode.noInput.code));
        expect(sentBodies, isEmpty);
      });

      test('answers a text usage error without reading a credential', () async {
        // The same rule `search` follows: a usage error must not depend on
        // the auth state, or a logged-out caller is told the wrong thing.
        final exitCode = await run([]);

        expect(exitCode, equals(ExitCode.usage.code));
        verifyNever(() => credentialsStore.load());
      });

      test(
        'warns about a backtick in inline --text, and still sends',
        () async {
          final exitCode = await run(['-t', 'see `code` here']);

          expect(exitCode, equals(ExitCode.success.code));
          expect(sentText(), equals('see `code` here'));
          final warning = verify(
            () => logger.warn(captureAny()),
          ).captured.single;
          expect(warning, contains('--$textFileOption'));
          expect(warning, contains('`'));
        },
      );

      test(r'warns about $( in inline --text', () async {
        await run(['-t', r'value $(id) here']);

        verify(() => logger.warn(any())).called(1);
      });

      test(r'warns about ${ in inline --text', () async {
        await run(['-t', r'value ${HOME} here']);

        verify(() => logger.warn(any())).called(1);
      });

      test('does not warn about ordinary inline text', () async {
        await run(['-t', 'ordinary text with a "quote"']);

        verifyNever(() => logger.warn(any()));
      });

      test('does not warn about a backtick that came from a file', () async {
        // File bytes never passed through a shell, so the warning would be
        // noise on the very path callers are being moved to.
        final file = writeTextFile('see `code` here');

        await run(['--text-file', file.path]);

        verifyNever(() => logger.warn(any()));
      });

      test('does not warn about a backtick that came from stdin', () async {
        readsStdin('see `code` here');

        await run(['--text-stdin']);

        verifyNever(() => logger.warn(any()));
      });
    });
  }
}
