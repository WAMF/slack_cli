/// Dart package for interacting with the Slack Web API.
///
/// The primary entry point is the `Slack` facade class, which provides
/// typed methods for posting messages, listing channels, and more.
///
/// ```dart
/// import 'package:dart_slack/dart_slack.dart';
///
/// final slack = Slack(token: 'xoxp-...');
/// final msg = await slack.postMessage(channel: 'C123', text: 'Hello!');
/// print(msg.ts);
/// slack.close();
/// ```
library;

export 'src/auth/auth.dart';
export 'src/models/models.dart';
export 'src/slack.dart';
export 'src/slack_api/slack_api.dart';
export 'src/socket_mode/socket_mode.dart';
