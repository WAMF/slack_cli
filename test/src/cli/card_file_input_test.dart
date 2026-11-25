import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_slack/src/auth/credentials.dart';
import 'package:dart_slack/src/auth/credentials_store.dart';
import 'package:dart_slack/src/cli/commands/edit_command.dart';
import 'package:dart_slack/src/cli/commands/reply_command.dart';
import 'package:dart_slack/src/cli/commands/send_command.dart';
import 'package:dart_slack/src/slack_api/slack_urls.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger;

class _MockCredentialsStore extends Mock implements CredentialsStore;

class _MockHttpClient extends Mock implements http.Client;

const _fixtures = 'test/fixtures/rich_message';

Map<String, dynamic> _golden(String name) =>
    jsonDecode(File('$_fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  late _MockLogger logger;
  late _MockCredentialsStore credentialsStore;
  late _MockHttpClient httpClient;
  late CommandRunner<int> runner;
  late List<({Uri uri, Map<String, dynamic> body})> posts;
  late Directory temp;

  const credentials = Credentials(accessToken: 'xoxp-test', userId: 'U123');

  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  setUp(() {
    logger = _MockLogger();
    credentialsStore = _MockCredentialsStore();
    httpClient = _MockHttpClient();
    posts = [];
    temp = Directory.systemTemp.createTempSync('dart_slack_card_');
    addTearDown(() => temp.deleteSync(recursive: true));

    when(() => logger.success(any())).thenReturn(null);
    when(() => logger.err(any())).thenReturn(null);
    when(() => logger.info(any())).thenReturn(null);
    when(() => httpClient.close()).thenReturn(null);
    when(() => credentialsStore.load()).thenReturn(credentials);
    when(
      () => httpClient.post(
        any(),
        headers: any(named: 'headers'),
        body: any(named: 'body'),
      ),
    ).thenAnswer((invocation) async {
      posts.add((
        uri: invocation.positionalArguments.single as Uri,
        body: jsonDecode(
          invocation.namedArguments[#body] as String,
        ) as Map<String, dynamic>,
      ));
      return http.Response(
        jsonEncode({
          'ok': true,
          'channel': 'C1',
          'ts': '1.2',
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
      )
      ..addCommand(
        ReplyCommand(
          logger: logger,
          credentialsStore: credentialsStore,
          httpClient: httpClient,
        ),
      )
      ..addCommand(
        EditCommand(
          logger: logger,
          credentialsStore: credentialsStore,
          httpClient: httpClient,
        ),
      );
  });

  String writeCard(Object? card) {
    final file = File('${temp.path}/card.json')
      ..writeAsStringSync(card is String ? card : jsonEncode(card));
    return file.path;
  }

  void expectNoCall() {
    verifyNever(() => credentialsStore.load());
    verifyNever(
      () => httpClient.post(
        any(),
        headers: any(named: 'headers'),
        body: any(named: 'body'),
      ),
    );
  }

  group('--card-file posts the golden payload', () {
    final golden = _golden('draft_proposed.slack.json');
    const card = '$_fixtures/draft_proposed.json';

    test(
      'reply -c <ch> -r <ts> --card-file posts the backend blocks',
      () async {
        final code = await runner.run([
          'reply',
          '-c',
          'C1',
          '-r',
          '111.222',
          '--card-file',
          card,
        ]);

        expect(code, ExitCode.success.code);
        expect(posts.single.uri, SlackUrls.postMessage);
        expect(posts.single.body, {
          'channel': 'C1',
          'thread_ts': '111.222',
          ...golden,
        });
      },
    );

    test('send --card-file posts the backend blocks', () async {
      final code = await runner.run(['send', '-c', 'C1', '--card-file', card]);

      expect(code, ExitCode.success.code);
      expect(posts.single.uri, SlackUrls.postMessage);
      expect(posts.single.body, {'channel': 'C1', ...golden});
    });

    test('edit --card-file replaces the message with the blocks', () async {
      final code = await runner.run([
        'edit',
        '-c',
        'C1',
        '--ts',
        '1.2',
        '--card-file',
        card,
      ]);

      expect(code, ExitCode.success.code);
      expect(posts.single.uri, SlackUrls.chatUpdate);
      expect(posts.single.body, {
        'channel': 'C1',
        'ts': '1.2',
        'text': golden['text'],
        'blocks': golden['blocks'],
      });
    });

    test('-t still posts plain text with no blocks', () async {
      await runner.run(['send', '-c', 'C1', '-t', 'hi']);

      expect(posts.single.body, {'channel': 'C1', 'text': 'hi'});
    });
  });

  group('--card-file refuses before any API call', () {
    test('an invalid card names the field and exits 65', () async {
      final path = writeCard({
        'fallbackText': 'F',
        'title': 'T',
        'links': [
          {'label': 'a', 'url': 'javascript:alert(1)'},
        ],
      });

      final code = await runner.run([
        'reply',
        '-c',
        'C1',
        '-r',
        '1.2',
        '--card-file',
        path,
      ]);

      expect(code, ExitCode.data.code);
      verify(
        () => logger.err(
          'Invalid card file $path: RichMessage.links[0].url: '
          'must match ^https?://',
        ),
      ).called(1);
      verify(
        () => logger.err(
          '{"ok":false,"error":"invalid_card","field":"links[0].url"}',
        ),
      ).called(1);
      expectNoCall();
    });

    test('a phase 2 card is refused on actions', () async {
      final path = writeCard({
        'fallbackText': 'F',
        'title': 'T',
        'actions': [
          {'id': 'a', 'label': 'A'},
        ],
      });

      final code = await runner.run(['send', '-c', 'C1', '--card-file', path]);

      expect(code, ExitCode.data.code);
      verify(
        () =>
            logger.err('{"ok":false,"error":"invalid_card","field":"actions"}'),
      ).called(1);
      expectNoCall();
    });

    test('a file that is not JSON is refused', () async {
      final path = writeCard('{not json');

      final code = await runner.run(['send', '-c', 'C1', '--card-file', path]);

      expect(code, ExitCode.data.code);
      verify(
        () => logger.err(
          any(
            that: startsWith('Invalid card file $path: RichMessage.(root): '),
          ),
        ),
      ).called(1);
      expectNoCall();
    });

    test('a missing file exits 66', () async {
      final code = await runner.run([
        'edit',
        '-c',
        'C1',
        '--ts',
        '1.2',
        '--card-file',
        '/no/such/card.json',
      ]);

      expect(code, ExitCode.noInput.code);
      verify(() => logger.err('Card file not found: /no/such/card.json'))
          .called(1);
      expectNoCall();
    });

    test('--card-file with --text is a usage error', () async {
      final path = writeCard({'fallbackText': 'F', 'title': 'T'});

      final code = await runner.run([
        'send',
        '-c',
        'C1',
        '-t',
        'hi',
        '--card-file',
        path,
      ]);

      expect(code, ExitCode.usage.code);
      verify(
        () => logger.err(any(that: startsWith('Conflicting message content.'))),
      ).called(1);
      expectNoCall();
    });

    for (final textArgs in [
      ['--text-file', 'x.md'],
      ['--text-stdin'],
    ]) {
      test('--card-file with ${textArgs.first} is a usage error', () async {
        final path = writeCard({'fallbackText': 'F', 'title': 'T'});

        final code = await runner.run([
          'reply',
          '-c',
          'C1',
          '-r',
          '1.2',
          ...textArgs,
          '--card-file',
          path,
        ]);

        expect(code, ExitCode.usage.code);
        expectNoCall();
      });
    }

    test('--card-file with --file is a usage error', () async {
      final path = writeCard({'fallbackText': 'F', 'title': 'T'});

      final code = await runner.run([
        'send',
        '-c',
        'C1',
        '-f',
        path,
        '--card-file',
        path,
      ]);

      expect(code, ExitCode.usage.code);
      verify(
        () => logger.err(
          any(that: startsWith('--card-file cannot be combined with --file.')),
        ),
      ).called(1);
      expectNoCall();
    });
  });

  test('--card-file - reads the card from standard input', () async {
    final command = SendCommand(
      logger: logger,
      credentialsStore: credentialsStore,
      httpClient: httpClient,
    )..readMessageStdin = () => jsonEncode({'fallbackText': 'F', 'title': 'T'});
    final stdinRunner = CommandRunner<int>('test', 'test')..addCommand(command);

    final code = await stdinRunner.run([
      'send',
      '-c',
      'C1',
      '--card-file',
      '-',
    ]);

    expect(code, ExitCode.success.code);
    expect(posts.single.body['text'], 'F');
    expect(posts.single.body['blocks'], hasLength(1));
  });

  test('send, reply and edit show --card-file in --help', () {
    for (final name in ['send', 'reply', 'edit']) {
      expect(runner.commands[name]!.usage, contains('--card-file'));
    }
  });
}
