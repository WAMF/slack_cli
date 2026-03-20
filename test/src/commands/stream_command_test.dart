import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_slack/src/auth/app_config.dart';
import 'package:dart_slack/src/auth/app_config_store.dart';
import 'package:dart_slack/src/cli/commands/stream_command.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _MockLogger extends Mock implements Logger {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockWebSocketChannel extends Mock implements WebSocketChannel {}

class _MockAppConfigStore extends Mock implements AppConfigStore {}

class _MockWebSocketSink extends Mock implements WebSocketSink {}

void main() {
  group('StreamCommand', () {
    late _MockLogger logger;
    late _MockHttpClient httpClient;
    late _MockWebSocketChannel wsChannel;
    late _MockWebSocketSink wsSink;
    late StreamController<dynamic> serverController;
    late StreamController<ProcessSignal> signalController;

    const appToken = 'xapp-test-token';

    setUpAll(() {
      registerFallbackValue(Uri.parse('https://example.com'));
    });

    setUp(() {
      logger = _MockLogger();
      httpClient = _MockHttpClient();
      wsChannel = _MockWebSocketChannel();
      wsSink = _MockWebSocketSink();
      serverController = StreamController<dynamic>.broadcast();
      signalController = StreamController<ProcessSignal>.broadcast();

      when(() => logger.info(any())).thenReturn(null);
      when(() => logger.err(any())).thenReturn(null);
      when(() => wsChannel.stream).thenAnswer((_) => serverController.stream);
      when(() => wsChannel.sink).thenReturn(wsSink);
      when(() => wsSink.add(any<dynamic>())).thenReturn(null);
      when(() => wsSink.close()).thenAnswer((_) async {});
      when(() => httpClient.close()).thenReturn(null);
      when(
        () => httpClient.post(any(), headers: any(named: 'headers')),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({'ok': true, 'url': 'wss://example.com/ws'}),
          200,
        ),
      );
    });

    tearDown(() async {
      await serverController.close();
      await signalController.close();
    });

    CommandRunner<int> buildRunner() {
      return CommandRunner<int>('test', 'test')..addCommand(
        StreamCommand(
          logger: logger,
          httpClient: httpClient,
          channelFactory: (_) => wsChannel,
          delay: (_) async {},
          signalStream: signalController.stream,
          appToken: appToken,
        ),
      );
    }

    test('has correct name and description', () {
      final command = StreamCommand(logger: logger);
      expect(command.name, equals('stream'));
      expect(command.description, isNotEmpty);
    });

    test('displays events matching channel filter', () async {
      final runner = buildRunner();
      final resultFuture = runner.run(['stream', '-c', 'C123']);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      serverController.add(
        jsonEncode({
          'type': 'events_api',
          'envelope_id': 'env-1',
          'payload': {
            'event': {
              'type': 'message',
              'channel': 'C123',
              'user': 'U456',
              'text': 'Hello',
              'ts': '1.0',
            },
          },
        }),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      signalController.add(ProcessSignal.sigint);

      final exitCode = await resultFuture;
      expect(exitCode, equals(ExitCode.success.code));

      verify(() => logger.info('<U456> Hello')).called(1);
    });

    test('ignores events from other channels', () async {
      final runner = buildRunner();
      final resultFuture = runner.run(['stream', '-c', 'C123']);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      serverController.add(
        jsonEncode({
          'type': 'events_api',
          'envelope_id': 'env-1',
          'payload': {
            'event': {
              'type': 'message',
              'channel': 'C999',
              'user': 'U456',
              'text': 'Wrong channel',
              'ts': '1.0',
            },
          },
        }),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      signalController.add(ProcessSignal.sigint);

      await resultFuture;

      verifyNever(() => logger.info('<U456> Wrong channel'));
    });

    test('displays thread reply count', () async {
      final runner = buildRunner();
      final resultFuture = runner.run(['stream', '-c', 'C123']);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      serverController.add(
        jsonEncode({
          'type': 'events_api',
          'envelope_id': 'env-1',
          'payload': {
            'event': {
              'type': 'message',
              'channel': 'C123',
              'user': 'U456',
              'text': 'Thread parent',
              'ts': '1.0',
              'reply_count': 3,
            },
          },
        }),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      signalController.add(ProcessSignal.sigint);

      await resultFuture;

      verify(() => logger.info('<U456> Thread parent [3 replies]')).called(1);
    });

    test('exits cleanly on SIGINT', () async {
      final runner = buildRunner();
      final resultFuture = runner.run(['stream', '-c', 'C123']);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      signalController.add(ProcessSignal.sigint);

      final exitCode = await resultFuture;
      expect(exitCode, equals(ExitCode.success.code));
    });

    test('returns config exit code when app token missing', () async {
      final runner = CommandRunner<int>('test', 'test')
        ..addCommand(
          StreamCommand(
            logger: logger,
            signalStream: signalController.stream,
          ),
        );

      final exitCode = await runner.run(['stream', '-c', 'C123']);
      expect(exitCode, equals(ExitCode.config.code));

      verify(
        () => logger.err(any(that: contains('SLACK_APP_TOKEN'))),
      ).called(1);
    });

    test('uses token from AppConfigStore when available', () async {
      final configStore = _MockAppConfigStore();
      when(configStore.load).thenReturn(
        const AppConfig(appToken: 'xapp-config-store-token'),
      );

      final runner = CommandRunner<int>('test', 'test')
        ..addCommand(
          StreamCommand(
            logger: logger,
            httpClient: httpClient,
            configStore: configStore,
            channelFactory: (_) => wsChannel,
            delay: (_) async {},
            signalStream: signalController.stream,
          ),
        );

      final resultFuture = runner.run(['stream', '-c', 'C123']);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      signalController.add(ProcessSignal.sigint);

      final exitCode = await resultFuture;
      expect(exitCode, equals(ExitCode.success.code));

      verify(configStore.load).called(1);
    });

    test('returns config exit code when config store is empty', () async {
      final configStore = _MockAppConfigStore();
      when(configStore.load).thenReturn(null);

      final runner = CommandRunner<int>('test', 'test')
        ..addCommand(
          StreamCommand(
            logger: logger,
            configStore: configStore,
            signalStream: signalController.stream,
          ),
        );

      final exitCode = await runner.run(['stream', '-c', 'C123']);
      expect(exitCode, equals(ExitCode.config.code));

      verify(configStore.load).called(1);
      verify(
        () => logger.err(any(that: contains('dart_slack configure'))),
      ).called(1);
    });

    test('returns software exit code on SocketModeException', () async {
      when(
        () => httpClient.post(any(), headers: any(named: 'headers')),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({'ok': false, 'error': 'invalid_auth'}),
          200,
        ),
      );

      final runner = buildRunner();
      final exitCode = await runner.run(['stream', '-c', 'C123']);

      expect(exitCode, equals(ExitCode.software.code));

      verify(
        () => logger.err(any(that: contains('Socket Mode error'))),
      ).called(1);
    });
  });
}
