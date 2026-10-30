import 'dart:async';
import 'dart:io';

import 'package:dart_slack/src/cli/commands/authenticated_command.dart';
import 'package:dart_slack/src/models/slack_message.dart';
import 'package:dart_slack/src/slack.dart';
import 'package:dart_slack/src/slack_api/slack_api_client.dart';
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
  new({
    required super.logger,
    super.credentialsStore,
    super.httpClient,
    @visibleForTesting Future<void> Function(Duration)? delay,
    @visibleForTesting this._signalStream,
  }) : _delay = delay ?? Future.delayed {
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
        ..err('Invalid --count value: "$rawCount". Use a positive integer.')
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

        lastTs = await _poll(
          slack,
          channel,
          lastTs,
          isStopped: () => stopCompleter.isCompleted,
        );
      }
    } finally {
      await signalSub.cancel();
    }

    return ExitCode.success.code;
  }

  Future<String?> _fetchInitial(Slack slack, String channel, int limit) async {
    final page = await slack.conversationsHistory(
      channel: channel,
      limit: limit,
    );
    if (page.items.isEmpty) return null;

    page.items.reversed.forEach(_printMessage);

    return page.items.first.ts;
  }

  Future<String?> _poll(
    Slack slack,
    String channel,
    String? lastTs, {
    required bool Function() isStopped,
  }) async {
    final messages = <String, SlackMessage>{};
    final cursors = <String>{};
    String? latest;
    String? cursor;

    while (true) {
      if (isStopped()) return lastTs;
      final page = await slack.conversationsHistory(
        channel: channel,
        oldest: lastTs,
        latest: latest,
        cursor: cursor,
      );
      for (final message in page.items) {
        messages.putIfAbsent(message.ts, () => message);
      }
      if (!page.hasMore && page.nextCursor == null) break;

      if (page.items.isNotEmpty) {
        // Walk backwards from the oldest message already fetched. Slack
        // excludes this boundary, so new arrivals cannot move this window
        // or cause the next poll to skip an older, unseen message.
        final nextLatest = page.items.last.ts;
        if (nextLatest == latest) {
          throw const SlackApiException('invalid_pagination');
        }
        latest = nextLatest;
        cursor = null;
      } else {
        // A filtered page can be empty while still carrying a cursor.
        final next = page.nextCursor;
        if (next == null || !cursors.add(next)) {
          throw const SlackApiException('invalid_pagination');
        }
        cursor = next;
      }
    }

    // Only publish the batch and advance its checkpoint after every page
    // succeeds. Keep chronological output across page boundaries.
    if (isStopped()) return lastTs;
    messages.values.toList().reversed.forEach(_printMessage);
    return messages.isEmpty ? lastTs : messages.values.first.ts;
  }

  void _printMessage(SlackMessage message) {
    final user = message.user ?? 'unknown';
    final thread = message.replyCount != null
        ? ' [${message.replyCount} replies]'
        : '';
    logger.info('<$user> ${message.text}${message.attachmentSuffix}$thread');
  }
}
