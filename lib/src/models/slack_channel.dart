/// A Slack channel.
class SlackChannel {
  /// Creates a [SlackChannel].
  const SlackChannel({
    required this.id,
    required this.name,
    required this.isPrivate,
    this.topic = '',
    this.purpose = '',
    this.memberCount = 0,
    this.isArchived = false,
    this.created = 0,
  });

  /// Deserializes from a Slack API channel object.
  factory SlackChannel.fromJson(Map<String, dynamic> json) {
    final topicMap = json['topic'] as Map<String, dynamic>?;
    final purposeMap = json['purpose'] as Map<String, dynamic>?;
    return SlackChannel(
      id: json['id'] as String,
      name: json['name'] as String,
      isPrivate: json['is_private'] as bool? ?? false,
      topic: topicMap?['value'] as String? ?? '',
      purpose: purposeMap?['value'] as String? ?? '',
      memberCount: json['num_members'] as int? ?? 0,
      isArchived: json['is_archived'] as bool? ?? false,
      created: json['created'] as int? ?? 0,
    );
  }

  /// The channel identifier (e.g. `C0123ABCDEF`).
  final String id;

  /// The channel name without the `#` prefix.
  final String name;

  /// Whether this is a private channel.
  final bool isPrivate;

  /// The channel topic.
  final String topic;

  /// The channel purpose.
  final String purpose;

  /// The number of members in the channel.
  final int memberCount;

  /// Whether the channel is archived.
  final bool isArchived;

  /// Unix timestamp when the channel was created.
  final int created;
}
