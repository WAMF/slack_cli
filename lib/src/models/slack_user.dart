/// A Slack workspace user.
class SlackUser {
  /// Creates a [SlackUser].
  const SlackUser({
    required this.id,
    required this.name,
    required this.realName,
    required this.displayName,
    required this.isBot,
    required this.isDeleted,
    this.email,
    this.imageUrl,
  });

  /// Deserializes from a Slack API user object.
  factory SlackUser.fromJson(Map<String, dynamic> json) {
    final profile = json['profile'] as Map<String, dynamic>? ?? {};
    return SlackUser(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      realName: json['real_name'] as String? ?? '',
      displayName: profile['display_name'] as String? ?? '',
      isBot: json['is_bot'] as bool? ?? false,
      isDeleted: json['deleted'] as bool? ?? false,
      email: profile['email'] as String?,
      imageUrl: profile['image_48'] as String?,
    );
  }

  /// The user identifier (e.g. `U0123ABCDEF`).
  final String id;

  /// The user's username (e.g. `johndoe`).
  final String name;

  /// The user's full name.
  final String realName;

  /// The user's display name.
  final String displayName;

  /// Whether this user is a bot.
  final bool isBot;

  /// Whether this user has been deactivated.
  final bool isDeleted;

  /// The user's email address, if available.
  final String? email;

  /// URL of the user's 48px profile image.
  final String? imageUrl;
}
