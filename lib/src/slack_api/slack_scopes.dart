/// OAuth permission scopes requested during authorization.
abstract final class SlackScopes {
  static const _channelsHistory = 'channels:history';
  static const _channelsRead = 'channels:read';
  static const _channelsWrite = 'channels:write';
  static const _chatWrite = 'chat:write';
  static const _canvasesRead = 'canvases:read';
  static const _canvasesWrite = 'canvases:write';
  static const _filesRead = 'files:read';
  static const _filesWrite = 'files:write';
  static const _groupsHistory = 'groups:history';
  static const _groupsRead = 'groups:read';
  static const _imWrite = 'im:write';
  static const _usersRead = 'users:read';
  static const _usersReadEmail = 'users:read.email';
  static const _usersProfileWrite = 'users.profile:write';

  /// All scopes required by the CLI.
  static const List<String> values = [
    _channelsHistory,
    _channelsRead,
    _channelsWrite,
    _chatWrite,
    _canvasesRead,
    _canvasesWrite,
    _filesRead,
    _filesWrite,
    _groupsHistory,
    _groupsRead,
    _imWrite,
    _usersRead,
    _usersReadEmail,
    _usersProfileWrite,
  ];

  /// Comma-separated scope string for the OAuth authorize URL.
  static String get joined => values.join(',');
}
