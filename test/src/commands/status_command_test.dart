import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:dart_slack/src/auth/credentials.dart';
import 'package:dart_slack/src/auth/credentials_store.dart';
import 'package:dart_slack/src/cli/commands/status_command.dart';
import 'package:dart_slack/src/slack_api/slack_urls.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockCredentialsStore extends Mock implements CredentialsStore {}

class _MockHttpClient extends Mock implements http.Client {}

void main() {
  group('StatusCommand', () {
    late _MockLogger logger;
    late _MockCredentialsStore credentialsStore;
    late _MockHttpClient httpClient;
    late CommandRunner<int> runner;

    const credentials = Credentials(accessToken: 'xoxp-test', userId: 'U123');

    final fixedNow = DateTime.utc(2026, 6, 12, 10);

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
          StatusCommand(
            logger: logger,
            credentialsStore: credentialsStore,
            httpClient: httpClient,
            now: () => fixedNow,
          ),
        );
    });

    Map<String, dynamic> capturedProfile() {
      final captured = verify(
        () => httpClient.post(
          captureAny(),
          headers: any(named: 'headers'),
          body: captureAny(named: 'body'),
        ),
      ).captured;
      expect(captured[0], equals(SlackUrls.usersProfileSet));
      final body = jsonDecode(captured[1] as String) as Map<String, dynamic>;
      return body['profile'] as Map<String, dynamic>;
    }

    void stubOk() {
      when(
        () => httpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => http.Response(jsonEncode({'ok': true}), 200));
    }

    test('has correct name and description', () {
      final command = StatusCommand(logger: logger);
      expect(command.name, equals('status'));
      expect(command.description, isNotEmpty);
      expect(command.subcommands.keys, containsAll(<String>['set', 'clear']));
    });

    group('set', () {
      test('sets text, emoji, and no expiration by default', () async {
        stubOk();

        final exitCode = await runner.run([
          'status',
          'set',
          '--text',
          'Working on a task',
          '--emoji',
          ':gear:',
        ]);

        expect(exitCode, equals(ExitCode.success.code));
        final profile = capturedProfile();
        expect(profile['status_text'], equals('Working on a task'));
        expect(profile['status_emoji'], equals(':gear:'));
        expect(profile['status_expiration'], equals(0));
        verify(
          () => logger.info('Status set: :gear: Working on a task'),
        ).called(1);
      });

      test('computes status_expiration from --expires-in', () async {
        stubOk();

        final exitCode = await runner.run([
          'status',
          'set',
          '-t',
          'Working',
          '-x',
          '6h',
        ]);

        expect(exitCode, equals(ExitCode.success.code));
        final profile = capturedProfile();
        final expected =
            fixedNow.add(const Duration(hours: 6)).millisecondsSinceEpoch ~/
            1000;
        expect(profile['status_expiration'], equals(expected));
      });

      test('treats a bare number as seconds', () async {
        stubOk();

        await runner.run(['status', 'set', '-t', 'Working', '-x', '90']);

        final profile = capturedProfile();
        final expected =
            fixedNow.add(const Duration(seconds: 90)).millisecondsSinceEpoch ~/
            1000;
        expect(profile['status_expiration'], equals(expected));
      });

      test('rejects an invalid --expires-in value', () async {
        await expectLater(
          runner.run(['status', 'set', '-t', 'Working', '-x', 'tomorrow']),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              contains('Invalid --expires-in value'),
            ),
          ),
        );
        verifyNever(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        );
      });

      test('rejects blank status text', () async {
        await expectLater(
          runner.run(['status', 'set', '-t', '   ']),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              contains('non-empty --text'),
            ),
          ),
        );
        verifyNever(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        );
      });

      test('rejects blank status emoji when provided', () async {
        await expectLater(
          runner.run(['status', 'set', '-t', 'Working', '-e', '   ']),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              contains('non-empty --emoji'),
            ),
          ),
        );
        verifyNever(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        );
      });

      test('explains not_allowed_token_type for bot tokens', () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({'ok': false, 'error': 'not_allowed_token_type'}),
            200,
          ),
        );

        final exitCode = await runner.run(['status', 'set', '-t', 'Working']);

        expect(exitCode, equals(ExitCode.software.code));
        verify(
          () => logger.err(any(that: contains('requires a user token'))),
        ).called(1);
      });

      test('surfaces other API errors via the shared handler', () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({'ok': false, 'error': 'fatal_error'}),
            200,
          ),
        );

        final exitCode = await runner.run(['status', 'set', '-t', 'Working']);

        expect(exitCode, equals(ExitCode.software.code));
        verify(() => logger.err('Slack API error: fatal_error')).called(1);
      });
    });

    group('parseDuration', () {
      test('parses unit suffixes', () {
        expect(
          StatusSetCommand.parseDuration('90s'),
          equals(const Duration(seconds: 90)),
        );
        expect(
          StatusSetCommand.parseDuration('45m'),
          equals(const Duration(minutes: 45)),
        );
        expect(
          StatusSetCommand.parseDuration('6h'),
          equals(const Duration(hours: 6)),
        );
        expect(
          StatusSetCommand.parseDuration('1d'),
          equals(const Duration(days: 1)),
        );
        expect(
          StatusSetCommand.parseDuration('3600'),
          equals(const Duration(seconds: 3600)),
        );
      });

      test('rejects malformed input', () {
        expect(StatusSetCommand.parseDuration(''), isNull);
        expect(StatusSetCommand.parseDuration('h6'), isNull);
        expect(StatusSetCommand.parseDuration('6 h'), isNull);
        expect(StatusSetCommand.parseDuration('-5m'), isNull);
        expect(StatusSetCommand.parseDuration('1.5h'), isNull);
        expect(StatusSetCommand.parseDuration('1 2h'), isNull);
        expect(StatusSetCommand.parseDuration('tomorrow'), isNull);
      });
    });

    group('clear', () {
      test('clears the status', () async {
        stubOk();

        final exitCode = await runner.run(['status', 'clear']);

        expect(exitCode, equals(ExitCode.success.code));
        final profile = capturedProfile();
        expect(profile['status_text'], isEmpty);
        expect(profile['status_emoji'], isEmpty);
        expect(profile['status_expiration'], equals(0));
        verify(() => logger.info('Status cleared.')).called(1);
      });
    });
  });
}
