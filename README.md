# slackcli

[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]
[![License: MIT][license_badge]][license_link]

A Dart CLI for posting messages, replying to threads, and sending DMs in Slack.

## Prerequisites

- Dart SDK `^3.10.0` (included with Flutter 3.41+)
- A Slack app with the required OAuth scopes (see [Slack App Setup](#slack-app-setup))

## Slack App Setup

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

## Getting Started

```sh
dart pub get
```

## Usage

### Authenticate

```sh
dart run bin/slackcli.dart login
```

Opens your browser for Slack OAuth authorization. Credentials are stored in `~/.slackcli/credentials.json`.

### List channels

```sh
dart run bin/slackcli.dart channels
```

### Send a message

```sh
dart run bin/slackcli.dart send -c <channel-id> -t "Hello from the CLI"
```

### Reply to a thread

```sh
dart run bin/slackcli.dart reply -c <channel-id> -r <thread_ts> -t "Thread reply"
```

### Send a DM

```sh
dart run bin/slackcli.dart dm -u <user-id> -t "Hey there"
```

### Log out

```sh
dart run bin/slackcli.dart logout
```

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
