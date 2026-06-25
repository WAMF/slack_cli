import 'package:args/command_runner.dart';
import 'package:dart_slack/src/auth/credentials_store.dart';
import 'package:dart_slack/src/cli/commands/authenticated_command.dart';
import 'package:dart_slack/src/slack.dart';
import 'package:dart_slack/src/slack_api/slack_api_client.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';

/// `dart_slack status <set|clear>`
///
/// Sets or clears the authenticated user's custom status via
/// `users.profile.set`. Requires a user token (`xoxp-...`) with the
/// `users.profile:write` scope — bot tokens cannot change a user's status
/// and fail with `not_allowed_token_type`.
class StatusCommand extends Command<int> {
  /// Creates a [StatusCommand].
  StatusCommand({
    required Logger logger,
    CredentialsStore? credentialsStore,
    http.Client? httpClient,
    DateTime Function()? now,
  }) {
    addSubcommand(
      StatusSetCommand(
        logger: logger,
        credentialsStore: credentialsStore,
        httpClient: httpClient,
        now: now,
      ),
    );
    addSubcommand(
      StatusClearCommand(
        logger: logger,
        credentialsStore: credentialsStore,
        httpClient: httpClient,
      ),
    );
  }

  @override
  String get description =>
      "Set or clear the authenticated user's custom status.";

  @override
  String get name => 'status';
}

/// `dart_slack status set --text <text> [--emoji <emoji>] [--expires-in 6h]`
///
/// Sets the authenticated user's custom status.
class StatusSetCommand extends AuthenticatedCommand {
  /// Creates a [StatusSetCommand].
  StatusSetCommand({
    required super.logger,
    super.credentialsStore,
    super.httpClient,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    argParser
      ..addOption(
        'text',
        abbr: 't',
        help: 'The status text (max 100 characters).',
        mandatory: true,
      )
      ..addOption(
        'emoji',
        abbr: 'e',
        help:
            'The status emoji, e.g. ":hammer_and_wrench:". '
            'Omit to let Slack use its default.',
      )
      ..addOption(
        'expires-in',
        abbr: 'x',
        help:
            'Clear the status automatically after this long, e.g. 45m, '
            '6h, or a plain number of seconds. Omit (or pass 0) to keep '
            'the status until it is cleared.',
      );
  }

  /// Injectable clock for computing `status_expiration` in tests.
  final DateTime Function() _now;

  @override
  String get description => "Set the authenticated user's custom status.";

  @override
  String get name => 'set';

  @override
  Future<int> runAuthenticated(Slack slack) async {
    final text = (argResults!['text'] as String).trim();
    final emoji = (argResults!['emoji'] as String?)?.trim() ?? '';
    final expiresInRaw = argResults!['expires-in'] as String?;

    if (text.isEmpty) {
      usageException('Provide a non-empty --text value.');
    }
    if (argResults!.wasParsed('emoji') && emoji.isEmpty) {
      usageException('Provide a non-empty --emoji value.');
    }

    final expiration = _resolveExpiration(expiresInRaw);

    try {
      await slack.setStatus(text: text, emoji: emoji, expiration: expiration);
    } on SlackApiException catch (e) {
      if (e.error == 'not_allowed_token_type') {
        logger.err(
          'Slack API error: ${e.error}. Setting a status requires a user '
          "token (xoxp-...) with the 'users.profile:write' scope; bot "
          'tokens (xoxb-...) cannot change a user profile.',
        );
        return ExitCode.software.code;
      }
      rethrow;
    }

    final suffix = expiration == 0 ? '' : ' (expires in $expiresInRaw)';
    logger.info('Status set: ${emoji.isEmpty ? text : '$emoji $text'}$suffix');
    return ExitCode.success.code;
  }

  /// Resolves the `status_expiration` Unix timestamp (seconds) from the raw
  /// `--expires-in` value. Returns `0` when no expiry is requested or the
  /// parsed duration is non-positive; raises a usage error on an invalid
  /// value.
  int _resolveExpiration(String? expiresInRaw) {
    if (expiresInRaw == null) return 0;
    final expiresIn = parseDuration(expiresInRaw);
    if (expiresIn == null) {
      usageException(
        "Invalid --expires-in value '$expiresInRaw'. "
        'Use a number of seconds or a value like 90s, 45m, 6h, 1d.',
      );
    }
    if (expiresIn <= Duration.zero) return 0;
    return _now().add(expiresIn).millisecondsSinceEpoch ~/ 1000;
  }

  /// Parses `90s` / `45m` / `6h` / `1d` / `3600` (seconds) into a
  /// [Duration]. Returns `null` when [input] is not a positive integer
  /// with an optional unit suffix.
  static Duration? parseDuration(String input) {
    final match = RegExp(r'^(\d+)([smhd])?$').firstMatch(input.trim());
    if (match == null) return null;
    final value = int.tryParse(match.group(1)!);
    if (value == null) return null;
    return switch (match.group(2)) {
      'm' => Duration(minutes: value),
      'h' => Duration(hours: value),
      'd' => Duration(days: value),
      _ => Duration(seconds: value),
    };
  }
}

/// `dart_slack status clear`
///
/// Clears the authenticated user's custom status.
class StatusClearCommand extends AuthenticatedCommand {
  /// Creates a [StatusClearCommand].
  StatusClearCommand({
    required super.logger,
    super.credentialsStore,
    super.httpClient,
  });

  @override
  String get description => "Clear the authenticated user's custom status.";

  @override
  String get name => 'clear';

  @override
  Future<int> runAuthenticated(Slack slack) async {
    await slack.clearStatus();
    logger.info('Status cleared.');
    return ExitCode.success.code;
  }
}
