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

  /// Releases the underlying HTTP client resources.
  void close() => _client.close();
}
