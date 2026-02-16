/// A posted Slack message.
class SlackMessage {
  /// Creates a [SlackMessage].
  const SlackMessage({
    required this.channel,
    required this.ts,
    required this.text,
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

  /// The channel the message was posted to.
  final String channel;

  /// The message timestamp (used for threading and identification).
  final String ts;

  /// The message text content.
  final String text;
}
