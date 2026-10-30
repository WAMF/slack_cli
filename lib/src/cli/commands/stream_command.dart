import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_slack/src/auth/app_config_store.dart';
import 'package:dart_slack/src/cli/slack_app.dart';
import 'package:dart_slack/src/cli/stream_lock.dart';
import 'package:dart_slack/src/socket_mode/socket_mode.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';

/// `dart_slack stream --channel <id>`
///
/// Streams messages from a Slack channel in real time via Socket Mode.
/// Requires an app-level token (`xapp-*`), configured via
/// `dart_slack configure`, the `SLACK_APP_TOKEN` env var, or a `.env` file.
/// Runs until interrupted with Ctrl+C.
class StreamCommand extends Command<int> {
  /// Creates a [StreamCommand].
  new({
    required this._logger,
    this._httpClient,
    @visibleForTesting AppConfigStore? configStore,
    @visibleForTesting String? Function()? appTokenProvider,
    @visibleForTesting this._channelFactory,
    @visibleForTesting this._delay,
    @visibleForTesting this._signalStream,
    @visibleForTesting String? appToken,
    @visibleForTesting this._lockDirectory,
  }) : _configStore = configStore ?? AppConfigStore(),
       _appTokenProvider = appTokenProvider ?? (() => SlackApp.appTokenOrNull),
       _appTokenOverride = appToken {
    argParser.addMultiOption(
      'channel',
      abbr: 'c',
      help: 'Channel IDs to stream. Repeat -c to watch several channels.',
    );
  }

  final Logger _logger;
  final http.Client? _httpClient;
  final AppConfigStore _configStore;
  final String? Function() _appTokenProvider;
  final WebSocketChannelFactory? _channelFactory;
  final Future<void> Function(Duration)? _delay;
  final Stream<ProcessSignal>? _signalStream;
  final String? _appTokenOverride;
  final Directory? _lockDirectory;

  @override
  String get description => 'Stream messages from a channel via Socket Mode.';

  @override
  String get name => 'stream';

  @override
  Future<int> run() async {
    final channels = (argResults!['channel'] as List<String>)
        .map((channel) => channel.trim())
        .toSet();
    if (channels.isEmpty) usageException('Option channel is mandatory.');
    if (channels.contains('')) {
      usageException('Provide a non-empty channel ID.');
    }

    final appToken =
        _appTokenOverride ??
        _configStore.load()?.appToken ??
        _appTokenProvider();
    if (appToken == null) {
      _logger.err(
        'App token not configured. '
        'Run "dart_slack configure" or set SLACK_APP_TOKEN.',
      );
      return ExitCode.config.code;
    }

    final StreamLock? streamLock;
    try {
      streamLock = StreamLock.acquire(directory: _lockDirectory);
    } on FileSystemException catch (e) {
      _logger.err('Cannot reserve the local stream listener: ${e.message}');
      return ExitCode.cantCreate.code;
    }
    if (streamLock == null) {
      _logger.err(
        'Another local stream is already running. Stop it first, or watch '
        'all channels in one command: dart_slack stream -c C1 -c C2.',
      );
      return ExitCode.tempFail.code;
    }
    try {
      return await _stream(channels, appToken);
    } finally {
      streamLock.close();
    }
  }

  Future<int> _stream(Set<String> channels, String appToken) async {
    final client = SocketModeClient(
      appToken: appToken,
      httpClient: _httpClient,
      channelFactory: _channelFactory,
      delay: _delay,
    );

    final stopCompleter = Completer<void>();
    final signalSub = (_signalStream ?? ProcessSignal.sigint.watch()).listen((
      _,
    ) {
      if (!stopCompleter.isCompleted) stopCompleter.complete();
    });
    StreamSubscription<SocketModeEvent>? eventSub;

    try {
      eventSub = client.events
          .where((event) => channels.contains(event.channel))
          .listen((event) {
            final thread = event.replyCount != null
                ? ' [${event.replyCount} replies]'
                : '';
            final prefix = channels.length > 1 ? '[${event.channel}] ' : '';
            _logger.info('$prefix<${event.user}> ${event.text}$thread');
          });

      await client.connect();
      _logger.info('Streaming ${channels.join(', ')} (Ctrl+C to stop)...');

      await stopCompleter.future;
    } on SocketModeException catch (e) {
      _logger.err('Socket Mode error: ${e.message}');
      return ExitCode.software.code;
    } on Exception catch (e) {
      _logger.err('Unexpected stream error: $e');
      return ExitCode.software.code;
    } finally {
      await eventSub?.cancel();
      await signalSub.cancel();
      await client.close();
    }

    return ExitCode.success.code;
  }
}
