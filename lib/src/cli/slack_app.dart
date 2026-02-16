import 'dart:io';

/// Slack app credentials loaded from environment variables or a `.env` file.
///
/// Resolution order:
/// 1. `SLACK_CLIENT_ID` / `SLACK_CLIENT_SECRET` environment variables.
/// 2. A `.env` file in the current working directory.
///
/// Throws [StateError] if either value is missing from both sources.
abstract final class SlackApp {
  static final Map<String, String> _env = _loadEnv();

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

  static Map<String, String> _loadEnv() {
    final env = Map<String, String>.of(Platform.environment);

    final dotEnvFile = File('.env');
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
