# dart_slack

[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]
[![License: MIT][license_badge]][license_link]

A Dart package and CLI for interacting with the Slack Web API.

## Package API

Use `dart_slack` as a library in any Dart or Flutter app:

```dart
import 'package:dart_slack/dart_slack.dart';
```

### Slack

High-level facade with typed return values. This is the recommended entry point.

```dart
final slack = Slack(token: 'xoxp-...');

// Post a message
final msg = await slack.postMessage(channel: 'C0123ABCDEF', text: 'Hello!');
print(msg.ts); // message timestamp

// Reply to a thread
await slack.postMessage(
  channel: 'C0123ABCDEF',
  text: 'Thread reply',
  threadTs: '1234567890.123456',
);

// Send a DM (pass a user ID as the channel)
await slack.postMessage(channel: 'U0123ABCDEF', text: 'Hey!');

// List channels
final channels = await slack.listChannels();
for (final channel in channels) {
  print('${channel.name} (${channel.id})');
}

// Join a public channel
await slack.joinChannel('C0123ABCDEF');

// Read a canvas's markdown body (returns null if the id is not a canvas)
final body = await slack.readCanvas(canvasId: 'F0123ABCDEF');
print(body);

// Set your custom status (user token only; expiration is a Unix timestamp)
await slack.setStatus(text: 'Working on a task', emoji: ':gear:');
await slack.clearStatus();

// Release resources when done
slack.close();
```

`postMessage` returns a `SlackMessage`, `listChannels` returns a `List<SlackChannel>`. All methods throw `SlackApiException` when the API returns an error. `postMessage` automatically joins the channel on `not_in_channel` and retries.

You can also create an instance from stored credentials:

```dart
final slack = Slack.fromStore(); // returns null if not logged in
```

### SlackApiClient

Lower-level HTTP client that returns raw `Map<String, dynamic>` responses. Use this when you need direct access to the full Slack API response.

```dart
final client = SlackApiClient(token: 'xoxp-...');
final json = await client.postMessage(channel: 'C0123ABCDEF', text: 'Hello!');
print(json['ts']);
client.close();
```

### SocketModeClient

Real-time event streaming over WebSocket using Slack's [Socket Mode](https://api.slack.com/apis/socket-mode). Requires an app-level token (`xapp-*`).

```dart
import 'package:dart_slack/dart_slack.dart';

final client = SocketModeClient(appToken: 'xapp-...');
await client.connect();

client.events.listen((event) {
  print('${event.channel}: <${event.user}> ${event.text}');
});

// Later...
await client.close();
```

Events are automatically acknowledged. The client reconnects with exponential backoff on disconnect.

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

Opens the user's browser, listens on `https://localhost:8585/callback`, and exchanges the authorization code for a user token. A self-signed TLS certificate is generated automatically in `~/.dart_slack/`. CSRF protection is handled via the OAuth `state` parameter.

### CredentialsStore

Persists OAuth credentials to `~/.dart_slack/credentials.json` with `0600` file permissions.

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

### Models

#### Credentials

Data class holding the access token and workspace metadata.

| Field | Type | Description |
|---|---|---|
| `accessToken` | `String` | OAuth user token (`xoxp-...`) |
| `teamId` | `String` | Workspace ID |
| `teamName` | `String` | Workspace name |
| `userId` | `String?` | Authenticated user ID |

Supports `fromJson` / `toJson` for serialization.

#### SlackMessage

Returned by `Slack.postMessage`.

| Field | Type | Description |
|---|---|---|
| `channel` | `String` | Channel the message was posted to |
| `ts` | `String` | Message timestamp (used for threading) |
| `text` | `String` | Message text content |

#### SlackChannel

Returned by `Slack.listChannels`.

| Field | Type | Description |
|---|---|---|
| `id` | `String` | Channel identifier (e.g. `C0123ABCDEF`) |
| `name` | `String` | Channel name without the `#` prefix |
| `isPrivate` | `bool` | Whether this is a private channel |

---

## CLI

### Prerequisites

