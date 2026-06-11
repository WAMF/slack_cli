import 'dart:convert';

import 'package:dart_slack/src/slack_api/slack_urls.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

class _Retry {
  static const maxAttempts = 3;
}

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
  /// An optional [httpClient] can be provided for testing. The [delay]
  /// callback is used for rate-limit back-off and can be replaced in tests.
  SlackApiClient({
    required String token,
    http.Client? httpClient,
    @visibleForTesting Future<void> Function(Duration)? delay,
  }) : _token = token,
       _httpClient = httpClient ?? http.Client(),
       _delay = delay ?? Future.delayed;

  final String _token;
  final http.Client _httpClient;
  final Future<void> Function(Duration) _delay;

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
    final body = <String, dynamic>{
      'channel': channel,
      'text': text,
      'thread_ts': ?threadTs,
    };
    final response = await _postRaw(SlackUrls.postMessage, body);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['ok'] == true) return json;

    final error = json['error'] as String? ?? 'unknown_error';
    if (error == 'not_in_channel') {
      await joinChannel(channel);
      return _post(SlackUrls.postMessage, body);
    }

    throw SlackApiException(
      error,
      needed: json['needed'] as String?,
    );
  }

  /// Joins a public channel by [channelId].
  Future<void> joinChannel(String channelId) =>
      _post(SlackUrls.conversationsJoin, {'channel': channelId});

  /// Lists channels the authenticated user has access to.
  ///
  /// Returns a list of channel maps, each containing at minimum
  /// `id`, `name`, and `is_private`.
  Future<List<Map<String, dynamic>>> listChannels({
    bool excludeArchived = true,
  }) async {
    final channels = <Map<String, dynamic>>[];
    String? cursor;

    do {
      final uri = SlackUrls.conversationsList.replace(
        queryParameters: {
          'exclude_archived': '$excludeArchived',
          'types': 'public_channel,private_channel',
          'limit': '200',
          'cursor': ?cursor,
        },
      );

      final json = await _get(uri);
      channels.addAll(
        (json['channels'] as List<dynamic>).cast<Map<String, dynamic>>(),
      );
      cursor = _nextCursor(json);
    } while (cursor != null);

    return channels;
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

  /// Updates the text of an existing message.
  Future<Map<String, dynamic>> updateMessage({
    required String channel,
    required String ts,
    required String text,
  }) => _post(SlackUrls.chatUpdate, {
    'channel': channel,
    'ts': ts,
    'text': text,
  });

  /// Deletes a message from [channel] at [ts].
  Future<void> deleteMessage({
    required String channel,
    required String ts,
  }) => _post(SlackUrls.chatDelete, {
    'channel': channel,
    'ts': ts,
  });

  /// Creates a canvas whose body is the given markdown [content].
  ///
  /// Pass [title] to name the canvas, and [channel] to tab the canvas into
  /// that channel rather than creating a standalone canvas. Returns the raw
  /// Slack API response map, which contains `canvas_id` on success.
  Future<Map<String, dynamic>> createCanvas({
    required String content,
    String? title,
    String? channel,
  }) => _post(SlackUrls.canvasesCreate, {
    'title': ?title,
    'channel_id': ?channel,
    'document_content': {'type': 'markdown', 'markdown': content},
  });

  /// Applies [changes] to the canvas identified by [canvasId].
  ///
  /// Each change is a Slack `canvases.edit` change object (e.g.
  /// `{'operation': 'replace', 'document_content': {...}}`).
  Future<void> editCanvas({
    required String canvasId,
    required List<Map<String, dynamic>> changes,
  }) => _post(SlackUrls.canvasesEdit, {
    'canvas_id': canvasId,
    'changes': changes,
  });

  /// Deletes the canvas identified by [canvasId].
  Future<void> deleteCanvas({required String canvasId}) =>
      _post(SlackUrls.canvasesDelete, {'canvas_id': canvasId});

  /// Releases the underlying HTTP client resources.
  void close() => _httpClient.close();

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Sends an HTTP request, retrying on 429 (rate-limited) responses.
  Future<http.Response> _sendWithRetry(
    Future<http.Response> Function() send,
  ) async {
    for (var attempt = 1; ; attempt++) {
      final response = await send();
      if (response.statusCode != 429 || attempt >= _Retry.maxAttempts) {
        return response;
      }
      final seconds = int.tryParse(response.headers['retry-after'] ?? '') ?? 1;
      await _delay(Duration(seconds: seconds));
    }
  }

  /// Sends a GET request and returns the decoded JSON body.
  ///
  /// Throws [SlackApiException] when the response contains `ok: false`.
  Future<Map<String, dynamic>> _get(Uri uri) async {
    final response = await _sendWithRetry(
      () => _httpClient.get(
        uri,
        headers: {'Authorization': 'Bearer $_token'},
      ),
    );
    return _checkOk(response);
  }

  /// Sends a POST request with a JSON [body] and returns the raw response.
  Future<http.Response> _postRaw(Uri uri, Map<String, dynamic> body) {
    return _sendWithRetry(
      () => _httpClient.post(
        uri,
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: jsonEncode(body),
      ),
    );
  }

  /// Sends a POST request with a JSON [body] and returns the decoded,
  /// ok-checked response.
  Future<Map<String, dynamic>> _post(
    Uri uri,
    Map<String, dynamic> body,
  ) async {
    final response = await _postRaw(uri, body);
    return _checkOk(response);
  }

  /// Decodes [response] and throws [SlackApiException] when `ok` is false.
  Map<String, dynamic> _checkOk(http.Response response) {
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw SlackApiException(
        json['error'] as String? ?? 'unknown_error',
        needed: json['needed'] as String?,
      );
    }
    return json;
  }

  String? _nextCursor(Map<String, dynamic> json) {
    final metadata = json['response_metadata'] as Map<String, dynamic>?;
    final cursor = metadata?['next_cursor'] as String?;
    return (cursor != null && cursor.isNotEmpty) ? cursor : null;
  }
}
