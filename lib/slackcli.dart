/// Dart package for interacting with the Slack Web API.
///
/// Provides a client for posting messages, listing channels, and joining
/// channels, along with OAuth authentication and local credential storage.
///
/// ```dart
/// import 'package:slackcli/slackcli.dart';
///
/// final client = SlackApiClient(token: 'xoxp-...');
/// await client.postMessage(channel: 'C123', text: 'Hello!');
/// ```
library;

export 'src/auth/auth.dart';
export 'src/slack_api/slack_api.dart';
