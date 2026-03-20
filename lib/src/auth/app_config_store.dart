import 'dart:convert';
import 'dart:io';

import 'package:dart_slack/src/auth/app_config.dart';
import 'package:meta/meta.dart';

/// Manages persistence of app-level configuration to disk.
///
/// Configuration is stored at `~/.dart_slack/config.json` with file
/// mode 0600 (owner read/write only) on POSIX systems.
class AppConfigStore {
  /// Creates an [AppConfigStore] that writes to [configDirectory].
  ///
  /// Defaults to `~/.dart_slack` when [configDirectory] is omitted.
  AppConfigStore({
    Directory? configDirectory,
    @visibleForTesting Map<String, String>? environment,
  }) : _configDirectory =
           configDirectory ??
           Directory(_defaultConfigPath(environment ?? Platform.environment));

  final Directory _configDirectory;

  File get _configFile => File('${_configDirectory.path}/config.json');

  /// Returns stored [AppConfig], or `null` if no config file exists.
  AppConfig? load() {
    if (!_configFile.existsSync()) return null;
    final json =
        jsonDecode(_configFile.readAsStringSync()) as Map<String, dynamic>;
    return AppConfig.fromJson(json);
  }

  /// Persists [config] to disk, creating the config directory if needed.
  void save(AppConfig config) {
    _configDirectory.createSync(recursive: true);
    _configFile.writeAsStringSync(jsonEncode(config.toJson()));
    _setFilePermissions();
  }

  /// Deletes the config file. Returns `true` if the file existed.
  bool delete() {
    if (!_configFile.existsSync()) return false;
    _configFile.deleteSync();
    return true;
  }

  /// Whether a config file exists on disk.
  bool get hasConfig => _configFile.existsSync();

  static String _defaultConfigPath(Map<String, String> environment) {
    final home =
        environment['HOME'] ??
        environment['USERPROFILE'] ??
        Directory.current.path;
    return '$home/.dart_slack';
  }

  void _setFilePermissions() {
    if (Platform.isMacOS || Platform.isLinux) {
      Process.runSync('chmod', ['600', _configFile.path]);
    }
  }
}
