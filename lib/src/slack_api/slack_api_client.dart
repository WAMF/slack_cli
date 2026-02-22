import 'dart:convert';

import 'package:dart_slack/src/slack_api/slack_urls.dart';
import 'package:http/http.dart' as http;

/// Thrown when the Slack API returns a non-ok response.
class SlackApiException implements Exception {
  /// Creates a [SlackApiException] from the decoded JSON error response.
  const SlackApiException(this.error, {this.needed});

  /// The error code returned by the Slack API (e.g. `invalid_auth`).
  final String error;

  /// The OAuth scope required for the request, present on `missing_scope`.
  final String? needed;

  @override
  String toString() => 'SlackApiException: $error';
}

/// HTTP client wrapper for the Slack Web API.
///
/// All methods throw [SlackApiException] when the API returns `ok: false`.
class SlackApiClient {
  /// Creates a [SlackApiClient] authenticated with [token].
  ///
  /// An optional [httpClient] can be provided for testing.
  SlackApiClient({required String token, http.Client? httpClient})
    : _token = token,
      _httpClient = httpClient ?? http.Client();

  final String _token;
  final http.Client _httpClient;

  /// Posts a message to the given [channel].
  ///
  /// Optionally provide [threadTs] to reply in a thread.
  /// Automatically joins the channel if the user is not a member.
  /// Returns the raw Slack API response map.
  Future<Map<String, dynamic>> postMessage({
    required String channel,
    required String text,
    String? threadTs,
  }) async {
    final result = await _postMessageRaw(
      channel: channel,
      text: text,
      threadTs: threadTs,
    );

    final json = jsonDecode(result.body) as Map<String, dynamic>;
    if (json['ok'] == true) return json;

    final error = json['error'] as String? ?? 'unknown_error';
    if (error == 'not_in_channel') {
      await joinChannel(channel);
      return _postMessageChecked(
        channel: channel,
        text: text,
        threadTs: threadTs,
      );
    }

    throw SlackApiException(error);
  }

  /// Joins a public channel by [channelId].
  Future<void> joinChannel(String channelId) async {
    final response = await _httpClient.post(
      SlackUrls.conversationsJoin,
      headers: {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: jsonEncode({'channel': channelId}),
    );

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw SlackApiException(
        json['error'] as String? ?? 'unknown_error',
      );
    }
  }

  /// Lists channels the authenticated user has access to.
  ///
  /// Returns a list of channel maps, each containing at minimum
  /// `id`, `name`, and `is_private`.
  Future<List<Map<String, dynamic>>> listChannels({
    bool excludeArchived = true,
  }) async {
    final uri = SlackUrls.conversationsList.replace(
      queryParameters: {
        'exclude_archived': '$excludeArchived',
        'types': 'public_channel,private_channel',
        'limit': '200',
      },
    );

    final json = await _get(uri);
    return (json['channels'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

  /// Fetches message history for [channel].
  ///
  /// Returns a map containing `messages` (list) and pagination metadata.
  Future<Map<String, dynamic>> conversationsHistory({
    required String channel,
    int limit = 100,
    String? cursor,
    String? oldest,
    String? latest,
  }) async {
    final params = <String, String>{
      'channel': channel,
      'limit': '$limit',
      'cursor': ?cursor,
      'oldest': ?oldest,
      'latest': ?latest,
    };
    return _get(
      SlackUrls.conversationsHistory.replace(queryParameters: params),
    );
  }

  /// Fetches thread replies for [channel] starting at [ts].
  ///
  /// Returns a map containing `messages` (list) and pagination metadata.
  Future<Map<String, dynamic>> conversationsReplies({
    required String channel,
    required String ts,
    int limit = 100,
    String? cursor,
    String? oldest,
    String? latest,
  }) async {
    final params = <String, String>{
      'channel': channel,
      'ts': ts,
      'limit': '$limit',
      'cursor': ?cursor,
      'oldest': ?oldest,
      'latest': ?latest,
    };
    return _get(
      SlackUrls.conversationsReplies.replace(queryParameters: params),
    );
  }

  /// Gets detailed information about [channel].
  Future<Map<String, dynamic>> conversationsInfo({
    required String channel,
  }) {
    final params = <String, String>{'channel': channel};
    return _get(
      SlackUrls.conversationsInfo.replace(queryParameters: params),
    );
  }

  /// Lists member user IDs for [channel].
  ///
  /// Returns a map containing `members` (list of strings) and pagination
  /// metadata.
  Future<Map<String, dynamic>> conversationsMembers({
    required String channel,
    int limit = 100,
    String? cursor,
  }) async {
    final params = <String, String>{
      'channel': channel,
      'limit': '$limit',
      'cursor': ?cursor,
    };
    return _get(
      SlackUrls.conversationsMembers.replace(queryParameters: params),
    );
  }

  /// Lists all users in the workspace.
  ///
  /// Returns a map containing `members` (list) and pagination metadata.
  Future<Map<String, dynamic>> usersList({
    int limit = 100,
    String? cursor,
  }) async {
    final params = <String, String>{
      'limit': '$limit',
      'cursor': ?cursor,
    };
    return _get(SlackUrls.usersList.replace(queryParameters: params));
  }

  /// Gets detailed information about a [user].
  Future<Map<String, dynamic>> usersInfo({
    required String user,
  }) {
    final params = <String, String>{'user': user};
    return _get(SlackUrls.usersInfo.replace(queryParameters: params));
  }

  /// Releases the underlying HTTP client resources.
  void close() => _httpClient.close();

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Sends a GET request and returns the decoded JSON body.
  ///
  /// Throws [SlackApiException] when the response contains `ok: false`.
  Future<Map<String, dynamic>> _get(Uri uri) async {
    final response = await _httpClient.get(
      uri,
      headers: {'Authorization': 'Bearer $_token'},
    );
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw SlackApiException(
        json['error'] as String? ?? 'unknown_error',
        needed: json['needed'] as String?,
      );
    }
    return json;
  }

  Future<http.Response> _postMessageRaw({
    required String channel,
    required String text,
    String? threadTs,
  }) {
    final body = <String, dynamic>{
      'channel': channel,
      'text': text,
      'thread_ts': ?threadTs,
    };

    return _httpClient.post(
      SlackUrls.postMessage,
      headers: {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: jsonEncode(body),
    );
  }

  Future<Map<String, dynamic>> _postMessageChecked({
    required String channel,
    required String text,
    String? threadTs,
  }) async {
    final response = await _postMessageRaw(
      channel: channel,
      text: text,
      threadTs: threadTs,
    );

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw SlackApiException(
        json['error'] as String? ?? 'unknown_error',
        needed: json['needed'] as String?,
      );
    }
    return json;
  }
}
