import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_slack/src/auth/app_config_store.dart';
import 'package:dart_slack/src/cli/slack_app.dart';
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
  StreamCommand({
    required Logger logger,
    http.Client? httpClient,
    @visibleForTesting AppConfigStore? configStore,
    @visibleForTesting WebSocketChannelFactory? channelFactory,
    @visibleForTesting Future<void> Function(Duration)? delay,
    @visibleForTesting Stream<ProcessSignal>? signalStream,
    @visibleForTesting String? appToken,
  })  : _logger = logger,
        _httpClient = httpClient,
        _configStore = configStore ?? AppConfigStore(),
        _channelFactory = channelFactory,
        _delay = delay,
        _signalStream = signalStream,
        _appTokenOverride = appToken {
    argParser.addOption(
      'channel',
      abbr: 'c',
      help: 'The channel ID to stream messages from.',
      mandatory: true,
    );
  }

  final Logger _logger;
  final http.Client? _httpClient;
  final AppConfigStore _configStore;
  final WebSocketChannelFactory? _channelFactory;
  final Future<void> Function(Duration)? _delay;
  final Stream<ProcessSignal>? _signalStream;
  final String? _appTokenOverride;

  @override
  String get description =>
      'Stream messages from a channel via Socket Mode.';

  @override
  String get name => 'stream';

  @override
  Future<int> run() async {
    final channel = argResults!['channel'] as String;

    final appToken = _appTokenOverride ??
        _configStore.load()?.appToken ??
        SlackApp.appTokenOrNull;
    if (appToken == null) {
      _logger.err(
        'App token not configured. '
        'Run "dart_slack configure" or set SLACK_APP_TOKEN.',
      );
      return ExitCode.config.code;
    }

    final client = SocketModeClient(
      appToken: appToken,
      httpClient: _httpClient,
      channelFactory: _channelFactory,
      delay: _delay,
    );

    final stopCompleter = Completer<void>();
    final signalSub =
        (_signalStream ?? ProcessSignal.sigint.watch()).listen((_) {
      if (!stopCompleter.isCompleted) stopCompleter.complete();
    });

    try {
      await client.connect();
      _logger.info('Streaming $channel (Ctrl+C to stop)...');

      final eventSub = client.events
          .where((event) => event.channel == channel)
          .listen((event) {
        final thread =
            event.replyCount != null ? ' [${event.replyCount} replies]' : '';
        _logger.info('<${event.user}> ${event.text}$thread');
      });

      await stopCompleter.future;
      await eventSub.cancel();
    } on SocketModeException catch (e) {
      _logger.err('Socket Mode error: ${e.message}');
      return ExitCode.software.code;
    } finally {
      await signalSub.cancel();
      await client.close();
    }

    return ExitCode.success.code;
  }
}