- Dart SDK `^3.10.0` (included with Flutter 3.41+)
- A Slack app with the required OAuth scopes (see [Slack App Setup](#slack-app-setup))

### Slack App Setup

1. Go to https://api.slack.com/apps and create a new app **From scratch**.
2. Under **OAuth & Permissions**, add these **User Token Scopes**:
   - `channels:history`
   - `channels:read`
   - `channels:write`
   - `chat:write`
   - `canvases:read` (read canvas content with `canvas read`)
   - `canvases:write` (create/edit/delete canvases)
   - `files:read` (look up a canvas's downloadable file)
   - `groups:read`
   - `im:write`
   - `users:read`

   > **Reading huddle transcripts:** Slack provides no API for huddle *audio*
   > recordings or spoken transcripts — once a huddle ends, the spoken content
   > is permanently inaccessible. What *is* retrievable is the huddle **notes
   > canvas** (notes and links captured during a huddle are saved to a canvas),
   > which `canvas read` fetches, plus the huddle thread messages via `thread`.
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

#### Socket Mode (optional, for `stream` command)

1. Under **Socket Mode**, toggle it on and generate an **App-Level Token** with the `connections:write` scope.
2. Under **Event Subscriptions**, enable events and subscribe to `message.channels`.
3. Add the token to your `.env` file:
   ```env
   SLACK_APP_TOKEN=xapp-...
   ```

### Getting Started

```sh
dart pub get
```

### Authentication

Authenticated commands resolve a token in this order:

1. `~/.dart_slack/credentials.json`, written by `dart_slack login`.
2. The `SLACK_TOKEN` environment variable — read from the process
   environment or a `.env` file in the current directory, the same way
   the OAuth secrets (`SLACK_CLIENT_ID`, etc.) are resolved.

The environment fallback lets the CLI run non-interactively — in CI,
containers, or agent workspaces — where a token is injected rather than
obtained through an interactive login. A token from the credentials file
always wins over the environment.

```sh
export SLACK_TOKEN=xoxp-…           # or add SLACK_TOKEN=xoxp-… to .env
dart run bin/dart_slack.dart channels   # no `login` step required
```

### Commands

```sh
# Authenticate
dart run bin/dart_slack.dart login

# Validate the current token (exits non-zero and prints a JSON error on failure)
dart run bin/dart_slack.dart auth test

# List channels
dart run bin/dart_slack.dart channels

# Show channel details
dart run bin/dart_slack.dart info -c <channel-id>

# List channel members
dart run bin/dart_slack.dart members -c <channel-id>

# Show recent messages
dart run bin/dart_slack.dart history -c <channel-id> -l 20

# Show thread replies
dart run bin/dart_slack.dart thread -c <channel-id> --ts <thread_ts>

# Send a message
dart run bin/dart_slack.dart send -c <channel-id> -t "Hello from the CLI"

# Reply to a thread
dart run bin/dart_slack.dart reply -c <channel-id> -r <thread_ts> -t "Thread reply"

# Edit a message
dart run bin/dart_slack.dart edit -c <channel-id> --ts <message_ts> -t "Updated text"

# Delete a message
dart run bin/dart_slack.dart delete -c <channel-id> --ts <message_ts>

# Create a canvas from markdown (standalone)
dart run bin/dart_slack.dart canvas create --title "Plan" -m "# Heading\n- item"

# Create a canvas tabbed into a channel, reading content from a file
dart run bin/dart_slack.dart canvas create -c <channel-id> -f ./plan.md

# Read a canvas's markdown body to stdout (e.g. a huddle's notes canvas)
dart run bin/dart_slack.dart canvas read --canvas <canvas-id>

# Read a canvas and save it to a file
dart run bin/dart_slack.dart canvas read --canvas <canvas-id> -o ./notes.md

# Edit a canvas (replace | append | prepend)
dart run bin/dart_slack.dart canvas edit --canvas <canvas-id> --mode append -m "More notes"

# Delete a canvas
dart run bin/dart_slack.dart canvas delete --canvas <canvas-id>

# Send a DM
dart run bin/dart_slack.dart dm -u <user-id> -t "Hey there"

# List workspace users
dart run bin/dart_slack.dart users

# Look up a user profile
dart run bin/dart_slack.dart whois -u <user-id>

# Set your custom status (expires automatically after 6 hours)
dart run bin/dart_slack.dart status set -t "Working on a task" -e ":gear:" -x 6h

# Clear your custom status
dart run bin/dart_slack.dart status clear

# Watch a channel (poll-based, uses user token)
dart run bin/dart_slack.dart watch -c <channel-id> -i 5 -n 10

# Stream a channel in real time (Socket Mode, uses app-level token)
dart run bin/dart_slack.dart stream -c <channel-id>

# Log out
dart run bin/dart_slack.dart logout
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
