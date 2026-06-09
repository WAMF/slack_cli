## Unreleased

### Breaking

- OAuth flow now validates the `state` parameter (CSRF protection). Callbacks without a valid state are rejected.
- HTML characters in OAuth callback responses are now escaped.

### Added

- Authenticated commands fall back to the `SLACK_TOKEN` environment variable (read from the process environment or a `.env` file, like the OAuth secrets) when no `~/.dart_slack/credentials.json` is present, so the CLI works in non-interactive contexts (CI, containers, agent workspaces) without an interactive `login`.
- `Slack` facade with typed return values (`SlackMessage`, `SlackChannel`).
- `Slack.fromStore()` factory for creating an instance from saved credentials.
- CSRF protection via OAuth `state` parameter.
- HTML escaping in OAuth callback server responses.
- CLI commands: `history`, `thread`, `info`, `members`, `users`, `whois`, `edit`, `delete`.
- `watch` command for poll-based channel monitoring using a user token.
- `stream` command for real-time channel streaming via Socket Mode (`xapp-*` token).
- `SocketModeClient` library for WebSocket-based Socket Mode connections with automatic reconnection.
- Tests for `OAuthFlow`, `SlackApp`, `AuthenticatedCommand`, `ChannelsCommand`, `SocketModeClient`, `SocketModeEvent`, and `StreamCommand`.

### Fixed

- `OAuthFlow.execute()` now uses `return await` so errors from token exchange propagate through `try/finally` correctly.

### Changed

- GitHub Actions: upgraded `actions/checkout` to v4, pinned Dart SDK to `3.10.0`, added `permissions: read-all`, gated `semantic-pull-request` on PR events only, added `bin/**` to path triggers.
- Removed deprecated `enable-beta-ecosystems` from Dependabot config.

## 0.1.0

- Initial release.
