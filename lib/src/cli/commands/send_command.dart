import 'dart:io';

import 'package:dart_slack/src/cli/commands/authenticated_command.dart';
import 'package:dart_slack/src/cli/message_text.dart';
import 'package:dart_slack/src/slack.dart';
import 'package:mason_logger/mason_logger.dart';

/// `dart_slack send --channel <id> --text "message" [--file <path>]`
///
/// Posts a message to a Slack channel.
class SendCommand extends AuthenticatedCommand {
  /// Creates a [SendCommand].
  SendCommand({
    required super.logger,
    super.credentialsStore,
    super.httpClient,
  }) {
    argParser
      ..addOption(
        'channel',
        abbr: 'c',
        help: 'The channel ID to post to.',
        mandatory: true,
      )
      ..addOption(
        'text',
        abbr: 't',
        help: 'The message text.',
        mandatory: true,
      )
      ..addOption(
        'file',
        abbr: 'f',
        help: 'Path to a local file to attach.',
      );
  }

  @override
  String get description => 'Post a message to a Slack channel.';

  @override
  String get name => 'send';

  @override
  Future<int> runAuthenticated(Slack slack) async {
    final channel = argResults!['channel'] as String;
    final text = normalizeMessageText(argResults!['text'] as String);
    final filePath = argResults!['file'] as String?;

    if (filePath != null) {
      if (!File(filePath).existsSync()) {
        logger.err('File not found: $filePath');
        return ExitCode.noInput.code;
      }
      final filename = await slack.uploadFile(
        channel: channel,
        path: filePath,
        comment: text,
      );
      logger.success('File "$filename" sent to $channel.');
      return ExitCode.success.code;
    }

    final message = await slack.postMessage(channel: channel, text: text);
    logger.success('Message sent to $channel (ts: ${message.ts}).');
    return ExitCode.success.code;
  }
}
