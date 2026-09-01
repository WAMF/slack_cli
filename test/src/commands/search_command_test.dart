import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:dart_slack/src/auth/credentials.dart';
import 'package:dart_slack/src/auth/credentials_store.dart';
import 'package:dart_slack/src/cli/commands/search_command.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockCredentialsStore extends Mock implements CredentialsStore {}

class _MockHttpClient extends Mock implements http.Client {}

/// A 200 answer carrying [body], decoded as UTF-8.
///
/// `http.Response(String, int)` encodes the body as Latin-1 and throws on any
/// character outside it, so an emoji in a match would fail in the harness
/// rather than in the code under test. Slack answers
/// `application/json; charset=utf-8`, so the harness says so too.
http.Response _okResponse(String body) {
  return http.Response.bytes(
    utf8.encode(body),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

/// A `search.messages` body carrying [matches] on page [page] of [pages].
String _searchResponse(
  List<Map<String, dynamic>> matches, {
  int page = 1,
  int pages = 1,
}) {
  return jsonEncode({
    'ok': true,
    'query': 'deploy failed',
    'messages': {
      'total': matches.length,
      'paging': {
        'count': 20,
        'total': matches.length,
        'page': page,
        'pages': pages,
      },
      'matches': matches,
    },
  });
}

/// One match, shaped the way `search.messages` returns it.
Map<String, dynamic> _match({
  String ts = '1.0',
  String text = 'deploy failed',
  String? channelId = 'C1',
  String? channelName = 'incidents',
  String? user = 'U1',
  String? username = 'lee',
}) {
  return <String, dynamic>{
    'ts': ts,
    'text': text,
    'channel': <String, dynamic>{'id': ?channelId, 'name': ?channelName},
    'user': ?user,
    'username': ?username,
  };
}

void main() {
  group('SearchCommand', () {
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

      when(() => logger.info(any())).thenReturn(null);
      when(() => logger.err(any())).thenReturn(null);
      when(() => httpClient.close()).thenReturn(null);
      when(() => credentialsStore.load()).thenReturn(credentials);

      runner = CommandRunner<int>('test', 'test')
        ..addCommand(
          SearchCommand(
            logger: logger,
            credentialsStore: credentialsStore,
            httpClient: httpClient,
          ),
        );
    });

    /// Answers every GET with [body] and returns the captured request URI
    /// after [args] have run.
    Future<Uri> capturedRequestUri(List<String> args, String body) async {
      when(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => _okResponse(body));

      await runner.run(args);

      final captured = verify(
        () => httpClient.get(captureAny(), headers: any(named: 'headers')),
      ).captured;
      return captured.single as Uri;
    }

    void answerWith(String body) {
      when(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => _okResponse(body));
    }

    test('has correct name and description', () {
      final command = SearchCommand(logger: logger);
      expect(command.name, equals('search'));
      expect(command.description, isNotEmpty);
    });

    test('says in the usage that --query is required', () async {
      // --query is not declared `mandatory: true` (see issue #42), so
      // package:args does not add its own " (mandatory)" marker the way it
      // does for `history -c` and `thread -c`. Without a marker in the help
      // text a reader cannot tell the option is required. The assertion runs
      // against the usage the user is actually shown on a usage error.
      await runner.run(['search']);

      final logged = verify(
        () => logger.info(captureAny()),
      ).captured.cast<String>();

      expect(
        logged.join('\n'),
        contains('Required. The text to search for.'),
      );
    });

    group('argument validation', () {
      const missingQuery =
          'Missing --query. Give the text to search for, '
          'for example: search -q "deploy failed".';

      test('rejects a missing --query with usage, not a stack trace', () async {
        final exitCode = await runner.run(['search']);

        expect(exitCode, equals(ExitCode.usage.code));
        verify(() => logger.err(missingQuery)).called(1);
        verifyNever(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        );
      });

      test('rejects a whitespace-only --query', () async {
        final exitCode = await runner.run(['search', '-q', '   ']);

        expect(exitCode, equals(ExitCode.usage.code));
        verify(() => logger.err(missingQuery)).called(1);
        verifyNever(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        );
      });

      test('rejects an empty --channel', () async {
        final exitCode = await runner.run([
          'search',
          '-q',
          'deploy failed',
          '-c',
          '  ',
        ]);

        expect(exitCode, equals(ExitCode.usage.code));
        verify(
          () => logger.err('Invalid --channel value: it must not be empty.'),
        ).called(1);
        verifyNever(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        );
      });
      test('answers a usage error without reading any credential', () async {
        // Regression test for the review finding on PR #43. Validation used
        // to run inside runAuthenticated, so `search` with no --query and no
        // stored token answered `Not logged in` and exit 67. A usage error
        // must not depend on the auth state.
        final exitCode = await runner.run(['search']);

        expect(exitCode, equals(ExitCode.usage.code));
        verifyNever(() => credentialsStore.load());
        verifyNever(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        );
      });

      test(
        'answers a limit usage error without reading any credential',
        () async {
          final exitCode = await runner.run(['search', '-q', 'hi', '-l', '0']);

          expect(exitCode, equals(ExitCode.usage.code));
          verifyNever(() => credentialsStore.load());
        },
      );

      test(
        'answers a channel usage error without reading any credential',
        () async {
          final exitCode = await runner.run(['search', '-q', 'hi', '-c', ' ']);

          expect(exitCode, equals(ExitCode.usage.code));
          verifyNever(() => credentialsStore.load());
        },
      );
    });

    group('limit handling', () {
      test('rejects a non-positive --limit', () async {
        final exitCode = await runner.run([
          'search',
          '-q',
          'deploy',
          '-l',
          '0',
        ]);

        expect(exitCode, equals(ExitCode.usage.code));
        verify(
          () => logger.err(
            'Invalid --limit value: "0". Use a positive integer.',
          ),
        ).called(1);
        verifyNever(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        );
      });

      test('rejects a non-numeric --limit', () async {
        final exitCode = await runner.run([
          'search',
          '-q',
          'deploy',
          '-l',
          'many',
        ]);

        expect(exitCode, equals(ExitCode.usage.code));
        verify(
          () => logger.err(
            'Invalid --limit value: "many". Use a positive integer.',
          ),
        ).called(1);
      });

      test('sends the default limit of 20 when --limit is omitted', () async {
        final uri = await capturedRequestUri(
          ['search', '-q', 'deploy failed'],
          _searchResponse([_match()]),
        );

        expect(uri.queryParameters['count'], equals('20'));
      });

      test('sends the requested limit as the count parameter', () async {
        final uri = await capturedRequestUri(
          ['search', '-q', 'deploy failed', '-l', '5'],
          _searchResponse([_match()]),
        );

        expect(uri.queryParameters['count'], equals('5'));
      });
    });

    group('channel filtering', () {
      test('adds no modifier when --channel is omitted', () async {
        final uri = await capturedRequestUri(
          ['search', '-q', 'deploy failed'],
          _searchResponse([_match()]),
        );

        expect(uri.queryParameters['query'], equals('deploy failed'));
      });

      test('adds the channel-link modifier for a channel ID', () async {
        final uri = await capturedRequestUri(
          ['search', '-q', 'deploy failed', '-c', 'C1763JQAD'],
          _searchResponse([_match()]),
        );

        expect(
          uri.queryParameters['query'],
          equals('deploy failed in:<#C1763JQAD>'),
        );
      });

      test('adds the name modifier for a channel name', () async {
        final uri = await capturedRequestUri(
          ['search', '-q', 'deploy failed', '-c', 'incidents'],
          _searchResponse([_match()]),
        );

        expect(
          uri.queryParameters['query'],
          equals('deploy failed in:#incidents'),
        );
      });

      test('does not double the # of a channel name typed with one', () async {
        final uri = await capturedRequestUri(
          ['search', '-q', 'deploy failed', '-c', '#incidents'],
          _searchResponse([_match()]),
        );

        expect(
          uri.queryParameters['query'],
          equals('deploy failed in:#incidents'),
        );
      });

      test('keeps the modifiers the user typed in the query', () async {
        final uri = await capturedRequestUri(
          [
            'search',
            '-q',
            'deploy from:@lee after:2026-08-01',
            '-c',
            'C1763JQAD',
          ],
          _searchResponse([_match()]),
        );

        expect(
          uri.queryParameters['query'],
          equals('deploy from:@lee after:2026-08-01 in:<#C1763JQAD>'),
        );
      });
    });

    group('conversation ID recognition', () {
      // `buildQuery` tells an ID from a name with `^[CDG][A-Z0-9]{2,}$`. An
      // ID becomes the channel-link form `in:<#ID>`; anything else becomes
      // the name form `in:#name`. Each case below is chosen so that exactly
      // one relaxation of that pattern would classify it the other way, so
      // the whole pattern is pinned rather than only its happy path.
      const cases = <(String, String, String)>[
        // The `{2,}` bound, from both sides.
        ('C1', 'deploy failed in:#C1', 'one trailing character is too few'),
        (
          'C12',
          'deploy failed in:<#C12>',
          'two trailing characters are enough',
        ),
        (
          'C0123456789AB',
          'deploy failed in:<#C0123456789AB>',
          'the trailing run has no upper bound',
        ),
        // The anchors.
        (
          'C123 x',
          'deploy failed in:#C123 x',
          'an ID must reach the end of the value',
        ),
        (
          'xC123',
          'deploy failed in:#xC123',
          'an ID must start at the start of the value',
        ),
        // The character classes.
        (
          'c0123abcdef',
          'deploy failed in:#c0123abcdef',
          'a lowercase leading letter is a name',
        ),
        (
          'Cabcdef',
          'deploy failed in:#Cabcdef',
          'lowercase after the leading letter is a name',
        ),
        (
          'U0123ABCDEF',
          'deploy failed in:#U0123ABCDEF',
          'a user ID is not a conversation ID',
        ),
        (
          'D0123ABCDEF',
          'deploy failed in:<#D0123ABCDEF>',
          'a direct message ID is a conversation ID',
        ),
        (
          'G0123ABCDEF',
          'deploy failed in:<#G0123ABCDEF>',
          'a private group ID is a conversation ID',
        ),
      ];

      for (final (channel, expected, reason) in cases) {
        test('reads -c "$channel" as $reason', () async {
          final uri = await capturedRequestUri(
            ['search', '-q', 'deploy failed', '-c', channel],
            _searchResponse([_match()]),
          );

          expect(
            uri.queryParameters['query'],
            equals(expected),
            reason: reason,
          );
        });
      }
    });

    group('buildQuery', () {
      // `validateArguments` rejects a blank --channel before the command
      // reaches `buildQuery`, so the CLI cannot exercise these two guards.
      // `buildQuery` is a public static, so they are part of its contract
      // and are tested directly.
      test('returns the query unchanged for a whitespace-only channel', () {
        expect(
          SearchCommand.buildQuery(query: 'deploy failed', channel: '   '),
          equals('deploy failed'),
        );
      });

      test('returns the query unchanged for an empty channel', () {
        expect(
          SearchCommand.buildQuery(query: 'deploy failed', channel: ''),
          equals('deploy failed'),
        );
      });

      test('trims the surrounding whitespace off a channel name', () {
        expect(
          SearchCommand.buildQuery(
            query: 'deploy failed',
            channel: '  incidents  ',
          ),
          equals('deploy failed in:#incidents'),
        );
      });

      test('trims the surrounding whitespace off a channel ID', () {
        expect(
          SearchCommand.buildQuery(
            query: 'deploy failed',
            channel: '  C1763JQAD  ',
          ),
          equals('deploy failed in:<#C1763JQAD>'),
        );
      });
    });

    group('API request', () {
      test('calls search.messages with the query and the first page', () async {
        final uri = await capturedRequestUri(
          ['search', '-q', 'deploy failed'],
          _searchResponse([_match()]),
        );

        expect(uri.host, equals('slack.com'));
        expect(uri.path, equals('/api/search.messages'));
        expect(uri.queryParameters['query'], equals('deploy failed'));
        expect(uri.queryParameters['page'], equals('1'));
      });

      test('sends the bearer token', () async {
        answerWith(_searchResponse([_match()]));

        await runner.run(['search', '-q', 'deploy failed']);

        final captured = verify(
          () => httpClient.get(any(), headers: captureAny(named: 'headers')),
        ).captured;
        expect(
          (captured.single as Map<String, String>)['Authorization'],
          equals('Bearer xoxp-test'),
        );
      });
    });

    group('output', () {
      test(
        'prints channel, timestamp, author and text for each match',
        () async {
          answerWith(
            _searchResponse([
              _match(
                ts: '1234567890.123456',
                text: 'deploy failed on staging',
              ),
              _match(
                ts: '1234567891.000100',
                channelId: 'C2',
                channelName: 'general',
                user: 'U2',
                username: 'sam',
                text: 'deploy failed again',
              ),
            ]),
          );

          final exitCode = await runner.run(['search', '-q', 'deploy failed']);

          expect(exitCode, equals(ExitCode.success.code));
          verify(
            () => logger.info(
              '[#incidents] [1234567890.123456] <lee> deploy failed on staging',
            ),
          ).called(1);
          verify(
            () => logger.info(
              '[#general] [1234567891.000100] <sam> deploy failed again',
            ),
          ).called(1);
        },
      );

      test('falls back to the channel ID and the user ID', () async {
        answerWith(
          _searchResponse([
            _match(channelName: null, username: null, text: 'no names here'),
          ]),
        );

        await runner.run(['search', '-q', 'deploy']);

        verify(() => logger.info('[C1] [1.0] <U1> no names here')).called(1);
      });

      test('falls back to unknown when Slack names neither', () async {
        answerWith(
          _searchResponse([
            _match(
              channelId: null,
              channelName: null,
              user: null,
              username: null,
              text: 'orphan',
            ),
          ]),
        );

        await runner.run(['search', '-q', 'deploy']);

        verify(
          () => logger.info('[unknown] [1.0] <unknown> orphan'),
        ).called(1);
      });

      test('collapses a multi-line match onto one line', () async {
        answerWith(
          _searchResponse([
            _match(text: 'deploy failed\n\n  on   staging\ttonight'),
          ]),
        );

        await runner.run(['search', '-q', 'deploy']);

        verify(
          () => logger.info(
            '[#incidents] [1.0] <lee> deploy failed on staging tonight',
          ),
        ).called(1);
      });

      test('truncates a long match to a 200 character snippet', () async {
        answerWith(_searchResponse([_match(text: 'x' * 250)]));

        await runner.run(['search', '-q', 'deploy']);

        final logged = verify(
          () => logger.info(captureAny()),
        ).captured.cast<String>();
        final line = logged.singleWhere((l) => l.startsWith('[#incidents]'));
        expect(line, equals('[#incidents] [1.0] <lee> ${'x' * 200}…'));
      });

      test(
        'cuts a long emoji match without splitting a surrogate pair',
        () async {
          // A Dart string is indexed in UTF-16 code units, so a naive
          // substring(0, 200) would cut this run of 2-code-unit emoji in half
          // and emit a lone surrogate.
          answerWith(_searchResponse([_match(text: '\u{1F600}' * 250)]));

          await runner.run(['search', '-q', 'deploy']);

          final logged = verify(
            () => logger.info(captureAny()),
          ).captured.cast<String>();
          final line = logged.singleWhere((l) => l.startsWith('[#incidents]'));
          expect(
            line,
            equals('[#incidents] [1.0] <lee> ${'\u{1F600}' * 200}…'),
          );
          expect(
            line.runes.any((r) => r >= 0xD800 && r <= 0xDFFF),
            isFalse,
            reason: 'no lone surrogate may survive the cut',
          );
        },
      );

      test('keeps a match of exactly 200 runes whole', () async {
        answerWith(_searchResponse([_match(text: '\u{1F600}' * 200)]));

        await runner.run(['search', '-q', 'deploy']);

        verify(
          () => logger.info(
            '[#incidents] [1.0] <lee> ${'\u{1F600}' * 200}',
          ),
        ).called(1);
      });

      test('keeps a match of exactly 200 characters whole', () async {
        answerWith(_searchResponse([_match(text: 'x' * 200)]));

        await runner.run(['search', '-q', 'deploy']);

        verify(
          () => logger.info('[#incidents] [1.0] <lee> ${'x' * 200}'),
        ).called(1);
      });

      test('truncates a match of exactly 201 characters', () async {
        // 201 is the only length that separates the real `<= 200` bound from
        // an off-by-one `<= 201`. At 200 both keep the text whole, and at
        // 250 both cut it.
        answerWith(_searchResponse([_match(text: 'x' * 201)]));

        await runner.run(['search', '-q', 'deploy']);

        verify(
          () => logger.info('[#incidents] [1.0] <lee> ${'x' * 200}…'),
        ).called(1);
      });

      test('trims the whitespace around a match', () async {
        // Collapsing runs of whitespace turns "  padded  " into " padded ",
        // which still carries a leading and a trailing space. The trim is
        // what removes them.
        answerWith(_searchResponse([_match(text: '  padded  ')]));

        await runner.run(['search', '-q', 'deploy']);

        verify(() => logger.info('[#incidents] [1.0] <lee> padded')).called(1);
      });

      test('notes when more pages of results exist', () async {
        answerWith(_searchResponse([_match()], pages: 3));

        await runner.run(['search', '-q', 'deploy']);

        verify(() => logger.info('(more results available)')).called(1);
      });

      test('says nothing about more results on the last page', () async {
        // The helper defaults to page 1 of 1, which is the last page.
        answerWith(_searchResponse([_match()]));

        await runner.run(['search', '-q', 'deploy']);

        verifyNever(() => logger.info('(more results available)'));
      });

      test('says nothing about more results when paging is absent', () async {
        answerWith(
          jsonEncode({
            'ok': true,
            'messages': {
              'matches': [_match()],
            },
          }),
        );

        final exitCode = await runner.run(['search', '-q', 'deploy']);

        expect(exitCode, equals(ExitCode.success.code));
        verify(
          () => logger.info('[#incidents] [1.0] <lee> deploy failed'),
        ).called(1);
        verifyNever(() => logger.info('(more results available)'));
      });
    });

    group('empty results', () {
      test('reports that nothing matched', () async {
        answerWith(_searchResponse([]));

        final exitCode = await runner.run(['search', '-q', 'nothing matches']);

        expect(exitCode, equals(ExitCode.success.code));
        verify(() => logger.info('No matching messages found.')).called(1);
      });

      test(
        'reports that nothing matched when Slack omits the matches',
        () async {
          answerWith(jsonEncode({'ok': true, 'messages': <String, dynamic>{}}));

          final exitCode = await runner.run([
            'search',
            '-q',
            'nothing matches',
          ]);

          expect(exitCode, equals(ExitCode.success.code));
          verify(() => logger.info('No matching messages found.')).called(1);
        },
      );
    });

    group('API errors', () {
      test('reports a missing scope and points at login', () async {
        answerWith(
          jsonEncode({
            'ok': false,
            'error': 'missing_scope',
            'needed': 'search:read',
          }),
        );

        final exitCode = await runner.run(['search', '-q', 'deploy']);

        expect(exitCode, equals(ExitCode.software.code));
        verify(() => logger.err('Slack API error: missing_scope')).called(1);
        verify(
          () => logger.err(
            "Missing scope 'search:read'. "
            "Run 'dart_slack login' to re-authorize.",
          ),
        ).called(1);
        verify(
          () => logger.err(
            jsonEncode({'ok': false, 'error': 'missing_scope'}),
          ),
        ).called(1);
      });

      test('reports a rejected token', () async {
        answerWith(jsonEncode({'ok': false, 'error': 'invalid_auth'}));

        final exitCode = await runner.run(['search', '-q', 'deploy']);

        expect(exitCode, equals(ExitCode.software.code));
        verify(() => logger.err('Slack API error: invalid_auth')).called(1);
      });
    });
  });
}
