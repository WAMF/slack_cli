import 'dart:async';
import 'dart:convert';

import 'package:dart_slack/src/socket_mode/socket_mode_event.dart';
import 'package:dart_slack/src/socket_mode/socket_mode_exception.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

/// Factory that creates a [WebSocketChannel] for the given [uri].
typedef WebSocketChannelFactory = WebSocketChannel Function(Uri uri);

class _Backoff {
  static const initialDelay = Duration(seconds: 1);
  static const maxDelay = Duration(seconds: 30);
  static const multiplier = 2;
}

/// Manages a Slack Socket Mode WebSocket connection.
///
/// Connects via `apps.connections.open`, receives event envelopes,
/// acknowledges them, and exposes parsed message events as a stream.
/// Automatically reconnects with exponential backoff on disconnect.
class SocketModeClient {
  /// Creates a [SocketModeClient] authenticated with [appToken].
  SocketModeClient({
    required String appToken,
    http.Client? httpClient,
    WebSocketChannelFactory? channelFactory,
    Future<void> Function(Duration)? delay,
  })  : _appToken = appToken,
        _httpClient = httpClient ?? http.Client(),
        _channelFactory = channelFactory ?? _defaultChannelFactory,
        _delay = delay ?? Future.delayed;

  final String _appToken;
  final http.Client _httpClient;
  final WebSocketChannelFactory _channelFactory;
  final Future<void> Function(Duration) _delay;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  final StreamController<SocketModeEvent> _eventController =
      StreamController<SocketModeEvent>.broadcast();
  Duration _backoffDelay = _Backoff.initialDelay;
  var _closed = false;
  var _reconnecting = false;

  static WebSocketChannel _defaultChannelFactory(Uri uri) =>
      WebSocketChannel.connect(uri);

  /// Stream of parsed message events from Socket Mode.
  Stream<SocketModeEvent> get events => _eventController.stream;

  /// Opens the Socket Mode connection and begins streaming events.
  ///
  /// Throws [SocketModeException] if `apps.connections.open` fails.
  Future<void> connect() async {
    _closed = false;
    await _connectWebSocket();
  }

  /// Closes the WebSocket connection and releases resources.
  Future<void> close() async {
    _closed = true;
    await _subscription?.cancel();
    await _channel?.sink.close();
    await _eventController.close();
    _httpClient.close();
  }

  Future<Uri> _requestWebSocketUrl() async {
    final response = await _httpClient.post(
      Uri.parse('https://slack.com/api/apps.connections.open'),
      headers: {'Authorization': 'Bearer $_appToken'},
    );
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw SocketModeException(
        'apps.connections.open failed: ${json['error']}',
      );
    }
    return Uri.parse(json['url'] as String);
  }

  Future<void> _connectWebSocket() async {
    final wssUrl = await _requestWebSocketUrl();
    _channel = _channelFactory(wssUrl);
    _backoffDelay = _Backoff.initialDelay;

    _subscription = _channel!.stream.listen(
      _onMessage,
      onError: (_) => unawaited(_reconnect()),
      onDone: () => unawaited(_reconnect()),
    );
  }

  void _onMessage(dynamic raw) {
    final json = jsonDecode(raw as String) as Map<String, dynamic>;
    final type = json['type'] as String?;

    switch (type) {
      case 'hello':
        break;
      case 'disconnect':
        unawaited(_reconnect());
      case 'events_api':
        _handleEventsApi(json);
      default:
        _acknowledge(json);
    }
  }

  void _handleEventsApi(Map<String, dynamic> envelope) {
    _acknowledge(envelope);

    final payload = envelope['payload'] as Map<String, dynamic>?;
    final event = payload?['event'] as Map<String, dynamic>?;
    if (event == null) return;

    if (event['type'] != 'message') return;
    if (event.containsKey('subtype')) return;

    if (!_eventController.isClosed) {
      _eventController.add(SocketModeEvent.fromJson(event));
    }
  }

  void _acknowledge(Map<String, dynamic> envelope) {
    final envelopeId = envelope['envelope_id'] as String?;
    if (envelopeId == null) return;
    _channel?.sink.add(jsonEncode({'envelope_id': envelopeId}));
  }

  Future<void> _reconnect() async {
    if (_closed || _reconnecting) return;
    _reconnecting = true;

    await _subscription?.cancel();

    try {
      while (!_closed) {
        try {
          await _delay(_backoffDelay);
          if (_closed) return;
          await _connectWebSocket();
          return;
        } on Exception {
          _backoffDelay = Duration(
            milliseconds:
                (_backoffDelay.inMilliseconds * _Backoff.multiplier)
                    .clamp(0, _Backoff.maxDelay.inMilliseconds),
          );
        }
      }
    } finally {
      _reconnecting = false;
    }
  }
}
