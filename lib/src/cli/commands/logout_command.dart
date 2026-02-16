import 'package:args/command_runner.dart';
import 'package:dart_slack/src/auth/credentials_store.dart';
import 'package:mason_logger/mason_logger.dart';

/// `dart_slack logout`
///
/// Removes stored Slack credentials.
class LogoutCommand extends Command<int> {
  /// Creates a [LogoutCommand].
  LogoutCommand({
    required Logger logger,
    CredentialsStore? credentialsStore,
  }) : _logger = logger,
       _credentialsStore = credentialsStore ?? CredentialsStore();

  @override
  String get description => 'Remove stored Slack credentials.';

  @override
  String get name => 'logout';

  final Logger _logger;
  final CredentialsStore _credentialsStore;

  @override
  Future<int> run() async {
    if (_credentialsStore.delete()) {
      _logger.success('Logged out.');
    } else {
      _logger.info('No credentials found.');
    }
    return ExitCode.success.code;
  }
}
