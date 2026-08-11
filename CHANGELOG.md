## Unreleased

### Breaking

- OAuth flow now validates the `state` parameter (CSRF protection). Callbacks without a valid state are rejected.
- HTML characters in OAuth callback responses are now escaped.

### Added

- `send`, `reply`, and `dm` accept a `--file <path>` option to attach a local
  file to the posted message (with `--text` as the accompanying comment).
  Backed by `Slack.uploadFile()`, which drives Slack's current (non-deprecated)
  three-step external upload flow: `SlackApiClient.getUploadUrlExternal()`,
  `uploadFileBytes()`, and `completeUploadExternal()`. Adds the `files:write`
  OAuth scope.
- `history`, `thread`, and `watch` now show a `[attachment: <name>, ...]`
  indicator when a message carries files, via `SlackMessage.attachmentSuffix`.
  Previously an inbound attachment (screenshot, spec, log export) was silently
  dropped from the printed transcript even though `SlackMessage.files` already
  parsed it.
- `canvas read` command to fetch a canvas's markdown body. Slack has no
  `canvases.get` method, so the content is read by looking up the canvas's
  backing file with `files.info` and downloading its `url_private_download`
  body. Prints to stdout or writes to a file with `--output`. Backed by
  `Slack.readCanvas()`, `SlackApiClient.filesInfo()`, and
  `SlackApiClient.downloadFile()`. Adds the `canvases:read` and `files:read`
  OAuth scopes. Enables reading a huddle's notes canvas; note that Slack
  exposes no API for huddle *audio* transcripts.
- `status` command (`status set` / `status clear`) wrapping `users.profile.set`:
  set or clear the authenticated user's custom status with `--text`, `--emoji`,
  and `--expires-in` (a stale-status safety net mapped to `status_expiration`).
  Requires a user token with the `users.profile:write` scope (now requested by
  `login`); bot tokens get a descriptive `not_allowed_token_type` error.
- `Slack.setStatus()` / `Slack.clearStatus()` facade methods and
  `SlackApiClient.usersProfileSet()`.
- Authenticated commands fall back to the `SLACK_TOKEN` environment variable (read from the process environment or a `.env` file, like the OAuth secrets) when no `~/.dart_slack/credentials.json` is present, so the CLI works in non-interactive contexts (CI, containers, agent workspaces) without an interactive `login`.
- `Slack` facade with typed return values (`SlackMessage`, `SlackChannel`).
- `Slack.fromStore()` factory for creating an instance from saved credentials.
- CSRF protection via OAuth `state` parameter.
- HTML escaping in OAuth callback server responses.
- CLI commands: `history`, `thread`, `info`, `members`, `users`, `whois`, `edit`, `delete`.
- `canvas` command group (`create`, `edit`, `delete`) for Slack canvases, backed by `Slack.createCanvas`/`editCanvas`/`deleteCanvas` and the `canvases.create`/`canvases.edit`/`canvases.delete` API methods. `create` accepts inline `--content` or a `--file`, an optional `--title`, and an optional `--channel` to tab the canvas into a channel; `edit` supports `replace`/`append`/`prepend` modes. Adds the `canvases:write` OAuth scope.
- `watch` command for poll-based channel monitoring using a user token.
- `stream` command for real-time channel streaming via Socket Mode (`xapp-*` token).
- `SocketModeClient` library for WebSocket-based Socket Mode connections with automatic reconnection.
- Tests for `OAuthFlow`, `SlackApp`, `AuthenticatedCommand`, `ChannelsCommand`, `SocketModeClient`, `SocketModeEvent`, and `StreamCommand`.

### Changed

- `send`, `reply`, and `dm` now surface the posted message's `ts` on the
  success line (e.g. `Reply sent to thread <root> in <channel> (ts: <ts>).`).
  The `ts` was already fetched and modeled — it was just discarded before
  printing — so a coworker can now capture the reply's own `ts` for
  thread-affinity routing (`dw conversation record-reply -m <ts>`).
- `history` and `thread` now prefix each message line with its `ts`
  (`[<ts>] <user> text`), giving a machine-parseable timestamp column.
- `thread` now always echoes the root message first, then prints
  `(no replies yet)` plus a `dart_slack history -c <channel>` pointer when a
  thread has no replies (previously it printed a bare `No replies found.` with
  no root context, leaving thin-wake agents context-less).

- `OAuthFlow.execute()` now uses `return await` so errors from token exchange propagate through `try/finally` correctly.

### Changed

- GitHub Actions: upgraded `actions/checkout` to v4, pinned Dart SDK to `3.10.0`, added `permissions: read-all`, gated `semantic-pull-request` on PR events only, added `bin/**` to path triggers.
- Removed deprecated `enable-beta-ecosystems` from Dependabot config.

### Removed

- Removed the pub.dev update check and the `update` command. `dart_slack` is
  not published to pub.dev (it is distributed via GitHub + tool provisioning),
  so `pub_updater.getLatestVersion('dart_slack')` always 404'd: the
  post-command auto-check logged `Failed to check for updates.` to stderr on
  every invocation, and `dart_slack update` could never succeed. Dropped the
  `_checkForUpdates()` call, the `update` command, and the `pub_updater`
  dependency.

### Fixed

- `send`, `reply`, `dm`, and `edit` now normalize `--text` before they build
  the Slack API request (#35). A plain double-quoted shell string does not
  interpret backslash escapes, so `-t "line1\nline2"` used to reach Slack as
  the literal characters `\` and `n` and rendered as broken text instead of a
  line break. The literal `\n`, `\r\n`, `\r`, and `\t` sequences now become
  real control characters, `\r\n` and lone `\r` line endings become `\n`, and
  stray non-printable control bytes (C0 and DEL) are stripped while newline
  and tab are kept. Write `\\n` to keep a literal backslash-n. Text that
  already holds real newlines, real tabs, and printable characters is
  unchanged byte-for-byte.
- `info` reported `Members: 0` for channels that demonstrably have members,
  contradicting `members` run against the same channel (#27).
  `conversations.info`'s `num_members` field is frequently stale or
  unpopulated; `info` now counts members by paginating
  `conversations.members`, the same call `members` uses.
- Auth failures (`invalid_auth`, `token_revoked`, etc.) now also emit a
  machine-readable `{"ok": false, "error": "<code>"}` JSON line on stderr
  alongside the human-readable message, so "exit 0 = sent" style checks can
  branch on the error code instead of regex-matching text. Network failures
  emit `{"ok": false, "error": "network_error"}` the same way. Non-zero exit
  on these failures was already in place via `AuthenticatedCommand`'s shared
  error handling (#23).
- Added `auth test`, a first-class `auth.test` wrapper that validates the
  current token and exits non-zero on failure, so a pre-flight health check
  no longer has to piggyback on an unrelated command like `channels` (#23).
  Backed by `Slack.authTest()`, `SlackApiClient.authTest()`, and the new
  `SlackAuthIdentity` model.

## 0.1.0

- Initial release.
