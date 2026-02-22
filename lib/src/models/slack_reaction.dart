/// A reaction on a Slack message.
class SlackReaction {
  /// Creates a [SlackReaction].
  const SlackReaction({required this.name, required this.count});

  /// Deserializes from a Slack API reaction object.
  factory SlackReaction.fromJson(Map<String, dynamic> json) {
    return SlackReaction(
      name: json['name'] as String,
      count: json['count'] as int,
    );
  }

  /// The emoji name (e.g. `thumbsup`).
  final String name;

  /// The number of users who reacted.
  final int count;
}
