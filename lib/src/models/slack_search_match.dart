/// A single message match returned by Slack's `search.messages` method.
///
/// A search match is not shaped like a `conversations.history` message: the
/// channel arrives as a nested object rather than an ID string, and Slack
/// resolves the author's display name alongside the user ID. This model keeps
/// both, so a caller can print a readable line without a second lookup.
class SlackSearchMatch {
  /// Creates a [SlackSearchMatch].
  const SlackSearchMatch({
    required this.ts,
    required this.text,
    this.channelId,
    this.channelName,
    this.user,
    this.username,
  });

  /// Deserializes from one entry of `search.messages`' `messages.matches`.
  factory SlackSearchMatch.fromJson(Map<String, dynamic> json) {
    final channel = json['channel'] as Map<String, dynamic>?;
    return SlackSearchMatch(
      ts: json['ts'] as String,
      text: json['text'] as String? ?? '',
      channelId: channel?['id'] as String?,
      channelName: channel?['name'] as String?,
      user: json['user'] as String?,
      username: json['username'] as String?,
    );
  }

  /// The message timestamp, which identifies the message in its channel.
  final String ts;

  /// The message text content.
  final String text;

  /// The ID of the channel that holds the message (e.g. `C0123ABCDEF`).
  final String? channelId;

  /// The name of that channel, without the `#` prefix.
  final String? channelName;

  /// The ID of the user who posted the message.
  final String? user;

  /// The display name of that user, as resolved by Slack.
  final String? username;

  /// A readable label for the channel: `#name` when Slack returns a name,
  /// the channel ID when it does not, and `unknown` when it returns neither.
  String get channelLabel {
    final name = channelName;
    if (name != null && name.isNotEmpty) return '#$name';
    final id = channelId;
    if (id != null && id.isNotEmpty) return id;
    return 'unknown';
  }

  /// A readable label for the author: the display name when Slack returns
  /// one, the user ID when it does not, and `unknown` when it returns
  /// neither.
  String get authorLabel {
    final name = username;
    if (name != null && name.isNotEmpty) return name;
    final id = user;
    if (id != null && id.isNotEmpty) return id;
    return 'unknown';
  }
}
