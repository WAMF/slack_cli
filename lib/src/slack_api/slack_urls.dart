/// URI constants for the Slack Web API and OAuth endpoints.
abstract final class SlackUrls {
  /// OAuth 2.0 V2 authorization endpoint.
  static final Uri authorize = Uri.parse(
    'https://slack.com/oauth/v2/authorize',
  );

  /// OAuth 2.0 V2 token exchange endpoint.
  static final Uri tokenExchange = Uri.parse(
    'https://slack.com/api/oauth.v2.access',
  );

  /// Post a message to a channel, thread, or DM.
  static final Uri postMessage = Uri.parse(
    'https://slack.com/api/chat.postMessage',
  );

  /// Join a public channel.
  static final Uri conversationsJoin = Uri.parse(
    'https://slack.com/api/conversations.join',
  );

  /// List conversations the caller has access to.
  static final Uri conversationsList = Uri.parse(
    'https://slack.com/api/conversations.list',
  );
}
