import 'package:dart_slack/src/auth/credentials_store.dart';
import 'package:dart_slack/src/models/models.dart';
import 'package:dart_slack/src/slack_api/slack_api_client.dart';
import 'package:http/http.dart' as http;

/// How [Slack.editCanvas] applies new content to an existing canvas.
enum CanvasEditMode {
  /// Replace the entire canvas body.
  replace('replace'),

  /// Append the content after the existing body.
  append('insert_at_end'),

  /// Insert the content before the existing body.
  prepend('insert_at_start')
  ;

  const CanvasEditMode(this.operation);

  /// The Slack `canvases.edit` operation name.
  final String operation;

  /// Resolves a CLI `--mode` value, defaulting to [replace] for any unknown
  /// value.
  static CanvasEditMode fromName(String? name) => switch (name) {
    'append' => CanvasEditMode.append,
    'prepend' => CanvasEditMode.prepend,
    _ => CanvasEditMode.replace,
  };
}

/// High-level facade for the Slack Web API.
///
/// Wraps [SlackApiClient] with typed return values for common operations.
///
/// ```dart
/// final slack = Slack(token: 'xoxp-...');
/// final msg = await slack.postMessage(channel: 'C123', text: 'Hello!');
/// print(msg.ts);
/// slack.close();
/// ```
class Slack {
  /// Creates a [Slack] instance authenticated with [token].
  Slack({required String token, http.Client? httpClient})
    : _client = SlackApiClient(token: token, httpClient: httpClient);

  /// Creates a [Slack] instance from a [SlackApiClient].
  ///
  /// Useful for testing or when you already have a configured client.
  Slack.fromClient(SlackApiClient client) : _client = client;

  /// Creates a [Slack] instance from stored credentials.
  ///
  /// Returns `null` if no credentials are saved.
  static Slack? fromStore({
    CredentialsStore? store,
    http.Client? httpClient,
  }) {
    final credentials = (store ?? CredentialsStore()).load();
    if (credentials == null) return null;
    return Slack(token: credentials.accessToken, httpClient: httpClient);
  }

  final SlackApiClient _client;

  /// Posts a message to [channel].
  ///
  /// Pass a user ID as [channel] to send a DM.
  /// Pass [threadTs] to reply in a thread.
  /// Automatically joins the channel if the user is not a member.
  Future<SlackMessage> postMessage({
    required String channel,
    required String text,
    String? threadTs,
  }) async {
    final json = await _client.postMessage(
      channel: channel,
      text: text,
      threadTs: threadTs,
    );
    return SlackMessage.fromJson(json);
  }

  /// Lists channels the authenticated user has access to.
  Future<List<SlackChannel>> listChannels({
    bool excludeArchived = true,
  }) async {
    final channels = await _client.listChannels(
      excludeArchived: excludeArchived,
    );
    return channels.map(SlackChannel.fromJson).toList();
  }

  /// Updates an existing message.
  Future<SlackMessage> updateMessage({
    required String channel,
    required String ts,
    required String text,
  }) async {
    final json = await _client.updateMessage(
      channel: channel,
      ts: ts,
      text: text,
    );
    return SlackMessage.fromJson(json);
  }

  /// Deletes a message.
  Future<void> deleteMessage({
    required String channel,
    required String ts,
  }) => _client.deleteMessage(channel: channel, ts: ts);

  /// Joins a public channel by [channelId].
  Future<void> joinChannel(String channelId) => _client.joinChannel(channelId);

