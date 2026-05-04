import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_slack/src/auth/credentials.dart';
import 'package:dart_slack/src/auth/credentials_store.dart';
import 'package:dart_slack/src/cli/commands/watch_command.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockCredentialsStore extends Mock implements CredentialsStore {}

class _MockHttpClient extends Mock implements http.Client {}

void main() {
  group('WatchCommand', () {
    late _MockLogger logger;
    late _MockCredentialsStore credentialsStore;
    late _MockHttpClient httpClient;
    late StreamController<ProcessSignal> signalController;

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
      signalController = StreamController<ProcessSignal>.broadcast();

      when(() => logger.info(any())).thenReturn(null);
      when(() => logger.err(any())).thenReturn(null);
      when(() => httpClient.close()).thenReturn(null);
    });

    tearDown(() async {
      await signalController.close();
    });

    CommandRunner<int> buildRunner({
      Future<void> Function(Duration)? delay,
    }) {
      return CommandRunner<int>('test', 'test')..addCommand(
        WatchCommand(
          logger: logger,
          credentialsStore: credentialsStore,
          httpClient: httpClient,
          delay: delay ?? (_) async {},
          signalStream: signalController.stream,
        ),
      );
    }

    http.Response historyResponse(
      List<Map<String, dynamic>> messages, {
      bool hasMore = false,
    }) {
      return http.Response(
        jsonEncode({
          'ok': true,
          'messages': messages,
          'has_more': hasMore,
        }),
        200,
      );
    }

    test('has correct name and description', () {
      final command = WatchCommand(logger: logger);
      expect(command.name, equals('watch'));
      expect(command.description, isNotEmpty);
    });

    test('shows initial context messages on start', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);
      when(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer(
        (_) async => historyResponse([
          {'ts': '2.0', 'text': 'Second', 'user': 'U2'},
          {'ts': '1.0', 'text': 'First', 'user': 'U1'},
        ]),
      );

      final runner = buildRunner(
        delay: (_) async {
          signalController.add(ProcessSignal.sigint);
        },
      );

      await runner.run(['watch', '-c', 'C1']);

      final logged = verify(() => logger.info(captureAny())).captured;
      expect(logged, contains('<U1> First'));
      expect(logged, contains('<U2> Second'));
      expect(
        logged.indexOf('<U1> First'),
        lessThan(logged.indexOf('<U2> Second')),
      );
    });

    test('polls for new messages with correct oldest param', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);

      var callCount = 0;
      when(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async {
        callCount++;
        if (callCount == 1) {
          return historyResponse([
            {'ts': '2.0', 'text': 'Initial', 'user': 'U1'},
          ]);
        }
        return historyResponse([
          {'ts': '3.0', 'text': 'New message', 'user': 'U2'},
        ]);
      });

      final runner = buildRunner(
        delay: (_) async {
          if (callCount >= 2) {
            signalController.add(ProcessSignal.sigint);
          }
        },
      );

      await runner.run(['watch', '-c', 'C1']);

      final uris = verify(
        () => httpClient.get(captureAny(), headers: any(named: 'headers')),
      ).captured.cast<Uri>();

      expect(uris[0].queryParameters.containsKey('oldest'), isFalse);
      expect(uris[1].queryParameters['oldest'], equals('2.0'));

      verify(() => logger.info('<U2> New message')).called(1);
    });

    test('silent on empty polls', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);

      var callCount = 0;
      when(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async {
        callCount++;
        if (callCount == 1) {
          return historyResponse([
            {'ts': '1.0', 'text': 'Initial', 'user': 'U1'},
          ]);
        }
        return historyResponse([]);
      });

      final runner = buildRunner(
        delay: (_) async {
          if (callCount >= 2) {
            signalController.add(ProcessSignal.sigint);
          }
        },
      );

      await runner.run(['watch', '-c', 'C1']);

      final logged = verify(
        () => logger.info(captureAny()),
      ).captured.cast<String>();
      final messageLines = logged.where((l) => l.startsWith('<')).toList();
      expect(messageLines, hasLength(1));
      expect(messageLines.first, equals('<U1> Initial'));
    });

    test('exits cleanly on SIGINT', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);
      when(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer(
        (_) async => historyResponse([]),
      );

      final runner = buildRunner(
        delay: (_) async {
          signalController.add(ProcessSignal.sigint);
        },
      );
      final exitCode = await runner.run(['watch', '-c', 'C1']);

      expect(exitCode, equals(ExitCode.success.code));
    });

    test('handles empty channel', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);
      when(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer(
        (_) async => historyResponse([]),
      );

      final runner = buildRunner(
        delay: (_) async {
          signalController.add(ProcessSignal.sigint);
        },
      );

      await runner.run(['watch', '-c', 'C1']);

      final logged = verify(
        () => logger.info(captureAny()),
      ).captured.cast<String>();
      expect(logged, contains('Watching C1 (Ctrl+C to stop)...'));
      expect(logged.where((l) => l.startsWith('<')), isEmpty);
    });

    test('respects custom interval', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);
      when(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer(
        (_) async => historyResponse([]),
      );

      Duration? capturedDuration;
      final runner = buildRunner(
        delay: (d) async {
          capturedDuration = d;
          signalController.add(ProcessSignal.sigint);
        },
      );

      await runner.run(['watch', '-c', 'C1', '-i', '10']);

      expect(capturedDuration, equals(const Duration(seconds: 10)));
    });

    test('respects custom initial count', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);
      when(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer(
        (_) async => historyResponse([]),
      );

      final runner = buildRunner(
        delay: (_) async {
          signalController.add(ProcessSignal.sigint);
        },
      );

      await runner.run(['watch', '-c', 'C1', '-n', '5']);

      final uri =
          verify(
                () => httpClient.get(
                  captureAny(),
                  headers: any(named: 'headers'),
                ),
              ).captured.first
              as Uri;

      expect(uri.queryParameters['limit'], equals('5'));
    });

    test('rejects invalid interval values', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);

      final runner = buildRunner();
      final exitCode = await runner.run(['watch', '-c', 'C1', '-i', '0']);

      expect(exitCode, equals(ExitCode.usage.code));
      verify(
        () => logger.err(
          'Invalid --interval value: "0". Use a positive integer.',
        ),
      ).called(1);
      verifyNever(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      );
    });

    test('rejects invalid count values', () async {
      when(() => credentialsStore.load()).thenReturn(credentials);

      final runner = buildRunner();
      final exitCode = await runner.run(['watch', '-c', 'C1', '-n', '-1']);

      expect(exitCode, equals(ExitCode.usage.code));
      verify(
        () =>
            logger.err('Invalid --count value: "-1". Use a positive integer.'),
      ).called(1);
      verifyNever(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      );
    });
  });
}
