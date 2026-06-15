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

  /// Delete a message.
  static final Uri chatDelete = Uri.parse(
    'https://slack.com/api/chat.delete',
  );

  /// Post a message to a channel, thread, or DM.
  static final Uri postMessage = Uri.parse(
    'https://slack.com/api/chat.postMessage',
  );

  /// Update the text of an existing message.
  static final Uri chatUpdate = Uri.parse(
    'https://slack.com/api/chat.update',
  );

  /// Join a public channel.
  static final Uri conversationsJoin = Uri.parse(
    'https://slack.com/api/conversations.join',
  );

  /// List conversations the caller has access to.
  static final Uri conversationsList = Uri.parse(
    'https://slack.com/api/conversations.list',
  );

  /// Fetch message history for a conversation.
  static final Uri conversationsHistory = Uri.parse(
    'https://slack.com/api/conversations.history',
  );

  /// Fetch replies to a thread.
  static final Uri conversationsReplies = Uri.parse(
    'https://slack.com/api/conversations.replies',
  );

  /// Get information about a conversation.
  static final Uri conversationsInfo = Uri.parse(
    'https://slack.com/api/conversations.info',
  );

  /// List members of a conversation.
  static final Uri conversationsMembers = Uri.parse(
    'https://slack.com/api/conversations.members',
  );

  /// List all users in the workspace.
  static final Uri usersList = Uri.parse(
    'https://slack.com/api/users.list',
  );

  /// Get information about a user.
  static final Uri usersInfo = Uri.parse(
    'https://slack.com/api/users.info',
  );

  /// Create a canvas (optionally tabbed into a channel).
  static final Uri canvasesCreate = Uri.parse(
    'https://slack.com/api/canvases.create',
  );

  /// Apply changes to an existing canvas.
  static final Uri canvasesEdit = Uri.parse(
    'https://slack.com/api/canvases.edit',
  );

  /// Delete a canvas.
  static final Uri canvasesDelete = Uri.parse(
    'https://slack.com/api/canvases.delete',
  );

  /// Set the authenticated user's profile, including custom status.
  static final Uri usersProfileSet = Uri.parse(
    'https://slack.com/api/users.profile.set',
  );
}
