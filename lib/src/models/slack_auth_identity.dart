/// Identity details for the token validated by `auth.test`.
class SlackAuthIdentity {
  /// Creates a [SlackAuthIdentity].
  const SlackAuthIdentity({
    required this.team,
    required this.teamId,
    required this.user,
    required this.userId,
    this.botId,
  });

  /// Deserializes from an `auth.test` response.
  factory SlackAuthIdentity.fromJson(Map<String, dynamic> json) =>
      SlackAuthIdentity(
        team: json['team'] as String? ?? '',
        teamId: json['team_id'] as String? ?? '',
        user: json['user'] as String? ?? '',
        userId: json['user_id'] as String? ?? '',
        botId: json['bot_id'] as String?,
      );

  /// The workspace name.
  final String team;

  /// The workspace identifier (e.g. `T0123ABCDEF`).
  final String teamId;

  /// The authenticated user's username.
  final String user;

  /// The authenticated user's identifier (e.g. `U0123ABCDEF`).
  final String userId;

  /// The bot identifier, present when the token belongs to a bot.
  final String? botId;
}
