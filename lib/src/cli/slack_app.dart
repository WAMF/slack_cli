import 'dart:io';

import 'package:meta/meta.dart';

/// Slack app credentials loaded from environment variables or a `.env` file.
///
/// Resolution order:
/// 1. `SLACK_CLIENT_ID` / `SLACK_CLIENT_SECRET` environment variables.
/// 2. A `.env` file in the current working directory.
///
/// Throws [StateError] if either value is missing from both sources.
abstract final class SlackApp {
  static Map<String, String>? _envCache;

  static String? _dotEnvPath;

  static Map<String, String> get _env => _envCache ??= _loadEnv();

  /// Resets the cached environment so the next access re-reads values.
  @visibleForTesting
  static void resetForTesting({String? dotEnvPath}) {
    _envCache = null;
    _dotEnvPath = dotEnvPath;
  }

  /// OAuth client identifier.
  static String get clientId =>
      _env['SLACK_CLIENT_ID'] ??
      (throw StateError(
        'SLACK_CLIENT_ID not set. '
        'Provide it as an env var or in a .env file.',
      ));

  /// OAuth client secret.
  static String get clientSecret =>
      _env['SLACK_CLIENT_SECRET'] ??
      (throw StateError(
        'SLACK_CLIENT_SECRET not set. '
        'Provide it as an env var or in a .env file.',
      ));

  /// App-level token for Socket Mode connections (xapp-*).
  static String get appToken =>
      _env['SLACK_APP_TOKEN'] ??
      (throw StateError(
        'SLACK_APP_TOKEN not set. '
        'Provide it as an env var or in a .env file.',
      ));

  /// App-level token, or `null` if not configured.
  static String? get appTokenOrNull => _env['SLACK_APP_TOKEN'];

  /// The merged environment used to resolve Slack secrets: the process
  /// environment overlaid with a `.env` file in the current directory.
  /// Exposed so other commands resolve secrets the same way OAuth does.
  static Map<String, String> get environment => _env;

  static Map<String, String> _loadEnv() {
    final env = Map<String, String>.of(Platform.environment);

    final dotEnvFile = File(_dotEnvPath ?? '.env');
    if (dotEnvFile.existsSync()) {
      for (final line in dotEnvFile.readAsLinesSync()) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        final index = trimmed.indexOf('=');
        if (index < 0) continue;
        final key = trimmed.substring(0, index).trim();
        final value = trimmed.substring(index + 1).trim();
        env.putIfAbsent(key, () => value);
      }
    }

    return env;
  }
}