  /// Fetches message history for [channel].
  Future<CursorPage<SlackMessage>> conversationsHistory({
    required String channel,
    int limit = 100,
    String? cursor,
    String? oldest,
    String? latest,
  }) async {
    final json = await _client.conversationsHistory(
      channel: channel,
      limit: limit,
      cursor: cursor,
      oldest: oldest,
      latest: latest,
    );
    final messages = (json['messages'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((m) => SlackMessage.fromHistory(channel: channel, json: m))
        .toList();
    return CursorPage(
      items: messages,
      hasMore: json['has_more'] as bool? ?? false,
      nextCursor: _nextCursor(json),
    );
  }

  /// Fetches thread replies for [channel] starting at [ts].
  Future<CursorPage<SlackMessage>> conversationsReplies({
    required String channel,
    required String ts,
    int limit = 100,
    String? cursor,
  }) async {
    final json = await _client.conversationsReplies(
      channel: channel,
      ts: ts,
      limit: limit,
      cursor: cursor,
    );
    final messages = (json['messages'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((m) => SlackMessage.fromHistory(channel: channel, json: m))
        .toList();
    return CursorPage(
      items: messages,
      hasMore: json['has_more'] as bool? ?? false,
      nextCursor: _nextCursor(json),
    );
  }

  /// Gets detailed information about [channel].
  Future<SlackChannel> conversationsInfo({
    required String channel,
  }) async {
    final json = await _client.conversationsInfo(channel: channel);
    return SlackChannel.fromJson(json['channel'] as Map<String, dynamic>);
  }

  /// Lists member user IDs for [channel].
  Future<CursorPage<String>> conversationsMembers({
    required String channel,
    int limit = 100,
    String? cursor,
  }) async {
    final json = await _client.conversationsMembers(
      channel: channel,
      limit: limit,
      cursor: cursor,
    );
    final members = (json['members'] as List<dynamic>).cast<String>();
    final next = _nextCursor(json);
    return CursorPage(
      items: members,
      hasMore: next != null,
      nextCursor: next,
    );
  }

  /// Lists all users in the workspace.
  Future<CursorPage<SlackUser>> usersList({
    int limit = 100,
    String? cursor,
  }) async {
    final json = await _client.usersList(limit: limit, cursor: cursor);
    final users = (json['members'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(SlackUser.fromJson)
        .toList();
    final next = _nextCursor(json);
    return CursorPage(
      items: users,
      hasMore: next != null,
      nextCursor: next,
    );
  }

  /// Gets detailed information about a [user].
  Future<SlackUser> usersInfo({required String user}) async {
    final json = await _client.usersInfo(user: user);
    return SlackUser.fromJson(json['user'] as Map<String, dynamic>);
  }

  /// Creates a canvas containing [markdown] and returns its ID.
  ///
  /// Pass [title] to name the canvas, and [channel] to tab the canvas into
  /// that channel instead of creating a standalone one.
  Future<String> createCanvas({
    required String markdown,
    String? title,
    String? channel,
  }) async {
    final json = await _client.createCanvas(
      content: markdown,
      title: title,
      channel: channel,
    );
    return json['canvas_id'] as String;
  }

  /// Updates the canvas [canvasId] with [markdown].
  ///
  /// [mode] selects whether the content replaces the body or is appended /
  /// prepended.
  Future<void> editCanvas({
    required String canvasId,
    required String markdown,
    CanvasEditMode mode = CanvasEditMode.replace,
  }) => _client.editCanvas(
    canvasId: canvasId,
    changes: [
      {
        'operation': mode.operation,
        'document_content': {'type': 'markdown', 'markdown': markdown},
      },
    ],
  );

  /// Reads the markdown body of the canvas [canvasId].
  ///
  /// Slack has no `canvases.get` method, so a canvas is read by looking up
  /// its backing file with `files.info` and downloading the body from the
  /// file's `url_private_download` URL. Returns the canvas content as served
  /// by Slack (markdown).
  ///
  /// Returns `null` when the looked-up file is not a canvas, or carries no
  /// downloadable URL — e.g. the ID is not a canvas — so the caller can report
  /// it cleanly.
  Future<String?> readCanvas({required String canvasId}) async {
    final json = await _client.filesInfo(file: canvasId);
    final file = json['file'] as Map<String, dynamic>?;
    if (file == null || !_isCanvasFile(file)) return null;
    final url = _canvasDownloadUrl(file);
    if (url == null) return null;
    try {
      return await _client.downloadFile(url);
    } on SlackApiException catch (e) {
      // A non-authorized download answers 200 with an HTML sign-in page;
      // [SlackApiClient.downloadFile] surfaces that as `not_authorized`.
      // Treat it as unreadable so the caller reports the clean scope hint
      // rather than emitting a login page as canvas content.
      if (e.error == 'not_authorized') return null;
      rethrow;
    }
  }

  /// Resolves the authenticated download URL for the canvas-backing [file],
  /// or `null` when it carries no usable URL.
  ///
  /// Never send the bearer token to a host Slack didn't vouch for. The URL
  /// comes from the `files.info` response, but a malformed or unexpected
  /// value must not leak the token off-platform, so require HTTPS and a
  /// Slack-owned download host before authenticating the GET.
  static Uri? _canvasDownloadUrl(Map<String, dynamic> file) {
    final rawUrl =
        (file['url_private_download'] ?? file['url_private']) as String?;
    if (rawUrl == null || rawUrl.isEmpty) return null;
    final url = Uri.tryParse(rawUrl);
    if (url == null ||
        url.scheme != 'https' ||
        !_isSlackDownloadHost(url.host)) {
      return null;
    }
    return url;
  }

  /// Whether [host] is a Slack-owned host that serves authenticated file
  /// downloads. Used to gate the bearer-authenticated canvas download so the
  /// token is never sent to an unexpected host.
  static bool _isSlackDownloadHost(String host) {
    final normalized = host.toLowerCase();
    return normalized == 'slack.com' ||
        normalized.endsWith('.slack.com') ||
        normalized == 'slack-files.com' ||
        normalized.endsWith('.slack-files.com');
  }

  /// Whether the `files.info` [file] object describes a Slack canvas.
  ///
  /// Canvases are served as ordinary files, so `files.info` will happily
  /// return any file id — including non-canvas attachments that also carry a
  /// `url_private_download` URL. Guarding on the canvas markers keeps
  /// [readCanvas] from downloading an arbitrary non-canvas file. Slack tags a
  /// canvas with `filetype: "canvas"` (legacy: `"quip"`), `pretty_type:
  /// "Canvas"`, and, for channel canvases, `mode: "canvas"`.
  static bool _isCanvasFile(Map<String, dynamic> file) {
    final filetype = (file['filetype'] as String?)?.toLowerCase();
    final prettyType = (file['pretty_type'] as String?)?.toLowerCase();
    final mode = (file['mode'] as String?)?.toLowerCase();
    return filetype == 'canvas' ||
        filetype == 'quip' ||
        prettyType == 'canvas' ||
        mode == 'canvas';
  }

  /// Deletes the canvas [canvasId].
  Future<void> deleteCanvas({required String canvasId}) =>
      _client.deleteCanvas(canvasId: canvasId);

  /// Sets the authenticated user's custom status.
  ///
  /// [expiration] is a Unix timestamp (seconds) after which Slack clears
  /// the status automatically; `0` keeps it until cleared. Requires a user
  /// token (`xoxp-...`) with the `users.profile:write` scope.
  Future<void> setStatus({
    required String text,
    String emoji = '',
    int expiration = 0,
  }) => _client.usersProfileSet(
    statusText: text,
    statusEmoji: emoji,
    statusExpiration: expiration,
  );

  /// Clears the authenticated user's custom status.
  Future<void> clearStatus() => _client.usersProfileSet(
    statusText: '',
    statusEmoji: '',
  );

  /// Releases the underlying HTTP client resources.
  void close() => _client.close();

  /// Extracts `next_cursor` from `response_metadata`, treating empty
  /// strings as absent.
  static String? _nextCursor(Map<String, dynamic> json) {
    final metadata = json['response_metadata'] as Map<String, dynamic>?;
    final cursor = metadata?['next_cursor'] as String?;
    return (cursor != null && cursor.isNotEmpty) ? cursor : null;
  }
}
