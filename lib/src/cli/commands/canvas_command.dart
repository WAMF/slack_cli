import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:dart_slack/src/auth/credentials_store.dart';
import 'package:dart_slack/src/cli/commands/authenticated_command.dart';
import 'package:dart_slack/src/slack.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';

/// `dart_slack canvas <create|edit|delete>`
///
/// Groups the canvas operations under a single parent command so the
/// `create` / `edit` / `delete` verbs do not collide with the message-level
/// `edit` and `delete` commands.
class CanvasCommand extends Command<int> {
  /// Creates a [CanvasCommand] and registers its subcommands.
  CanvasCommand({
    required Logger logger,
    CredentialsStore? credentialsStore,
    http.Client? httpClient,
  }) {
    addSubcommand(
      CanvasCreateCommand(
        logger: logger,
        credentialsStore: credentialsStore,
        httpClient: httpClient,
      ),
    );
    addSubcommand(
      CanvasEditCommand(
        logger: logger,
        credentialsStore: credentialsStore,
        httpClient: httpClient,
      ),
    );
    addSubcommand(
      CanvasDeleteCommand(
        logger: logger,
        credentialsStore: credentialsStore,
        httpClient: httpClient,
      ),
    );
  }

  @override
  String get description => 'Create, edit, and delete Slack canvases.';

  @override
  String get name => 'canvas';
}

/// `dart_slack canvas create [--title T] (--content M | --file F) [-c C]`
///
/// Creates a canvas from markdown. With `--channel`, the canvas is tabbed into
/// that channel; otherwise a standalone canvas is created.
class CanvasCreateCommand extends AuthenticatedCommand {
  /// Creates a [CanvasCreateCommand].
  CanvasCreateCommand({
    required super.logger,
    super.credentialsStore,
    super.httpClient,
  }) {
    argParser
      ..addOption('title', help: 'The canvas title.')
      ..addOption(
        'content',
        abbr: 'm',
        help: 'Markdown content for the canvas body.',
      )
      ..addOption(
        'file',
        abbr: 'f',
        help: 'Path to a markdown file to use as the canvas body.',
      )
      ..addOption(
        'channel',
        abbr: 'c',
        help:
            'Channel ID to tab the canvas into (omit for a standalone '
            'canvas).',
      );
  }

  @override
  String get description => 'Create a Slack canvas from markdown.';

  @override
  String get name => 'create';

  @override
  Future<int> runAuthenticated(Slack slack) async {
    final content = _resolveCanvasContent(argResults!, logger);
    if (content == null) return ExitCode.usage.code;

    final canvasId = await slack.createCanvas(
      markdown: content,
      title: argResults!['title'] as String?,
      channel: argResults!['channel'] as String?,
    );
    logger.success('Canvas created: $canvasId');
    return ExitCode.success.code;
  }
}

/// `dart_slack canvas edit --canvas ID (--content M | --file F) [--mode MODE]`
///
/// Replaces, appends, or prepends markdown content in an existing canvas.
class CanvasEditCommand extends AuthenticatedCommand {
  /// Creates a [CanvasEditCommand].
  CanvasEditCommand({
    required super.logger,
    super.credentialsStore,
    super.httpClient,
  }) {
    argParser
      ..addOption(
        'canvas',
        help: 'The canvas ID to edit.',
        mandatory: true,
      )
      ..addOption(
        'content',
        abbr: 'm',
        help: 'Markdown content to write.',
      )
      ..addOption(
        'file',
        abbr: 'f',
        help: 'Path to a markdown file to use as content.',
      )
      ..addOption(
        'mode',
        help: 'How to apply the content.',
        allowed: ['replace', 'append', 'prepend'],
        defaultsTo: 'replace',
      );
  }

  @override
  String get description => 'Edit an existing Slack canvas.';

  @override
  String get name => 'edit';

  @override
  Future<int> runAuthenticated(Slack slack) async {
    final content = _resolveCanvasContent(argResults!, logger);
    if (content == null) return ExitCode.usage.code;

    final canvasId = argResults!['canvas'] as String;
    await slack.editCanvas(
      canvasId: canvasId,
      markdown: content,
      mode: CanvasEditMode.fromName(argResults!['mode'] as String?),
    );
    logger.success('Canvas $canvasId updated.');
    return ExitCode.success.code;
  }
}

/// `dart_slack canvas delete --canvas ID`
///
/// Deletes a canvas.
class CanvasDeleteCommand extends AuthenticatedCommand {
  /// Creates a [CanvasDeleteCommand].
  CanvasDeleteCommand({
    required super.logger,
    super.credentialsStore,
    super.httpClient,
  }) {
    argParser.addOption(
      'canvas',
      help: 'The canvas ID to delete.',
      mandatory: true,
    );
  }

  @override
  String get description => 'Delete a Slack canvas.';

  @override
  String get name => 'delete';

  @override
  Future<int> runAuthenticated(Slack slack) async {
    final canvasId = argResults!['canvas'] as String;
    await slack.deleteCanvas(canvasId: canvasId);
    logger.success('Canvas $canvasId deleted.');
    return ExitCode.success.code;
  }
}

/// Resolves canvas markdown from the mutually exclusive `--content` and
/// `--file` options.
///
/// Returns `null` (after logging an error) when neither or both are supplied,
/// or when the file cannot be read.
String? _resolveCanvasContent(ArgResults args, Logger logger) {
  final inline = args['content'] as String?;
  final filePath = args['file'] as String?;

  if ((inline == null) == (filePath == null)) {
    logger.err('Provide exactly one of --content or --file.');
    return null;
  }

  if (inline != null) return inline;

  try {
    return File(filePath!).readAsStringSync();
  } on FileSystemException catch (e) {
    logger.err('Failed to read file: $filePath (${e.message})');
    return null;
  }
}
