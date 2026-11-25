import 'package:dart_slack/src/rich_message/rich_message_validator.dart';

/// The part of a `chat.postMessage` body that a card decides.
///
/// The command adds `channel` and `thread_ts`.
class SlackCardPayload {
  /// Creates a [SlackCardPayload].
  const new({required this.text, required this.blocks});

  /// The top-level `text`: the push notification and screen reader text.
  final String text;

  /// The Block Kit blocks.
  final List<Map<String, dynamic>> blocks;

  /// The payload in the same form as the backend renderer output and the
  /// golden files. `unfurl_links` is `false`, or the link preview repeats
  /// the card.
  Map<String, dynamic> toJson() => {
    'text': text,
    'unfurl_links': false,
    'blocks': blocks,
  };
}

/// Escapes the three characters that Slack mrkdwn treats as control
/// characters.
///
/// Without this, `<!channel>` in a value pings a whole channel.
String escapeSlackMrkdwn(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// Block Kit's limit for a `section` block's `text`.
const slackSectionTextMaxChars = 3000;

/// Block Kit's limit for one item of a `section` block's `fields`.
const slackSectionFieldMaxChars = 2000;

/// Refuses [text] when it is longer than [max] code points.
///
/// Escaping runs after validation and can make a value longer (`&` becomes
/// `&amp;`). A schema-valid card can therefore exceed a Block Kit limit, and
/// Slack then refuses the whole post with `invalid_blocks`. This refuses it
/// before any request and names [field]. It is the same check, limits and
/// error text as `fitSlack` in the backend renderer.
String _fitSlack(String text, int max, String field) {
  final length = text.runes.length;
  if (length > max) {
    throw RichMessageValidationError(
      field,
      'the Slack text is $length characters after escaping; the maximum is '
      '$max. Shorten it, or put detail behind a link.',
    );
  }
  return text;
}

Map<String, dynamic> _mrkdwn(String text) => {'type': 'mrkdwn', 'text': text};

Map<String, dynamic> _plainText(String text) => {
  'type': 'plain_text',
  'text': text,
};

/// Renders a RichMessage as Slack Block Kit, phase 1.
///
/// The rules are the same as the backend renderer
/// (`backend/convex/convex/rich_message/render_slack.ts` in
/// WAMF/WAAF_DigitalWorkforce), and the golden tests prove it:
///
/// * `fallbackText` is the top-level `text`.
/// * `title` is a `header` block, plain text.
/// * `summary` is the `section` text, mrkdwn. `fields` are the same
///   section's `fields`, as `*Label*\nvalue`.
/// * `status` is a `context` line `Status: <label>`, because blocks have no
///   colour badge. `context` follows it in the same `context` block.
/// * `links` are an `actions` block of URL buttons. The first one is the
///   primary button.
/// * `actions` and `choice` are refused (phase 2).
/// * After escaping, the `summary` text may have at most
///   [slackSectionTextMaxChars] code points, and each field text at most
///   [slackSectionFieldMaxChars]. A longer one is refused.
///
/// Throws a [RichMessageValidationError] when [input] breaks the schema, or
/// when a text is too long for Slack after escaping.
SlackCardPayload renderSlack(Object? input) {
  final message = validateRichMessage(input);
  assertStaticRichMessage(message);

  return SlackCardPayload(
    text: message['fallbackText'] as String,
    blocks: [
      {'type': 'header', 'text': _plainText(message['title'] as String)},
      ?_section(message),
      ?_context(message),
      ?_actions(message),
    ],
  );
}

/// `summary` and `fields` in one `section` block, or `null` for neither.
Map<String, dynamic>? _section(Map<String, dynamic> message) {
  final summary = message['summary'] as String?;
  final fields =
      (message['fields'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  if (summary == null && fields.isEmpty) return null;
  return {
    'type': 'section',
    if (summary != null)
      'text': _mrkdwn(
        _fitSlack(
          escapeSlackMrkdwn(summary),
          slackSectionTextMaxChars,
          'summary',
        ),
      ),
    if (fields.isNotEmpty)
      'fields': [
        for (final (index, field) in fields.indexed)
          _mrkdwn(
            _fitSlack(
              '*${escapeSlackMrkdwn(field['label'] as String)}*\n'
                  '${escapeSlackMrkdwn(field['value'] as String)}',
              slackSectionFieldMaxChars,
              'fields[$index].value',
            ),
          ),
      ],
  };
}

/// `status` and `context` in one `context` block, or `null` for neither.
Map<String, dynamic>? _context(Map<String, dynamic> message) {
  final status = message['status'] as Map<String, dynamic>?;
  final context = message['context'] as String?;
  if (status == null && context == null) return null;
  return {
    'type': 'context',
    'elements': [
      if (status != null)
        _mrkdwn('Status: ${escapeSlackMrkdwn(status['label'] as String)}'),
      if (context != null) _mrkdwn(escapeSlackMrkdwn(context)),
    ],
  };
}

/// `links` as an `actions` block of URL buttons, or `null` for none. The
/// first button is the primary one.
Map<String, dynamic>? _actions(Map<String, dynamic> message) {
  final links =
      (message['links'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  if (links.isEmpty) return null;
  return {
    'type': 'actions',
    'elements': [
      for (final (index, link) in links.indexed)
        {
          'type': 'button',
          if (index == 0) 'style': 'primary',
          'text': _plainText(link['label'] as String),
          'url': link['url'],
        },
    ],
  };
}
