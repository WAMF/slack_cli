import 'dart:async';
import 'dart:io';

import 'package:dart_slack/src/cli/commands/authenticated_command.dart';
import 'package:dart_slack/src/models/slack_message.dart';
import 'package:dart_slack/src/slack.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';

class _Defaults {
  static const interval = '5';
  static const initialCount = '10';
}

/// `dart_slack watch --channel <id> [--interval <s>] [--count <n>]`
///
/// Watches a Slack channel for new messages, polling at a configurable
/// interval. Runs until interrupted with Ctrl+C.
class WatchCommand extends AuthenticatedCommand {
  /// Creates a [WatchCommand].
  WatchCommand({
    required super.logger,
    super.credentialsStore,
    super.httpClient,
    @visibleForTesting Future<void> Function(Duration)? delay,
    @visibleForTesting Stream<ProcessSignal>? signalStream,
  }) : _delay = delay ?? Future.delayed,
       _signalStream = signalStream {
    argParser
      ..addOption(
        'channel',
        abbr: 'c',
        help: 'The channel ID to watch.',
        mandatory: true,
      )
      ..addOption(
        'interval',
        abbr: 'i',
        help: 'Poll interval in seconds.',
        defaultsTo: _Defaults.interval,
      )
      ..addOption(
        'count',
        abbr: 'n',
        help: 'Number of recent messages to show on start.',
        defaultsTo: _Defaults.initialCount,
      );
  }

  final Future<void> Function(Duration) _delay;
  final Stream<ProcessSignal>? _signalStream;

  @override
  String get description => 'Watch a channel for new messages.';

  @override
  String get name => 'watch';

  @override
  Future<int> runAuthenticated(Slack slack) async {
    final channel = argResults!['channel'] as String;
    final rawInterval = argResults!['interval'] as String;
    final rawCount = argResults!['count'] as String;
    final interval = int.tryParse(rawInterval);
    final initialCount = int.tryParse(rawCount);
    if (interval == null || interval <= 0) {
      logger
        ..err(
          'Invalid --interval value: "$rawInterval". '
          'Use a positive integer.',
        )
        ..info('')
        ..info(usage);
      return ExitCode.usage.code;
    }
    if (initialCount == null || initialCount <= 0) {
      logger
        ..err(
          'Invalid --count value: "$rawCount". Use a positive integer.',
        )
        ..info('')
        ..info(usage);
      return ExitCode.usage.code;
    }

    final stopCompleter = Completer<void>();
    final signalSub = (_signalStream ?? ProcessSignal.sigint.watch()).listen((
      _,
    ) {
      if (!stopCompleter.isCompleted) stopCompleter.complete();
    });

    try {
      var lastTs = await _fetchInitial(slack, channel, initialCount);

      logger.info('Watching $channel (Ctrl+C to stop)...');

      while (!stopCompleter.isCompleted) {
        await Future.any([
          _delay(Duration(seconds: interval)),
          stopCompleter.future,
        ]);
        if (stopCompleter.isCompleted) break;

        lastTs = await _poll(slack, channel, lastTs);
      }
    } finally {
      await signalSub.cancel();
    }

    return ExitCode.success.code;
  }

  Future<String?> _fetchInitial(
    Slack slack,
    String channel,
    int limit,
  ) async {
    final page = await slack.conversationsHistory(
      channel: channel,
      limit: limit,
    );
    if (page.items.isEmpty) return null;

    page.items.reversed.forEach(_printMessage);

    return page.items.first.ts;
  }

  Future<String?> _poll(Slack slack, String channel, String? lastTs) async {
    final page = await slack.conversationsHistory(
      channel: channel,
      oldest: lastTs,
    );
    if (page.items.isEmpty) return lastTs;

    page.items.reversed.forEach(_printMessage);

    return page.items.first.ts;
  }

  void _printMessage(SlackMessage message) {
    final user = message.user ?? 'unknown';
    final thread = message.replyCount != null
        ? ' [${message.replyCount} replies]'
        : '';
    logger.info('<$user> ${message.text}$thread');
  }
}
