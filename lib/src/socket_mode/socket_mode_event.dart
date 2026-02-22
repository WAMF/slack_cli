/// A message event received over a Socket Mode WebSocket connection.
class SocketModeEvent {
  /// Creates a [SocketModeEvent].
  const SocketModeEvent({
    required this.type,
    required this.channel,
    required this.user,
    required this.text,
    required this.ts,
    this.threadTs,
    this.replyCount,
  });

  /// Deserializes from the inner `payload.event` map of an `events_api`
  /// envelope.
  factory SocketModeEvent.fromJson(Map<String, dynamic> json) {
    return SocketModeEvent(
      type: json['type'] as String? ?? '',
      channel: json['channel'] as String? ?? '',
      user: json['user'] as String? ?? '',
      text: json['text'] as String? ?? '',
      ts: json['ts'] as String? ?? '',
      threadTs: json['thread_ts'] as String?,
      replyCount: json['reply_count'] as int?,
    );
  }

  /// The event type (e.g. `message`).
  final String type;

  /// The channel where the event occurred.
  final String channel;

  /// The user who triggered the event.
  final String user;

  /// The message text content.
  final String text;

  /// The message timestamp.
  final String ts;

  /// The thread parent timestamp, if this message is in a thread.
  final String? threadTs;

  /// The number of replies, if this is a thread parent.
  final int? replyCount;
}
