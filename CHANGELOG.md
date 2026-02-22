## Unreleased

### Breaking

- OAuth flow now validates the `state` parameter (CSRF protection). Callbacks without a valid state are rejected.
- HTML characters in OAuth callback responses are now escaped.

### Added

- `Slack` facade with typed return values (`SlackMessage`, `SlackChannel`).
- `Slack.fromStore()` factory for creating an instance from saved credentials.
- CSRF protection via OAuth `state` parameter.
- HTML escaping in OAuth callback server responses.
- Tests for `OAuthFlow`, `SlackApp`, `AuthenticatedCommand`, and `ChannelsCommand`.

### Fixed

- `OAuthFlow.execute()` now uses `return await` so errors from token exchange propagate through `try/finally` correctly.

### Changed

- GitHub Actions: upgraded `actions/checkout` to v4, pinned Dart SDK to `3.10.0`, added `permissions: read-all`, gated `semantic-pull-request` on PR events only, added `bin/**` to path triggers.
- Removed deprecated `enable-beta-ecosystems` from Dependabot config.

## 0.1.0

- Initial release.
