import 'dart:convert';
import 'dart:io';

import 'package:dart_slack/src/auth/credentials.dart';
import 'package:dart_slack/src/auth/private_files.dart';
import 'package:meta/meta.dart';

/// Manages persistence of Slack OAuth credentials to disk.
///
/// Credentials are stored at `~/.dart_slack/credentials.json` with file
/// mode 0600 (owner read/write only), inside a mode 0700 directory, on POSIX
/// systems.
class CredentialsStore {
  /// Creates a [CredentialsStore] that writes to [configDirectory].
  ///
  /// Defaults to `~/.dart_slack` when [configDirectory] is omitted.
  new({
    Directory? configDirectory,
    @visibleForTesting Map<String, String>? environment,
  }) : _configDirectory =
           configDirectory ??
           Directory(dartSlackConfigPath(environment ?? Platform.environment));

  final Directory _configDirectory;

  File get _credentialsFile =>
      File('${_configDirectory.path}/credentials.json');

  /// Returns stored [Credentials], or `null` if no credentials file exists.
  Credentials? load() {
    if (!_credentialsFile.existsSync()) return null;
    final json =
        jsonDecode(_credentialsFile.readAsStringSync()) as Map<String, dynamic>;
    return Credentials.fromJson(json);
  }

  /// Persists [credentials] to disk, creating the config directory if needed.
  void save(Credentials credentials) {
    ensurePrivateDirectory(_configDirectory);
    writePrivateFile(_credentialsFile, jsonEncode(credentials.toJson()));
  }

  /// Deletes the credentials file. Returns `true` if the file existed.
  bool delete() {
    if (!_credentialsFile.existsSync()) return false;
    _credentialsFile.deleteSync();
    return true;
  }

  /// Whether valid credentials exist on disk.
  bool get hasCredentials => _credentialsFile.existsSync();
}
