/// A Slack channel.
class SlackChannel {
  /// Creates a [SlackChannel].
  const SlackChannel({
    required this.id,
    required this.name,
    required this.isPrivate,
  });

  /// Deserializes from a Slack API channel object.
  factory SlackChannel.fromJson(Map<String, dynamic> json) =>
      SlackChannel(
        id: json['id'] as String,
        name: json['name'] as String,
        isPrivate: json['is_private'] as bool? ?? false,
      );

  /// The channel identifier (e.g. `C0123ABCDEF`).
  final String id;

  /// The channel name without the `#` prefix.
  final String name;

  /// Whether this is a private channel.
  final bool isPrivate;
}
