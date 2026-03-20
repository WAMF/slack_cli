import 'dart:io' as io;
import 'dart:io' show Stdin, Stdout;

import 'package:args/command_runner.dart';
import 'package:dart_slack/src/auth/app_config.dart';
import 'package:dart_slack/src/auth/app_config_store.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';

class _TokenPrefix {
  static const appToken = 'xapp-';
}

/// `dart_slack configure`
///
/// Stores the Socket Mode app-level token securely on disk.
/// The token is read with hidden input so it never appears in shell
/// history or on screen.
class ConfigureCommand extends Command<int> {
  /// Creates a [ConfigureCommand].
  ConfigureCommand({
    required Logger logger,
    AppConfigStore? configStore,
    @visibleForTesting Stdin? stdin,
    @visibleForTesting Stdout? stdout,
  }) : _logger = logger,
       _configStore = configStore ?? AppConfigStore(),
       _stdin = stdin ?? io.stdin,
       _stdout = stdout ?? io.stdout {
    argParser.addFlag(
      'clear',
      help: 'Remove stored app configuration.',
      negatable: false,
    );
  }

  final Logger _logger;
  final AppConfigStore _configStore;
  final Stdin _stdin;
  final Stdout _stdout;

  @override
  String get description => 'Store the Socket Mode app token securely.';

  @override
  String get name => 'configure';

  @override
  Future<int> run() async {
    if (argResults!['clear'] as bool) {
      return _clear();
    }

    if (_configStore.hasConfig) {
      final existing = _configStore.load()!;
      final masked = _maskToken(existing.appToken);
      final overwrite = _logger.confirm(
        'App token already configured ($masked). Reconfigure?',
      );
      if (!overwrite) return ExitCode.success.code;
    }

    final token = _readSecret('App token (xapp-*): ');

    if (token.isEmpty) {
      _logger.err('No token provided.');
      return ExitCode.usage.code;
    }

    if (!token.startsWith(_TokenPrefix.appToken)) {
      _logger.err(
        'Invalid token. App-level tokens start with '
        '"${_TokenPrefix.appToken}".',
      );
      return ExitCode.usage.code;
    }

    _configStore.save(AppConfig(appToken: token));
    _logger.success('App token saved to ~/.dart_slack/config.json');

    return ExitCode.success.code;
  }

  int _clear() {
    if (_configStore.delete()) {
      _logger.success('App configuration removed.');
    } else {
      _logger.info('No app configuration found.');
    }
    return ExitCode.success.code;
  }

  String _readSecret(String prompt) {
    _stdout.write(prompt);
    _stdin.echoMode = false;
    try {
      return _stdin.readLineSync() ?? '';
    } finally {
      _stdin.echoMode = true;
      _stdout.writeln();
    }
  }

  String _maskToken(String token) {
    if (token.length <= 8) return '****';
    return '${token.substring(0, 8)}****';
  }
}
