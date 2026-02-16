# slackcli

[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]
[![License: MIT][license_badge]][license_link]

A Dart package and CLI for interacting with the Slack Web API.

## Package API

Use `slackcli` as a library in any Dart or Flutter app:

```dart
import 'package:slackcli/slackcli.dart';
```

### SlackApiClient

Authenticated HTTP client for the Slack Web API.

```dart
final client = SlackApiClient(token: 'xoxp-...');

// Post a message
await client.postMessage(channel: 'C0123ABCDEF', text: 'Hello!');

// Reply to a thread
await client.postMessage(
  channel: 'C0123ABCDEF',
  text: 'Thread reply',
  threadTs: '1234567890.123456',
);

// Send a DM (pass a user ID as the channel)
await client.postMessage(channel: 'U0123ABCDEF', text: 'Hey!');

// List channels
final channels = await client.listChannels();
for (final channel in channels) {
  print('${channel['name']} (${channel['id']})');
}

// Join a public channel
await client.joinChannel('C0123ABCDEF');

// Release resources when done
client.close();
```

All methods throw `SlackApiException` when the API returns an error. `postMessage` automatically joins the channel on `not_in_channel` and retries.

### OAuthFlow

Runs the Slack OAuth 2.0 V2 authorization flow over a local HTTPS server.

```dart
final flow = OAuthFlow(
  clientId: 'your-client-id',
  clientSecret: 'your-client-secret',
  logger: Logger(),
);

final credentials = await flow.execute();
print('Token: ${credentials.accessToken}');
print('Team: ${credentials.teamName}');
```

Opens the user's browser, listens on `https://localhost:8585/callback`, and exchanges the authorization code for a user token. A self-signed TLS certificate is generated automatically in `~/.slackcli/`.

### CredentialsStore

Persists OAuth credentials to `~/.slackcli/credentials.json` with `0600` file permissions.

```dart
final store = CredentialsStore();

// Save after login
store.save(credentials);

// Load later
final loaded = store.load(); // returns null if not logged in

// Check existence
if (store.hasCredentials) { ... }

// Remove on logout
store.delete();
```

### Credentials

Data class holding the access token and workspace metadata.

| Field | Type | Description |
|---|---|---|
| `accessToken` | `String` | OAuth user token (`xoxp-...`) |
| `teamId` | `String` | Workspace ID |
| `teamName` | `String` | Workspace name |
| `userId` | `String?` | Authenticated user ID |

Supports `fromJson` / `toJson` for serialization.

---

## CLI

### Prerequisites

- Dart SDK `^3.10.0` (included with Flutter 3.41+)
- A Slack app with the required OAuth scopes (see [Slack App Setup](#slack-app-setup))

### Slack App Setup

1. Go to https://api.slack.com/apps and create a new app **From scratch**.
2. Under **OAuth & Permissions**, add these **User Token Scopes**:
   - `chat:write`
   - `channels:read`
   - `channels:write`
   - `groups:read`
   - `im:write`
   - `users:read`
3. Under **OAuth & Permissions** > **Redirect URLs**, add:
   ```
   https://localhost:8585/callback
   ```
4. Copy your **Client ID** and **Client Secret** from **Basic Information**.
5. Create a `.env` file in the project root (see `.env.example`):
   ```
   SLACK_CLIENT_ID=<your-client-id>
   SLACK_CLIENT_SECRET=<your-client-secret>
   ```
   Alternatively, set these as environment variables.

### Getting Started

```sh
dart pub get
```

### Commands

```sh
# Authenticate
dart run bin/slackcli.dart login

# List channels
dart run bin/slackcli.dart channels

# Send a message
dart run bin/slackcli.dart send -c <channel-id> -t "Hello from the CLI"

# Reply to a thread
dart run bin/slackcli.dart reply -c <channel-id> -r <thread_ts> -t "Thread reply"

# Send a DM
dart run bin/slackcli.dart dm -u <user-id> -t "Hey there"

# Log out
dart run bin/slackcli.dart logout
```

---

## Running Tests

```sh
dart test
```

### With coverage

```sh
dart pub global activate coverage 1.15.0
dart test --coverage=coverage
dart pub global run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info
genhtml coverage/lcov.info -o coverage/
open coverage/index.html
```

---

[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
[very_good_analysis_badge]: https://img.shields.io/badge/style-very_good_analysis-B22C89.svg
[very_good_analysis_link]: https://pub.dev/packages/very_good_analysis
