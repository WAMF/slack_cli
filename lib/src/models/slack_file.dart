/// A file attached to a Slack message.
class SlackFile {
  /// Creates a [SlackFile].
  const new({required this.name});

  /// Deserializes from a Slack API file object.
  factory fromJson(Map<String, dynamic> json) {
    return SlackFile(name: json['name'] as String? ?? 'untitled');
  }

  /// The file name.
  final String name;
}
