import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:dart_slack/src/auth/credentials.dart';
import 'package:dart_slack/src/auth/credentials_store.dart';
import 'package:dart_slack/src/cli/commands/history_command.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger;

class _MockCredentialsStore extends Mock implements CredentialsStore;

class _MockHttpClient extends Mock implements http.Client;

void main() {
  group('HistoryCommand', () {
    late _MockLogger logger;
    late _MockCredentialsStore credentialsStore;
    late _MockHttpClient httpClient;
    late CommandRunner<int> runner;

    const credentials = Credentials(accessToken: 'xoxp-test', userId: 'U123');

    setUpAll(() {
      registerFallbackValue(Uri.parse('https://example.com'));
    });

    setUp(() {
      logger = _MockLogger();
      credentialsStore = _MockCredentialsStore();
      httpClient = _MockHttpClient();

      when(() => logger.info(any())).thenReturn(null);
      when(() => httpClient.close()).thenReturn(null);

      runner = CommandRunner<int>('test', 'test')
        ..addCommand(
          HistoryCommand(
            logger: logger,
            credentialsStore: credentialsStore,
            httpClient: httpClient,
          ),
        );
    });

    /// Answers each `conversations.history` request from [pages], keyed by
    /// the request's `cursor` parameter (`null` for the first request), and
    /// records every request URI.
    List<Uri> stubPages(Map<String?, Map<String, dynamic>> pages) {
      final requests = <Uri>[];
      when(() => credentialsStore.load()).thenReturn(credentials);
      when(() => httpClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((invocation) async {
            final uri = invocation.positionalArguments.first as Uri;
            requests.add(uri);
            final body = pages[uri.queryParameters['cursor']];
            if (body == null) {
              return http.Response(
                jsonEncode({'ok': false, 'error': 'invalid_cursor'}),
                200,
              );
            }
            return http.Response(jsonEncode({'ok': true, ...body}), 200);
          });
      return requests;
    }

    Map<String, dynamic> page(
      List<Map<String, dynamic>> messages, {
      String? next,
    }) => {
      'messages': messages,
      'has_more': next != null,
      if (next != null) 'response_metadata': {'next_cursor': next},
    };

    Map<String, dynamic> msg(String ts, String text) => {
      'ts': ts,
      'text': text,
      'user': 'U1',
    };

    List<Object?> infoLines() =>
        verify(() => logger.info(captureAny())).captured;

    test('has correct name and description', () {
      final command = HistoryCommand(logger: logger);
      expect(command.name, equals('history'));
      expect(command.description, isNotEmpty);
    });

    test('displays messages in chronological order', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);
      when(() => httpClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer(
            (_) async => http.Response(
              jsonEncode({
                'ok': true,
                'messages': [
                  {'ts': '2.0', 'text': 'Second', 'user': 'U2'},
                  {'ts': '1.0', 'text': 'First', 'user': 'U1'},
                ],
                'has_more': false,
              }),
              200,
            ),
          );

      await runner.run(['history', '-c', 'C1']);

      final logged = verify(() => logger.info(captureAny())).captured;
      expect(logged, contains('[1.0] <U1> First'));
      expect(logged, contains('[2.0] <U2> Second'));
      expect(
        logged.indexOf('[1.0] <U1> First'),
        lessThan(logged.indexOf('[2.0] <U2> Second')),
      );
    });

    test('shows thread reply count', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);
      when(() => httpClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer(
            (_) async => http.Response(
              jsonEncode({
                'ok': true,
                'messages': [
                  {
                    'ts': '1.0',
                    'text': 'Thread parent',
                    'user': 'U1',
                    'reply_count': 5,
                  },
                ],
                'has_more': false,
              }),
              200,
            ),
          );

      await runner.run(['history', '-c', 'C1']);

      verify(() => logger.info('[1.0] <U1> Thread parent [5 replies]'))
          .called(1);
    });

    test('shows an attachment indicator for messages with files', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);
      when(() => httpClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer(
            (_) async => http.Response(
              jsonEncode({
                'ok': true,
                'messages': [
                  {
                    'ts': '1.0',
                    'text': 'Here is the spec',
                    'user': 'U1',
                    'files': [
                      {'name': 'spec.pdf'},
                    ],
                  },
                ],
                'has_more': false,
              }),
              200,
            ),
          );

      await runner.run(['history', '-c', 'C1']);

      verify(
        () => logger.info('[1.0] <U1> Here is the spec [attachment: spec.pdf]'),
      ).called(1);
    });

    test('shows empty state message', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);
      when(() => httpClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer(
            (_) async => http.Response(
              jsonEncode({
                'ok': true,
                'messages': <Map<String, dynamic>>[],
                'has_more': false,
              }),
              200,
            ),
          );

      await runner.run(['history', '-c', 'C1']);

      verify(() => logger.info('No messages found.')).called(1);
      verify(() => logger.info('(0 messages returned; no more messages)'))
          .called(1);
    });

    test('rejects invalid limit values', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);
      when(() => logger.err(any())).thenReturn(null);

      final exitCode = await runner.run(['history', '-c', 'C1', '-l', '0']);

      expect(exitCode, equals(ExitCode.usage.code));
      verify(
        () => logger.err('Invalid --limit value: "0". Use a positive integer.'),
      ).called(1);
      verifyNever(() => httpClient.get(any(), headers: any(named: 'headers')));
    });
    test('fills a --limit above one page by following cursors', () async {
      final requests = stubPages({
        null: page([msg('4.0', 'Four'), msg('3.0', 'Three')], next: 'c1'),
        'c1': page([msg('2.0', 'Two'), msg('1.0', 'One')]),
      });

      final exitCode = await runner.run(['history', '-c', 'C1', '-l', '201']);

      expect(exitCode, equals(ExitCode.success.code));
      expect(requests, hasLength(2));
      expect(requests[0].queryParameters['limit'], equals('200'));
      expect(requests[0].queryParameters.containsKey('cursor'), isFalse);
      expect(requests[1].queryParameters['limit'], equals('199'));
      expect(requests[1].queryParameters['cursor'], equals('c1'));
      expect(infoLines(), [
        '[1.0] <U1> One',
        '[2.0] <U1> Two',
        '[3.0] <U1> Three',
        '[4.0] <U1> Four',
        '(4 messages returned; no more messages)',
      ]);
    });

    test('stops at --limit and prints the next cursor', () async {
      final requests = stubPages({
        null: page([msg('2.0', 'Two'), msg('1.0', 'One')], next: 'c2'),
      });

      await runner.run(['history', '-c', 'C1', '-l', '2']);

      expect(requests, hasLength(1));
      expect(requests.single.queryParameters['limit'], equals('2'));
      verify(
        () => logger.info(
          '(2 messages returned; stopped at --limit 2; '
          'more messages available: use --cursor c2)',
        ),
      ).called(1);
    });

    test('reaches an older thread root with --cursor', () async {
      final requests = stubPages({
        'c2': page([
          {...msg('0.5', 'Old root'), 'reply_count': 3},
        ]),
      });

      await runner.run(['history', '-c', 'C1', '--cursor', 'c2']);

      expect(requests.single.queryParameters['cursor'], equals('c2'));
      expect(infoLines(), [
        '[0.5] <U1> Old root [3 replies]',
        '(1 message returned; no more messages)',
      ]);
    });

    test('follows a cursor past an empty page', () async {
      final requests = stubPages({
        null: page([], next: 'c1'),
        'c1': page([msg('1.0', 'One')]),
      });

      await runner.run(['history', '-c', 'C1']);

      expect(requests, hasLength(2));
      expect(infoLines(), [
        '[1.0] <U1> One',
        '(1 message returned; no more messages)',
      ]);
    });

    test('reports more messages on an empty page with has_more', () async {
      stubPages({
        null: {'messages': <Object>[], 'has_more': true},
      });

      await runner.run(['history', '-c', 'C1']);

      const summary =
          '(0 messages returned; more messages available, '
          'but Slack returned no cursor)';
      expect(infoLines(), ['No messages found.', summary]);
    });

    test('stops at the request safety limit on endless empty pages', () async {
      final requests = <Uri>[];
      when(() => credentialsStore.load()).thenReturn(credentials);
      when(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((invocation) async {
        requests.add(invocation.positionalArguments.first as Uri);
        return http.Response(
          jsonEncode({'ok': true, ...page([], next: 'c${requests.length}')}),
          200,
        );
      });

      await runner.run(['history', '-c', 'C1']);

      expect(requests, hasLength(HistoryCommand.maxPages));
      verify(
        () => logger.info(
          '(0 messages returned; stopped at the safety limit of '
          '${HistoryCommand.maxPages} requests; '
          'more messages available: use --cursor c${HistoryCommand.maxPages})',
        ),
      ).called(1);
    });

    test('--all follows cursors until no more messages exist', () async {
      final requests = stubPages({
        null: page([msg('3.0', 'Three')], next: 'c1'),
        'c1': page([msg('2.0', 'Two')], next: 'c2'),
        'c2': page([msg('1.0', 'One')]),
      });

      await runner.run(['history', '-c', 'C1', '--all']);

      expect(requests, hasLength(3));
      expect(
        requests.map((r) => r.queryParameters['limit']),
        everyElement('200'),
      );
      expect(infoLines(), [
        '[1.0] <U1> One',
        '[2.0] <U1> Two',
        '[3.0] <U1> Three',
        '(3 messages returned; no more messages)',
      ]);
    });

    test('--all stops at the message safety limit and says so', () async {
      final requests = <Uri>[];
      when(() => credentialsStore.load()).thenReturn(credentials);
      when(() => httpClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((invocation) async {
            final uri = invocation.positionalArguments.first as Uri;
            requests.add(uri);
            final n = requests.length;
            final size = int.parse(uri.queryParameters['limit']!);
            return http.Response(
              jsonEncode({
                'ok': true,
                ...page([
                  for (var i = 0; i < size; i++) msg('$n.$i', 'm'),
                ], next: 'c$n'),
              }),
              200,
            );
          });

      await runner.run(['history', '-c', 'C1', '--all']);

      const pages = HistoryCommand.safetyLimit ~/ HistoryCommand.pageSize;
      expect(requests, hasLength(pages));
      final lines = infoLines();
      expect(lines, hasLength(HistoryCommand.safetyLimit + 1));
      expect(
        lines.last,
        equals(
          '(${HistoryCommand.safetyLimit} messages returned; '
          'stopped at the --all safety limit of '
          '${HistoryCommand.safetyLimit} messages; '
          'more messages available: use --cursor c$pages)',
        ),
      );
    });

    test('passes --oldest and --latest to every request', () async {
      final requests = stubPages({
        null: page([msg('5.0', 'Five')], next: 'c1'),
        'c1': page([msg('4.0', 'Four')]),
      });

      await runner.run([
        'history',
        '-c',
        'C1',
        '--oldest',
        '1730000000.000100',
        '--latest',
        '1740000000',
      ]);

      expect(requests, hasLength(2));
      for (final request in requests) {
        expect(request.queryParameters['oldest'], equals('1730000000.000100'));
        expect(request.queryParameters['latest'], equals('1740000000'));
      }
    });

    group('usage errors', () {
      setUp(() {
        when(() => credentialsStore.load()).thenReturn(credentials);
        when(() => logger.err(any())).thenReturn(null);
      });

      test('rejects --all with --limit', () async {
        final exitCode = await runner.run([
          'history',
          '-c',
          'C1',
          '--all',
          '-l',
          '5',
        ]);

        expect(exitCode, equals(ExitCode.usage.code));
        verify(() => logger.err('Use either --all or --limit, not both.'))
            .called(1);
        verifyNever(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        );
      });

      test('rejects a --limit above the safety limit', () async {
        final exitCode = await runner.run([
          'history',
          '-c',
          'C1',
          '-l',
          '${HistoryCommand.safetyLimit + 1}',
        ]);

        expect(exitCode, equals(ExitCode.usage.code));
        verifyNever(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        );
      });

      test('rejects a non-numeric --oldest', () async {
        final exitCode = await runner.run([
          'history',
          '-c',
          'C1',
          '--oldest',
          'yesterday',
        ]);

        expect(exitCode, equals(ExitCode.usage.code));
        verify(
          () => logger.err(
            'Invalid --oldest value: "yesterday". Use a Slack timestamp '
            'such as 1730000000.000100.',
          ),
        ).called(1);
        verifyNever(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        );
      });
    });
  });
}
