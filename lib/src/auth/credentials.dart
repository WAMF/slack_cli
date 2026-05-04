/// Holds the OAuth access token and associated metadata persisted to disk.
class Credentials {
  /// Creates a new [Credentials] instance.
  const Credentials({
    required this.accessToken,
    this.userId,
  });

  /// Deserializes from the JSON map read from the credentials file.
  factory Credentials.fromJson(Map<String, dynamic> json) => Credentials(
    accessToken: json['access_token'] as String,
    userId: json['user_id'] as String?,
  );

  /// The OAuth access token used to authenticate API requests.
  final String accessToken;

  /// The authenticated user's Slack identifier.
  final String? userId;

  /// Serializes to a JSON-compatible map for writing to the credentials file.
  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    if (userId != null) 'user_id': userId,
  };
}
