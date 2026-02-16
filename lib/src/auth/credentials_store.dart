import 'dart:convert';
import 'dart:io';

import 'package:slackcli/src/auth/credentials.dart';

/// Manages persistence of Slack OAuth credentials to disk.
///
/// Credentials are stored at `~/.slackcli/credentials.json` with file
/// mode 0600 (owner read/write only) on POSIX systems.
class CredentialsStore {
  /// Creates a [CredentialsStore] that writes to [configDirectory].
  ///
  /// Defaults to `~/.slackcli` when [configDirectory] is omitted.
  CredentialsStore({Directory? configDirectory})
    : _configDirectory =
          configDirectory ??
          Directory('${Platform.environment['HOME']}/.slackcli');

  final Directory _configDirectory;

  File get _credentialsFile => File(
    '${_configDirectory.path}/credentials.json',
  );

  /// Returns stored [Credentials], or `null` if no credentials file exists.
  Credentials? load() {
    if (!_credentialsFile.existsSync()) return null;
    final json =
        jsonDecode(_credentialsFile.readAsStringSync())
            as Map<String, dynamic>;
    return Credentials.fromJson(json);
  }

  /// Persists [credentials] to disk, creating the config directory if needed.
  void save(Credentials credentials) {
    _configDirectory.createSync(recursive: true);
    _credentialsFile.writeAsStringSync(jsonEncode(credentials.toJson()));
    _setFilePermissions();
  }

  /// Deletes the credentials file. Returns `true` if the file existed.
  bool delete() {
    if (!_credentialsFile.existsSync()) return false;
    _credentialsFile.deleteSync();
    return true;
  }

  /// Whether valid credentials exist on disk.
  bool get hasCredentials => _credentialsFile.existsSync();

  void _setFilePermissions() {
    if (Platform.isMacOS || Platform.isLinux) {
      Process.runSync('chmod', ['600', _credentialsFile.path]);
    }
  }
}
