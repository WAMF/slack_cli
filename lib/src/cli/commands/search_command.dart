import 'package:dart_slack/src/cli/commands/authenticated_command.dart';
import 'package:dart_slack/src/slack.dart';
import 'package:mason_logger/mason_logger.dart';

/// The largest snippet printed for one match. Search matches can be long and
/// multi-line; the full message is still readable with `history` or `thread`.
const int _snippetLength = 200;

/// Matches a Slack conversation ID: a channel (`C...`), a private group
/// (`G...`), or a direct message (`D...`).
final RegExp _conversationId = RegExp(r'^[CDG][A-Z0-9]{2,}$');

/// `dart_slack search --query <text> [--limit <n>] [--channel <id-or-name>]`
///
/// Searches every conversation the authenticated user can see. The query
/// accepts Slack's own search modifiers, for example `in:#incidents`,
/// `from:@lee`, `before:2026-08-01`.
///
/// Requires a user token with the `search:read` scope. That scope was added
/// after the first release, so a token stored by an earlier `login` does not
/// carry it. Slack answers `missing_scope` in that case and the shared
/// [AuthenticatedCommand] handler prints the `dart_slack login` hint.
class SearchCommand extends AuthenticatedCommand {
  /// Creates a [SearchCommand].
  SearchCommand({
    required super.logger,
    super.credentialsStore,
    super.httpClient,
  }) {
    argParser
      ..addOption(
        'query',
        abbr: 'q',
        help:
            'The text to search for. Slack search modifiers such as '
            '"in:#channel", "from:@user", "before:2026-08-01" are accepted.',
      )
      ..addOption(
        'limit',
        abbr: 'l',
        help: 'Maximum number of matches to show.',
        defaultsTo: '20',
      )
      ..addOption(
        'channel',
        abbr: 'c',
        help:
            'Restrict the search to one channel, by ID or by name. '
            'Adds the matching "in:" modifier to the query.',
      );
  }

  @override
  String get description => 'Search messages across channels.';

  @override
  String get name => 'search';

  @override
  Future<int> runAuthenticated(Slack slack) async {
    // Read as nullable and check it here rather than declaring the option
    // `mandatory: true`. A mandatory option throws an ArgumentError out of
    // `argResults[...]`, which reaches the user as an unhandled exception
    // and a Dart stack trace instead of the usage text.
    final query = (argResults!['query'] as String?)?.trim();
    if (query == null || query.isEmpty) {
      return _usageError(
        'Missing --query. Give the text to search for, '
        'for example: search -q "deploy failed".',
      );
    }

    final rawLimit = argResults!['limit'] as String;
    final limit = int.tryParse(rawLimit);
    if (limit == null || limit <= 0) {
      return _usageError(
        'Invalid --limit value: "$rawLimit". Use a positive integer.',
      );
    }

    final rawChannel = argResults!['channel'] as String?;
    if (rawChannel != null && rawChannel.trim().isEmpty) {
      return _usageError('Invalid --channel value: it must not be empty.');
    }

    final page = await slack.searchMessages(
      query: buildQuery(query: query, channel: rawChannel),
      limit: limit,
    );

    if (page.items.isEmpty) {
      logger.info('No matching messages found.');
      return ExitCode.success.code;
    }

    for (final match in page.items) {
      logger.info(
        '[${match.channelLabel}] [${match.ts}] '
        '<${match.authorLabel}> ${snippet(match.text)}',
      );
    }

    if (page.hasMore) {
      logger.info('(more results available)');
    }

    return ExitCode.success.code;
  }

  /// Combines the user's [query] with the `in:` modifier for [channel].
  ///
  /// The user's query is always kept: the modifier is appended to it, never
  /// substituted for it, so `-q "deploy failed" -c C123` still searches for
  /// "deploy failed". A channel ID becomes `in:<#C123>`, Slack's encoded
  /// channel-link form; anything else is treated as a name and becomes
  /// `in:#name`, with a `#` the user typed themselves accepted either way.
  static String buildQuery({required String query, String? channel}) {
    final name = channel?.trim();
    if (name == null || name.isEmpty) return query;
    if (_conversationId.hasMatch(name)) return '$query in:<#$name>';
    return '$query in:#${name.startsWith('#') ? name.substring(1) : name}';
  }

  /// Reduces [text] to one printable line.
  ///
  /// Every run of whitespace — including the newlines of a multi-line
  /// message — collapses to a single space, so one match stays on one line.
  /// Text longer than [_snippetLength] is cut and marked with an ellipsis.
  static String snippet(String text) {
    final collapsed = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.length <= _snippetLength) return collapsed;
    return '${collapsed.substring(0, _snippetLength)}…';
  }

  /// Prints [message] with the command usage and returns the usage exit code.
  int _usageError(String message) {
    logger
      ..err(message)
      ..info('')
      ..info(usage);
    return ExitCode.usage.code;
  }
}
