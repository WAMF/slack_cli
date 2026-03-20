/// App-level configuration persisted to disk.
///
/// Stores secrets like the Socket Mode app token separately from
/// per-user OAuth credentials.
class AppConfig {
  /// Creates an [AppConfig].
  const AppConfig({required this.appToken});

  /// Deserializes from the JSON map read from the config file.
  factory AppConfig.fromJson(Map<String, dynamic> json) =>
      AppConfig(appToken: json['app_token'] as String);

  /// The Socket Mode app-level token (`xapp-*`).
  final String appToken;

  /// Serializes to a JSON-compatible map for writing to the config file.
  Map<String, dynamic> toJson() => {'app_token': appToken};
}
