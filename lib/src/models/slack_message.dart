/// A posted Slack message.
class SlackMessage {
  /// Creates a [SlackMessage].
  const SlackMessage({
    required this.channel,
    required this.ts,
    required this.text,
    this.user,
    this.threadTs,
    this.replyCount,
  });

  /// Deserializes from a `chat.postMessage` response.
  factory SlackMessage.fromJson(Map<String, dynamic> json) {
    final message = json['message'] as Map<String, dynamic>?;
    return SlackMessage(
      channel: json['channel'] as String,
      ts: json['ts'] as String,
      text: message?['text'] as String? ?? '',
    );
  }

  /// Deserializes from a `conversations.history` or `conversations.replies`
  /// message object.
  factory SlackMessage.fromHistory({
    required String channel,
    required Map<String, dynamic> json,
  }) {
    return SlackMessage(
      channel: channel,
      ts: json['ts'] as String,
      text: json['text'] as String? ?? '',
      user: json['user'] as String?,
      threadTs: json['thread_ts'] as String?,
      replyCount: json['reply_count'] as int?,
    );
  }

  /// The channel the message was posted to.
  final String channel;

  /// The message timestamp (used for threading and identification).
  final String ts;

  /// The message text content.
  final String text;

  /// The user ID who posted the message.
  final String? user;

  /// The thread parent timestamp, if this message is in a thread.
  final String? threadTs;

  /// The number of replies, if this is a thread parent.
  final int? replyCount;
}
