import 'package:dart_slack/src/auth/credentials_store.dart';
import 'package:dart_slack/src/models/models.dart';
import 'package:dart_slack/src/slack_api/slack_api_client.dart';
import 'package:http/http.dart' as http;

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

  /// Joins a public channel by [channelId].
  Future<void> joinChannel(String channelId) =>
      _client.joinChannel(channelId);

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
