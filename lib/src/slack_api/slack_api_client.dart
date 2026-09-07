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

  /// Opens (or looks up) the direct-message conversation with [user].
  ///
  /// Returns the raw response map, which contains a `channel` object whose
  /// `id` is the DM conversation ID (`D...`). Unlike `chat.postMessage`,
  /// which accepts a user ID directly, `files.completeUploadExternal`
  /// requires this resolved conversation ID as `channel_id`.
  Future<Map<String, dynamic>> conversationsOpen({
    required String user,
  }) => _post(SlackUrls.conversationsOpen, {'users': user});

  /// Searches messages the authenticated user can see for [query].
  ///
  /// [query] accepts Slack's search modifiers, for example `in:#incidents`,
  /// `from:@lee`, `before:2026-08-01`. [count] caps the matches per page and
  /// [page] selects the 1-based page.
  ///
  /// Requires a user token (`xoxp-...`) with the `search:read` scope. A bot
  /// token cannot call this method at all.
  ///
  /// Returns a map containing `messages`, which holds the `matches` list and
  /// the `paging` metadata.
  Future<Map<String, dynamic>> searchMessages({
    required String query,
    int count = 20,
    int page = 1,
  }) async {
    final params = <String, String>{
      'query': query,
      'count': '$count',
      'page': '$page',
    };
    return _get(SlackUrls.searchMessages.replace(queryParameters: params));
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

  /// Gets metadata about the file identified by [file].
  ///
  /// For a canvas (`filetype: canvas`/`quip`), the returned `file` object
  /// carries a `url_private_download` URL from which the canvas body can be
  /// fetched with [downloadFile]. Requires the `files:read` scope.
  Future<Map<String, dynamic>> filesInfo({
    required String file,
  }) {
    final params = <String, String>{'file': file};
    return _get(SlackUrls.filesInfo.replace(queryParameters: params));
  }

  /// Requests a pre-signed upload URL for a file named [filename] whose
  /// content is [length] bytes long.
  ///
  /// Returns the raw response map, which contains `upload_url` and `file_id`
  /// on success. The first step of Slack's external upload flow (the
  /// `files.upload` method it replaces is deprecated).
  Future<Map<String, dynamic>> getUploadUrlExternal({
    required String filename,
    required int length,
  }) {
    final params = <String, String>{
      'filename': filename,
      'length': '$length',
    };
    return _get(
      SlackUrls.filesGetUploadURLExternal.replace(queryParameters: params),
    );
  }

  /// Uploads [bytes] to the pre-signed [uploadUrl] returned by
  /// [getUploadUrlExternal].
  ///
  /// The second step of Slack's external upload flow. Unlike the other
  /// `slack.com/api/*` endpoints, this URL does not answer a `{ok: ...}`
  /// JSON envelope, so a non-2xx status is the only failure signal.
  Future<void> uploadFileBytes({
    required Uri uploadUrl,
    required List<int> bytes,
    required String filename,
  }) async {
    final request = http.MultipartRequest('POST', uploadUrl)
      ..files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );
    final streamedResponse = await _httpClient.send(request);
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SlackApiException('upload_failed_${response.statusCode}');
    }
  }

  /// Finalizes an upload for the file identified by [fileId], optionally
  /// attaching it to [channel] (and [threadTs], to post it in a thread) with
  /// [initialComment] as the accompanying message text.
  ///
  /// The third and final step of Slack's external upload flow. Returns the
  /// raw response map.
  Future<Map<String, dynamic>> completeUploadExternal({
    required String fileId,
    required String filename,
    String? channel,
    String? threadTs,
    String? initialComment,
  }) => _post(SlackUrls.filesCompleteUploadExternal, {
    'files': [
      {'id': fileId, 'title': filename},
    ],
    'channel_id': ?channel,
    'thread_ts': ?threadTs,
    'initial_comment': ?initialComment,
  });

  /// Downloads the raw body served at [url], authenticated with the bearer
  /// token, and returns it as a string.
  ///
  /// Slack stores canvas content as a downloadable file rather than exposing
  /// it inline, so reading a canvas means fetching its `url_private_download`
  /// URL. Unlike the JSON API helpers this returns the response body verbatim
  /// (markdown/HTML), and throws [SlackApiException] on a non-2xx response.
  ///
  /// Slack's `url_private(_download)` endpoints have a well-known quirk: when
  /// the token is not authorized for the file they answer **200 with an HTML
  /// sign-in page** instead of a 4xx. Returning that login shell verbatim
  /// would be a silent wrong-content failure, so a 200 response whose
  /// `content-type` is HTML (or whose body opens with an HTML document) is
  /// rejected with [SlackApiException]`('not_authorized')`.
  Future<String> downloadFile(Uri url) async {
    final response = await _sendWithRetry(
      () => _httpClient.get(
        url,
        headers: {'Authorization': 'Bearer $_token'},
      ),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SlackApiException('download_failed_${response.statusCode}');
    }
    if (_isHtmlResponse(response)) {
      throw const SlackApiException('not_authorized');
    }
    return response.body;
  }

  /// Whether [response] looks like Slack's HTML sign-in/error shell rather
  /// than a downloadable file body.
  ///
  /// Prefers the authoritative `content-type` header and falls back to
  /// sniffing the start of the body for an HTML document marker, so a missing
  /// or generic content type is still caught.
  static bool _isHtmlResponse(http.Response response) {
    final contentType = (response.headers['content-type'] ?? '').toLowerCase();
    if (contentType.contains('text/html') ||
        contentType.contains('application/xhtml')) {
      return true;
    }
    final head = response.body.trimLeft().toLowerCase();
    return head.startsWith('<!doctype html') || head.startsWith('<html');
  }

  /// Sets the authenticated user's custom status via `users.profile.set`.
  ///
  /// Pass empty strings (and `0` for [statusExpiration]) to clear the
  /// status. [statusExpiration] is a Unix timestamp (seconds) after which
  /// Slack clears the status automatically; `0` keeps it until cleared.
  ///
  /// Requires a user token (`xoxp-...`) with the `users.profile:write`
  /// scope — bot tokens fail with `not_allowed_token_type`.
  Future<Map<String, dynamic>> usersProfileSet({
    required String statusText,
    required String statusEmoji,
    int statusExpiration = 0,
  }) => _post(SlackUrls.usersProfileSet, {
    'profile': {
      'status_text': statusText,
      'status_emoji': statusEmoji,
      'status_expiration': statusExpiration,
    },
  });

  /// Verifies the token is valid and returns identity details.
  ///
  /// Wraps `auth.test`. Throws [SlackApiException] (e.g. `invalid_auth`,
  /// `token_revoked`, `token_expired`) when the token cannot authenticate.
  Future<Map<String, dynamic>> authTest() =>
      _post(SlackUrls.authTest, const {});

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
