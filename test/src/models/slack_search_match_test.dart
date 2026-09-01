import 'package:dart_slack/src/models/slack_search_match.dart';
import 'package:test/test.dart';

void main() {
  group('SlackSearchMatch', () {
    test('fromJson parses a search.messages match', () {
      final match = SlackSearchMatch.fromJson(const {
        'type': 'message',
        'ts': '1234567890.123456',
        'text': 'deploy failed on staging',
        'user': 'U123',
        'username': 'lee',
        'channel': {'id': 'C123', 'name': 'incidents'},
        'permalink': 'https://example.slack.com/archives/C123/p1234567890',
      });

      expect(match.ts, equals('1234567890.123456'));
      expect(match.text, equals('deploy failed on staging'));
      expect(match.user, equals('U123'));
      expect(match.username, equals('lee'));
      expect(match.channelId, equals('C123'));
      expect(match.channelName, equals('incidents'));
    });

    test('fromJson defaults text to empty when Slack omits it', () {
      final match = SlackSearchMatch.fromJson(const {'ts': '1.0'});

      expect(match.text, isEmpty);
    });

    test('fromJson tolerates a missing channel object', () {
      final match = SlackSearchMatch.fromJson(const {
        'ts': '1.0',
        'text': 'orphan',
      });

      expect(match.channelId, isNull);
      expect(match.channelName, isNull);
    });

    group('channelLabel', () {
      test('prefers the channel name with a # prefix', () {
        const match = SlackSearchMatch(
          ts: '1.0',
          text: 'hi',
          channelId: 'C123',
          channelName: 'incidents',
        );

        expect(match.channelLabel, equals('#incidents'));
      });

      test('falls back to the channel ID', () {
        const match = SlackSearchMatch(
          ts: '1.0',
          text: 'hi',
          channelId: 'C123',
        );

        expect(match.channelLabel, equals('C123'));
      });

      test('falls back to unknown when neither is present', () {
        const match = SlackSearchMatch(ts: '1.0', text: 'hi');

        expect(match.channelLabel, equals('unknown'));
      });

      test('treats an empty channel name as absent', () {
        const match = SlackSearchMatch(
          ts: '1.0',
          text: 'hi',
          channelId: 'C123',
          channelName: '',
        );

        expect(match.channelLabel, equals('C123'));
      });
    });

    group('authorLabel', () {
      test('prefers the display name', () {
        const match = SlackSearchMatch(
          ts: '1.0',
          text: 'hi',
          user: 'U123',
          username: 'lee',
        );

        expect(match.authorLabel, equals('lee'));
      });

      test('falls back to the user ID', () {
        const match = SlackSearchMatch(ts: '1.0', text: 'hi', user: 'U123');

        expect(match.authorLabel, equals('U123'));
      });

      test('falls back to unknown when neither is present', () {
        const match = SlackSearchMatch(ts: '1.0', text: 'hi');

        expect(match.authorLabel, equals('unknown'));
      });

      test('treats an empty username as absent', () {
        const match = SlackSearchMatch(
          ts: '1.0',
          text: 'hi',
          user: 'U123',
          username: '',
        );

        expect(match.authorLabel, equals('U123'));
      });
    });
  });
}
