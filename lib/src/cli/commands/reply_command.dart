import 'dart:io';

import 'package:dart_slack/src/cli/card_file_input.dart';
import 'package:dart_slack/src/cli/commands/authenticated_command.dart';
import 'package:dart_slack/src/cli/message_text_input.dart';
import 'package:dart_slack/src/slack.dart';
import 'package:mason_logger/mason_logger.dart';

/// `dart_slack reply --channel <id> --thread <ts> --text-file <path>`
/// `[--file <path>]`
///
/// The reply text comes from exactly one of `--text`, `--text-file` or
/// `--text-stdin`. `--file` attaches a file and is a different option.
/// `--card-file <path>` posts a RichMessage card instead of text.
///
/// Replies to a message thread in a Slack channel.
class ReplyCommand extends AuthenticatedCommand
    with MessageTextCommand, CardFileCommand {
  /// Creates a [ReplyCommand].
  new({required super.logger, super.credentialsStore, super.httpClient}) {
    argParser
      ..addOption(
        'channel',
        abbr: 'c',
        help: 'The channel ID containing the thread.',
        mandatory: true,
      )
      ..addOption(
        'thread',
        abbr: 'r',
        help: 'The thread timestamp (thread_ts) to reply to.',
        mandatory: true,
      )
      ..addOption('file', abbr: 'f', help: 'Path to a local file to attach.');
    addMessageTextOptions(argParser, help: 'The reply text.');
    addCardFileOption(argParser);
  }

  @override
  String get description => 'Reply to a message thread in a Slack channel.';

  @override
  String get name => 'reply';

  @override
  Future<int> runAuthenticated(Slack slack) async {
    final channel = argResults!['channel'] as String;
    final thread = argResults!['thread'] as String;
    final filePath = argResults!['file'] as String?;

    if (filePath != null) {
      if (!File(filePath).existsSync()) {
        logger.err('File not found: $filePath');
        return ExitCode.noInput.code;
      }
      final filename = await slack.uploadFile(
        channel: channel,
        path: filePath,
        threadTs: thread,
        comment: messageText,
      );
      logger.success('File "$filename" sent to thread $thread in $channel.');
      return ExitCode.success.code;
    }

    final message = await slack.postMessage(
      channel: channel,
      text: card?.text ?? messageText,
      threadTs: thread,
      card: card,
    );
    logger.success(
      'Reply sent to thread $thread in $channel (ts: ${message.ts}).',
    );
    return ExitCode.success.code;
  }
}
