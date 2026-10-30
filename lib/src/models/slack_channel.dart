/// A Slack channel or direct-message conversation.
class SlackChannel {
  /// Creates a [SlackChannel].
  const new({
    required this.id,
    required this.name,
    required this.isPrivate,
    this.topic = '',
    this.purpose = '',
    this.memberCount = 0,
    this.isArchived = false,
    this.created = 0,
    this.isIm = false,
    this.userId,
  });

  /// Deserializes from a Slack API channel object.
  factory fromJson(Map<String, dynamic> json) {
    final topicMap = json['topic'] as Map<String, dynamic>?;
    final purposeMap = json['purpose'] as Map<String, dynamic>?;
    return SlackChannel(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      isPrivate: json['is_private'] as bool? ?? json['is_im'] == true,
      topic: topicMap?['value'] as String? ?? '',
      purpose: purposeMap?['value'] as String? ?? '',
      memberCount: json['num_members'] as int? ?? 0,
      isArchived: json['is_archived'] as bool? ?? false,
      created: json['created'] as int? ?? 0,
      isIm: json['is_im'] as bool? ?? false,
      userId: json['user'] as String?,
    );
  }

  /// The channel identifier (e.g. `C0123ABCDEF`).
  final String id;

  /// The channel name without the `#` prefix, or empty for unnamed
  /// conversations such as one-to-one direct messages.
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

  /// Whether this is a one-to-one direct-message conversation.
  final bool isIm;

  /// The other participant's user ID for a one-to-one direct message.
  final String? userId;
}
