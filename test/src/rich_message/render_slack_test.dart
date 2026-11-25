import 'dart:convert';
import 'dart:io';

import 'package:dart_slack/src/rich_message/rich_message.dart';
import 'package:dart_slack/src/rich_message/rich_message_schema.g.dart';
import 'package:test/test.dart';

const _fixtures = 'test/fixtures/rich_message';

Object? _readJson(String name) =>
    jsonDecode(File('$_fixtures/$name').readAsStringSync());

Map<String, dynamic> _card([Map<String, dynamic> extra = const {}]) => {
  'fallbackText': 'F',
  'title': 'T',
  ...extra,
};

void main() {
  group('renderSlack golden', () {
    // The goldens are the backend renderer output, synced from
    // WAMF/WAAF_DigitalWorkforce by tool/sync_rich_message.dart. Equal JSON
    // here means the CLI posts the same card as the backend.
    for (final name in ['draft_proposed', 'all_fields']) {
      test('$name.json renders to $name.slack.json', () {
        final rendered = renderSlack(_readJson('$name.json')).toJson();
        expect(
          jsonDecode(jsonEncode(rendered)),
          equals(_readJson('$name.slack.json')),
        );
      });
    }

    test('the embedded schema is the synced schema, byte for byte', () {
      expect(
        richMessageSchemaJson,
        equals(File('$_fixtures/rich_message_schema.json').readAsStringSync()),
      );
    });
  });

  group('validateRichMessage shared invalid cases', () {
    final cases =
        ((_readJson('invalid_cases.json')! as Map<String, dynamic>)['cases']
                as List)
            .cast<Map<String, dynamic>>();

    test('the fixture holds cases', () => expect(cases, isNotEmpty));

    for (final item in cases) {
      test('${item['name']} names ${item['field']}', () {
        expect(
          () => renderSlack(item['message']),
          throwsA(
            isA<RichMessageValidationError>()
                .having((e) => e.field, 'field', item['field'])
                .having(
                  (e) => e.message,
                  'message',
                  startsWith('RichMessage.${item['field']}: '),
                ),
          ),
        );
      });
    }
  });

  group('validateRichMessage rules', () {
    RichMessageValidationError errorFor(Object? value) {
      try {
        validateRichMessage(value);
      } on RichMessageValidationError catch (e) {
        return e;
      }
      fail('expected a RichMessageValidationError');
    }

    test('reads the limits from the schema', () {
      final props = richMessageSchema['properties'] as Map<String, dynamic>;
      final max = (props['fallbackText'] as Map)['maxLength'] as int;
      expect(validateRichMessage(_card({'fallbackText': 'x' * max})), isMap);
      expect(
        errorFor(_card({'fallbackText': 'x' * (max + 1)})).problem,
        equals('is ${max + 1} characters; the maximum is $max'),
      );
    });

    test('counts Unicode code points, not UTF-16 units', () {
      // 140 emoji are 280 UTF-16 units but 140 code points.
      expect(validateRichMessage(_card({'fallbackText': '😀' * 140})), isMap);
      expect(
        errorFor(_card({'fallbackText': '😀' * 141})).field,
        'fallbackText',
      );
    });

    test('a root that is not an object names (root)', () {
      final error = errorFor(<dynamic>[]);
      expect(error.field, '(root)');
      expect(error.problem, 'must be an object, got array');
    });

    test('null is present but of the wrong type', () {
      final error = errorFor(_card({'summary': null}));
      expect(error.field, 'summary');
      expect(error.problem, 'must be a string, got null');
    });

    test('names the type of a wrong value', () {
      expect(errorFor(_card({'title': 3})).problem, contains('got number'));
      expect(errorFor(_card({'title': true})).problem, contains('got boolean'));
      expect(
        errorFor(_card({'fields': <String, dynamic>{}})).problem,
        contains('got object'),
      );
    });

    test('checks required fields in schema order', () {
      expect(errorFor(<String, dynamic>{}).field, 'fallbackText');
    });

    test('names the nested path of an unknown key', () {
      final error = errorFor(
        _card({
          'links': [
            {'label': 'a', 'url': 'https://a.example', 'colour': 'red'},
          ],
        }),
      );
      expect(error.field, 'links[0].colour');
      expect(error.problem, 'is not a RichMessage field');
    });

    test('accepts a phase 2 action in the model', () {
      expect(
        validateRichMessage(
          _card({
            'actions': [
              {'id': 'approve', 'label': 'Approve'},
            ],
          }),
        ),
        isMap,
      );
    });
  });

  group('renderSlack phase 1 is static', () {
    test('refuses actions', () {
      expect(
        () => renderSlack(
          _card({
            'actions': [
              {'id': 'approve', 'label': 'Approve'},
            ],
          }),
        ),
        throwsA(
          isA<RichMessageValidationError>().having(
            (e) => e.field,
            'field',
            'actions',
          ),
        ),
      );
    });

    test('refuses choice', () {
      expect(
        () => renderSlack(
          _card({
            'choice': {
              'id': 'pick',
              'placeholder': 'Pick',
              'options': [
                {'label': 'A', 'value': 'a'},
              ],
            },
          }),
        ),
        throwsA(
          isA<RichMessageValidationError>().having(
            (e) => e.field,
            'field',
            'choice',
          ),
        ),
      );
    });

    test('an empty actions list renders, as in the backend', () {
      expect(renderSlack(_card({'actions': <dynamic>[]})).blocks, hasLength(1));
    });
  });

  group('renderSlack blocks', () {
    test('a title-only card is one header block', () {
      final payload = renderSlack(_card()).toJson();
      expect(payload, {
        'text': 'F',
        'unfurl_links': false,
        'blocks': [
          {
            'type': 'header',
            'text': {'type': 'plain_text', 'text': 'T'},
          },
        ],
      });
    });

    test('fields without a summary give a section with fields only', () {
      final blocks = renderSlack(
        _card({
          'fields': [
            {'label': 'a<', 'value': '&b'},
          ],
        }),
      ).blocks;
      expect(blocks[1], {
        'type': 'section',
        'fields': [
          {'type': 'mrkdwn', 'text': '*a&lt;*\n&amp;b'},
        ],
      });
    });

    test('a summary without fields gives a section with text only', () {
      final blocks = renderSlack(_card({'summary': '<!channel>'})).blocks;
      expect(blocks[1], {
        'type': 'section',
        'text': {'type': 'mrkdwn', 'text': '&lt;!channel&gt;'},
      });
    });

    test('context without status is one context element', () {
      final blocks = renderSlack(_card({'context': 'a > b'})).blocks;
      expect(blocks[1], {
        'type': 'context',
        'elements': [
          {'type': 'mrkdwn', 'text': 'a &gt; b'},
        ],
      });
    });

    test('status without context is a Status line', () {
      final blocks = renderSlack(
        _card({
          'status': {'label': 'Blocked', 'tone': 'bad'},
        }),
      ).blocks;
      expect(blocks[1], {
        'type': 'context',
        'elements': [
          {'type': 'mrkdwn', 'text': 'Status: Blocked'},
        ],
      });
    });

    test('the title, fallback and button labels stay plain text', () {
      final payload = renderSlack(
        _card({
          'fallbackText': 'a & b',
          'title': '<T>',
          'links': [
            {'label': 'x & y', 'url': 'https://a.example/?a=1&b=2'},
          ],
        }),
      );
      expect(payload.text, 'a & b');
      expect(payload.blocks[0]['text'], {'type': 'plain_text', 'text': '<T>'});
      expect(payload.blocks[1], {
        'type': 'actions',
        'elements': [
          {
            'type': 'button',
            'style': 'primary',
            'text': {'type': 'plain_text', 'text': 'x & y'},
            'url': 'https://a.example/?a=1&b=2',
          },
        ],
      });
    });
  });

  // Port of the backend `fitSlack` check (WAAF_DigitalWorkforce PR #8629).
  // Escaping runs after validation and makes `&`, `<` and `>` longer, so a
  // schema-valid card can be too long for Block Kit after escaping.
  group('renderSlack escaped length', () {
    Matcher refuses(String field, int length, int max) => throwsA(
      isA<RichMessageValidationError>()
          .having((e) => e.field, 'field', field)
          .having(
            (e) => e.message,
            'message',
            'RichMessage.$field: the Slack text is $length characters after '
                'escaping; the maximum is $max. Shorten it, or put detail '
                'behind a link.',
          ),
    );

    String sectionText(SlackCardPayload payload) =>
        ((payload.blocks[1]['text'] as Map)['text']) as String;

    test('the limits are the Block Kit limits', () {
      expect(slackSectionTextMaxChars, 3000);
      expect(slackSectionFieldMaxChars, 2000);
    });

    test('refuses a schema-valid summary too long after escaping', () {
      final card = _card({'summary': '&' * 3000});
      expect(() => validateRichMessage(card), returnsNormally);
      expect(() => renderSlack(card), refuses('summary', 15000, 3000));
    });

    test('the review case: 2900 characters with 50 & is refused', () {
      final card = _card({'summary': '${'x' * 2850}${'&' * 50}'});
      expect(() => validateRichMessage(card), returnsNormally);
      expect(() => renderSlack(card), refuses('summary', 3100, 3000));
    });

    test('accepts a summary of exactly 3000 characters after escaping', () {
      final summary = '${'x' * 2995}&';
      final text = sectionText(renderSlack(_card({'summary': summary})));
      expect(text.runes.length, 3000);
      expect(text, endsWith('&amp;'));
    });

    test('refuses a summary of 3001 characters after escaping', () {
      final card = _card({'summary': '${'x' * 2996}&'});
      expect(() => renderSlack(card), refuses('summary', 3001, 3000));
    });

    test('counts code points, not UTF-16 units', () {
      // 3000 emoji are 6000 UTF-16 units but 3000 code points.
      final summary = '\u{1F600}' * 3000;
      final text = sectionText(renderSlack(_card({'summary': summary})));
      expect(text.runes.length, 3000);
    });

    test('refuses a field too long after escaping, naming its index', () {
      final card = _card({
        'fields': [
          {'label': 'Fine', 'value': 'ok'},
          {'label': 'Long', 'value': '<' * 1000},
        ],
      });
      expect(() => validateRichMessage(card), returnsNormally);
      // "*Long*\n" + 1000 x "&lt;" = 7 + 4000.
      expect(() => renderSlack(card), refuses('fields[1].value', 4007, 2000));
    });

    test('a field counts the label markup too', () {
      // "*L*\n" is 4 characters. 399 x "&amp;" is 1995, so one more
      // character in the value is exactly 2000, and two is 2001.
      Map<String, dynamic> withValue(String value) => _card({
        'fields': [
          {'label': 'L', 'value': value},
        ],
      });
      final fields =
          renderSlack(withValue('${'&' * 399}x')).blocks[1]['fields'] as List;
      expect(((fields.single as Map)['text'] as String).runes.length, 2000);
      expect(
        () => renderSlack(withValue('${'&' * 399}xx')),
        refuses('fields[0].value', 2001, 2000),
      );
    });
  });
}
