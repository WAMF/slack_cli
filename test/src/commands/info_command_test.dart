import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:dart_slack/src/auth/credentials.dart';
import 'package:dart_slack/src/auth/credentials_store.dart';
import 'package:dart_slack/src/cli/commands/info_command.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockCredentialsStore extends Mock implements CredentialsStore {}

class _MockHttpClient extends Mock implements http.Client {}

void main() {
  group('InfoCommand', () {
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
      when(() => httpClient.close()).thenReturn(null);

      runner = CommandRunner<int>('test', 'test')
        ..addCommand(
          InfoCommand(
            logger: logger,
            credentialsStore: credentialsStore,
            httpClient: httpClient,
          ),
        );
    });

    test('has correct name and description', () {
      final command = InfoCommand(logger: logger);
      expect(command.name, equals('info'));
      expect(command.description, isNotEmpty);
    });

    /// Stubs `httpClient.get` to answer `conversations.info` with
    /// [channelJson] and `conversations.members` by paginating [members],
    /// dispatching on the request path the same way the real Slack API
    /// endpoints differ.
    void stubChannel(
      Map<String, dynamic> channelJson,
      List<String> members,
    ) {
      when(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((invocation) async {
        final uri = invocation.positionalArguments.first as Uri;
        if (uri.path.endsWith('conversations.info')) {
          return http.Response(
            jsonEncode({'ok': true, 'channel': channelJson}),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'ok': true,
            'members': members,
            'response_metadata': {'next_cursor': ''},
          }),
          200,
        );
      });
    }

    test('displays channel details', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);
      stubChannel(
        {
          'id': 'C1',
          'name': 'general',
          'is_private': false,
          'topic': {'value': 'Announcements'},
          'purpose': {'value': 'General chat'},
          'num_members': 0,
          'is_archived': false,
        },
        ['U1', 'U2'],
      );

      await runner.run(['info', '-c', 'C1']);

      verify(() => logger.info('# general  (C1)')).called(1);
      verify(() => logger.info('  Topic: Announcements')).called(1);
      verify(() => logger.info('  Purpose: General chat')).called(1);
      verify(() => logger.info('  Members: 2')).called(1);
    });

    test(
      'reports the real member count when conversations.info under-counts',
      () async {
        when(() => credentialsStore.load()).thenReturn(credentials);
        // Regression for #27: `conversations.info`'s `num_members` reported
        // 0 for a channel that `conversations.members` correctly lists as
        // having 8 members. `info` must count via the same `members` call
        // rather than trusting the stale/unpopulated `num_members` field.
        stubChannel(
          {
            'id': 'C0BHBD22P5M',
            'name': 'feature-conversations',
            'is_private': false,
            'num_members': 0,
          },
          ['U1', 'U2', 'U3', 'U4', 'U5', 'U6', 'U7', 'U8'],
        );

        await runner.run(['info', '-c', 'C0BHBD22P5M']);

        verify(() => logger.info('  Members: 8')).called(1);
      },
    );

    test('sums member count across paginated members pages', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);
      when(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((invocation) async {
        final uri = invocation.positionalArguments.first as Uri;
        if (uri.path.endsWith('conversations.info')) {
          return http.Response(
            jsonEncode({
              'ok': true,
              'channel': {'id': 'C1', 'name': 'general', 'is_private': false},
            }),
            200,
          );
        }

        final cursor = uri.queryParameters['cursor'];
        if (cursor == null) {
          return http.Response(
            jsonEncode({
              'ok': true,
              'members': ['U1', 'U2'],
              'response_metadata': {'next_cursor': 'page-2'},
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'ok': true,
            'members': ['U3'],
            'response_metadata': {'next_cursor': ''},
          }),
          200,
        );
      });

      await runner.run(['info', '-c', 'C1']);

      verify(() => logger.info('  Members: 3')).called(1);
    });

    test('shows archived status', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);
      stubChannel({
        'id': 'C2',
        'name': 'old',
        'is_private': false,
        'is_archived': true,
        'num_members': 0,
      }, <String>[]);

      await runner.run(['info', '-c', 'C2']);

      verify(() => logger.info('  Archived: yes')).called(1);
      verify(() => logger.info('  Members: 0')).called(1);
    });
  });
}
