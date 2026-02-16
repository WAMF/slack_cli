import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:slackcli/src/slack_api/slack_urls.dart';

/// Thrown when the Slack API returns a non-ok response.
class SlackApiException implements Exception {
  /// Creates a [SlackApiException] with the given Slack API [error] string.
  const SlackApiException(this.error);

  /// The error code returned by the Slack API (e.g. `invalid_auth`).
  final String error;

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
      );
    }
    return json;
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

    final response = await _httpClient.get(
      uri,
      headers: {'Authorization': 'Bearer $_token'},
    );

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw SlackApiException(
        json['error'] as String? ?? 'unknown_error',
      );
    }

    return (json['channels'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

  /// Releases the underlying HTTP client resources.
  void close() => _httpClient.close();
}
