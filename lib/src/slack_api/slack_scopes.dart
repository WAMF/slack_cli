/// OAuth permission scopes requested during authorization.
abstract final class SlackScopes {
  static const _chatWrite = 'chat:write';
  static const _channelsRead = 'channels:read';
  static const _channelsWrite = 'channels:write';
  static const _groupsRead = 'groups:read';
  static const _imWrite = 'im:write';
  static const _usersRead = 'users:read';

  /// All scopes required by the CLI.
  static const List<String> values = [
    _chatWrite,
    _channelsRead,
    _channelsWrite,
    _groupsRead,
    _imWrite,
    _usersRead,
  ];

  /// Comma-separated scope string for the OAuth authorize URL.
  static String get joined => values.join(',');
}
