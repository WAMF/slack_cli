import 'dart:convert';
import 'dart:io';

import 'package:dart_slack/src/auth/app_config.dart';
import 'package:dart_slack/src/auth/private_files.dart';
import 'package:meta/meta.dart';

/// Manages persistence of app-level configuration to disk.
///
/// Configuration is stored at `~/.dart_slack/config.json` with file
/// mode 0600 (owner read/write only), inside a mode 0700 directory, on POSIX
/// systems.
class AppConfigStore {
  /// Creates an [AppConfigStore] that writes to [configDirectory].
  ///
  /// Defaults to `~/.dart_slack` when [configDirectory] is omitted.
  new({
    Directory? configDirectory,
    @visibleForTesting Map<String, String>? environment,
  }) : _configDirectory =
           configDirectory ??
           Directory(dartSlackConfigPath(environment ?? Platform.environment));

  final Directory _configDirectory;

  File get _configFile => File('${_configDirectory.path}/config.json');

  /// Returns stored [AppConfig], or `null` if no usable config file exists.
  AppConfig? load() {
    if (!_configFile.existsSync()) return null;
    try {
      final decoded = jsonDecode(_configFile.readAsStringSync());
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['app_token'] is! String) return null;

      final json = decoded;
      return AppConfig.fromJson(json);
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// Persists [config] to disk, creating the config directory if needed.
  void save(AppConfig config) {
    ensurePrivateDirectory(_configDirectory);
    writePrivateFile(_configFile, jsonEncode(config.toJson()));
  }

  /// Deletes the config file. Returns `true` if the file existed.
  bool delete() {
    if (!_configFile.existsSync()) return false;
    _configFile.deleteSync();
    return true;
  }

  /// Whether a config file exists on disk.
  bool get hasConfig => _configFile.existsSync();
}
