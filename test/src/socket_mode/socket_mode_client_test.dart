import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_slack/src/socket_mode/socket_mode_client.dart';
import 'package:dart_slack/src/socket_mode/socket_mode_event.dart';
import 'package:dart_slack/src/socket_mode/socket_mode_exception.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _MockHttpClient extends Mock implements http.Client;

class _MockWebSocketChannel extends Mock implements WebSocketChannel;

class _MockWebSocketSink extends Mock implements WebSocketSink;

void main() {
  group('SocketModeClient', () {
    late _MockHttpClient httpClient;
    late _MockWebSocketChannel wsChannel;
    late _MockWebSocketSink wsSink;
    late StreamController<dynamic> serverController;

    const appToken = 'xapp-test-token';

    http.Response connectResponse({bool ok = true, String? error}) {
      return http.Response(
        jsonEncode({
          'ok': ok,
          if (ok) 'url': 'wss://example.com/ws',
          'error': ?error,
        }),
        200,
      );
    }

    String envelope(
      String type, {
      String? envelopeId,
      Map<String, dynamic>? payload,
    }) {
      return jsonEncode({
        'type': type,
        'envelope_id': ?envelopeId,
        'payload': ?payload,
      });
    }

    setUpAll(() {
      registerFallbackValue(Uri.parse('https://example.com'));
    });

    setUp(() {
      httpClient = _MockHttpClient();
      wsChannel = _MockWebSocketChannel();
      wsSink = _MockWebSocketSink();
      serverController = StreamController<dynamic>.broadcast();

      when(() => wsChannel.stream).thenAnswer((_) => serverController.stream);
      when(() => wsChannel.sink).thenReturn(wsSink);
      when(() => wsChannel.ready).thenAnswer((_) async {});
      when(() => wsSink.add(any<dynamic>())).thenReturn(null);
      when(() => wsSink.close()).thenAnswer((_) async {});
      when(() => httpClient.close()).thenReturn(null);
      when(() => httpClient.post(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => connectResponse());
    });

    tearDown(() async {
      await serverController.close();
    });

    SocketModeClient buildClient() {
      return SocketModeClient(
        appToken: appToken,
        httpClient: httpClient,
        channelFactory: (_) => wsChannel,
        delay: (_) async {},
      );
    }

    test('requests WSS URL via apps.connections.open', () async {
      final client = buildClient();
      await client.connect();

      final headers =
          verify(
                () => httpClient.post(
                  any(
                    that: predicate<Uri>(
                      (u) => u.path.contains('apps.connections.open'),
                    ),
                  ),
                  headers: captureAny(named: 'headers'),
                ),
              ).captured.first
              as Map<String, String>;

      expect(headers['Authorization'], equals('Bearer $appToken'));

      await client.close();
    });

    test('receives hello envelope without error', () async {
      final client = buildClient();
      await client.connect();

      serverController.add(envelope('hello'));
      await Future<void>.delayed(Duration.zero);

      await client.close();
    });

    test('connect waits for the WebSocket handshake', () async {
      final ready = Completer<void>();
      when(() => wsChannel.ready).thenAnswer((_) => ready.future);
      final client = buildClient();
      var connected = false;
      final connection = client.connect().then((_) => connected = true);

      await Future<void>.delayed(Duration.zero);
      expect(connected, isFalse);

      ready.complete();
      await connection;
      expect(connected, isTrue);

      await client.close();
    });

    test('failed adapter handshake is reported once and cleaned up', () async {
      late IOWebSocketChannel failedChannel;
      final delays = <Duration>[];
      final client = SocketModeClient(
        appToken: appToken,
        httpClient: httpClient,
        channelFactory: (_) => failedChannel = IOWebSocketChannel(
          Future<WebSocket>.error(
            const WebSocketException('Handshake rejected'),
          ),
        ),
        delay: (duration) async => delays.add(duration),
      );

      await expectLater(
        client.connect(),
        throwsA(
          isA<SocketModeException>().having(
            (error) => error.message,
            'message',
            contains('Handshake rejected'),
          ),
        ),
      );
      await expectLater(failedChannel.sink.done, completes);
      expect(delays, isEmpty);
      verify(() => httpClient.post(any(), headers: any(named: 'headers')))
          .called(1);

      await client.close();
    });

    test('parses events_api envelope and emits SocketModeEvent', () async {
      final client = buildClient();
      await client.connect();

      final events = <SocketModeEvent>[];
      client.events.listen(events.add);

      serverController.add(
        envelope(
          'events_api',
          envelopeId: 'env-1',
          payload: {
            'event': {
              'type': 'message',
              'channel': 'C123',
              'user': 'U456',
              'text': 'Hello',
              'ts': '1.0',
            },
          },
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.first.channel, equals('C123'));
      expect(events.first.user, equals('U456'));
      expect(events.first.text, equals('Hello'));

      await client.close();
    });

    test('acknowledges events_api envelope', () async {
      final client = buildClient();
      await client.connect();

      serverController.add(
        envelope(
          'events_api',
          envelopeId: 'env-1',
          payload: {
            'event': {
              'type': 'message',
              'channel': 'C123',
              'user': 'U456',
              'text': 'Hello',
              'ts': '1.0',
            },
          },
        ),
      );

      await Future<void>.delayed(Duration.zero);

      verify(() => wsSink.add(jsonEncode({'envelope_id': 'env-1'}))).called(1);

      await client.close();
    });

    test('filters out non-message events', () async {
      final client = buildClient();
      await client.connect();

      final events = <SocketModeEvent>[];
      client.events.listen(events.add);

      serverController.add(
        envelope(
          'events_api',
          envelopeId: 'env-1',
          payload: {
            'event': {
              'type': 'reaction_added',
              'channel': 'C123',
              'user': 'U456',
              'ts': '1.0',
            },
          },
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(events, isEmpty);

      await client.close();
    });

    test('filters out message subtypes', () async {
      final client = buildClient();
      await client.connect();

      final events = <SocketModeEvent>[];
      client.events.listen(events.add);

      serverController.add(
        envelope(
          'events_api',
          envelopeId: 'env-1',
          payload: {
            'event': {
              'type': 'message',
              'subtype': 'message_changed',
              'channel': 'C123',
              'user': 'U456',
              'text': 'Edited',
              'ts': '1.0',
            },
          },
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(events, isEmpty);

      await client.close();
    });

    test('reconnects on disconnect envelope', () async {
      final client = buildClient();
      await client.connect();

      verify(() => httpClient.post(any(), headers: any(named: 'headers')))
          .called(1);

      serverController.add(envelope('disconnect'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      verify(() => httpClient.post(any(), headers: any(named: 'headers')))
          .called(1);

      await client.close();
    });

    test('reconnects on unexpected WebSocket close', () async {
      final firstController = StreamController<dynamic>.broadcast();
      final secondController = StreamController<dynamic>.broadcast();
      var connectionCount = 0;

      when(() => wsChannel.stream).thenAnswer((_) {
        connectionCount++;
        return connectionCount == 1
            ? firstController.stream
            : secondController.stream;
      });

      final client = buildClient();
      await client.connect();

      verify(() => httpClient.post(any(), headers: any(named: 'headers')))
          .called(1);

      await firstController.close();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      verify(() => httpClient.post(any(), headers: any(named: 'headers')))
          .called(1);

      await client.close();
      await secondController.close();
    });

    test('handshake failures back off until a successful reconnect', () async {
      final delays = <Duration>[];
      final failedChannels = <IOWebSocketChannel>[];
      var connections = 0;
      var readyCalls = 0;
      final recovered = Completer<void>();
      final reconnectedAgain = Completer<void>();
      when(() => wsChannel.ready).thenAnswer((_) async {
        readyCalls++;
        if (readyCalls == 2) recovered.complete();
        if (readyCalls == 3) reconnectedAgain.complete();
      });
      final client = SocketModeClient(
        appToken: appToken,
        httpClient: httpClient,
        channelFactory: (_) {
          connections++;
          if (connections == 2 || connections == 3) {
            final failedChannel = IOWebSocketChannel(
              Future<WebSocket>.error(
                const WebSocketException('Handshake rejected'),
              ),
            );
            failedChannels.add(failedChannel);
            return failedChannel;
          }
          return wsChannel;
        },
        delay: (duration) async => delays.add(duration),
      );
      await client.connect();

      serverController.add(envelope('disconnect'));
      await recovered.future;
      await Future<void>.delayed(Duration.zero);

      expect(connections, equals(4));
      expect(delays, [
        const Duration(seconds: 1),
        const Duration(seconds: 2),
        const Duration(seconds: 4),
      ]);
      for (final channel in failedChannels) {
        await expectLater(channel.sink.done, completes);
      }
      verify(() => wsSink.close()).called(1);

      serverController.add(envelope('disconnect'));
      await reconnectedAgain.future;
      await Future<void>.delayed(Duration.zero);

      expect(connections, equals(5));
      expect(delays.last, equals(const Duration(seconds: 1)));
      await client.close();
    });

    test('throws SocketModeException on API failure', () async {
      when(() => httpClient.post(any(), headers: any(named: 'headers')))
          .thenAnswer(
            (_) async => connectResponse(ok: false, error: 'invalid_auth'),
          );

      final client = buildClient();

      expect(
        client.connect,
        throwsA(
          isA<SocketModeException>().having(
            (e) => e.message,
            'message',
            contains('invalid_auth'),
          ),
        ),
      );

      await client.close();
    });

    test('close prevents reconnection', () async {
      final client = buildClient();
      await client.connect();

      verify(() => httpClient.post(any(), headers: any(named: 'headers')))
          .called(1);

      await client.close();

      verify(() => httpClient.close()).called(1);
      verifyNoMoreInteractions(httpClient);
    });

    test('close during a URL request does not open a WebSocket', () async {
      final response = Completer<http.Response>();
      when(() => httpClient.post(any(), headers: any(named: 'headers')))
          .thenAnswer((_) => response.future);
      final client = buildClient();
      final connection = client.connect();

      await client.close();
      response.complete(connectResponse());
      await connection;

      verifyZeroInteractions(wsChannel);
    });

    test('close during backoff prevents another connection attempt', () async {
      final delayStarted = Completer<void>();
      final delayFinished = Completer<void>();
      final client = SocketModeClient(
        appToken: appToken,
        httpClient: httpClient,
        channelFactory: (_) => wsChannel,
        delay: (_) {
          delayStarted.complete();
          return delayFinished.future;
        },
      );
      await client.connect();

      serverController.add(envelope('disconnect'));
      await delayStarted.future;
      await client.close();
      delayFinished.complete();
      await Future<void>.delayed(Duration.zero);

      verify(() => httpClient.post(any(), headers: any(named: 'headers')))
          .called(1);
      verify(() => wsSink.close()).called(1);
    });
  });
}
