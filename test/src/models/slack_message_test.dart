import 'package:dart_slack/src/models/slack_message.dart';
import 'package:test/test.dart';

void main() {
  group('SlackMessage', () {
    test('fromJson parses a postMessage response', () {
      final message = SlackMessage.fromJson(const {
        'ok': true,
        'channel': 'C123',
        'ts': '1234567890.123456',
        'message': {
          'text': 'Hello',
          'user': 'U123',
          'ts': '1234567890.123456',
        },
      });

      expect(message.channel, equals('C123'));
      expect(message.ts, equals('1234567890.123456'));
      expect(message.text, equals('Hello'));
    });

    test('fromJson defaults text to empty when message is null', () {
      final message = SlackMessage.fromJson(const {
        'ok': true,
        'channel': 'C123',
        'ts': '1234567890.123456',
      });

      expect(message.text, isEmpty);
    });

    test('fromHistory parses a complete history message', () {
      final message = SlackMessage.fromHistory(
        channel: 'C123',
        json: const {
          'ts': '1512085950.000216',
          'text': 'Hello world',
          'user': 'U456',
          'thread_ts': '1512085950.000216',
          'reply_count': 3,
        },
      );

      expect(message.channel, equals('C123'));
      expect(message.ts, equals('1512085950.000216'));
      expect(message.text, equals('Hello world'));
      expect(message.user, equals('U456'));
      expect(message.threadTs, equals('1512085950.000216'));
      expect(message.replyCount, equals(3));
    });

    test('fromHistory handles missing optional fields', () {
      final message = SlackMessage.fromHistory(
        channel: 'C123',
        json: const {
          'ts': '1512085951.000300',
          'text': 'Simple message',
        },
      );

      expect(message.user, isNull);
      expect(message.threadTs, isNull);
      expect(message.replyCount, isNull);
    });

    test('fromHistory parses a thread reply', () {
      final message = SlackMessage.fromHistory(
        channel: 'C123',
        json: const {
          'ts': '1512085951.000300',
          'text': 'A reply',
          'user': 'U789',
          'thread_ts': '1512085950.000216',
        },
      );

      expect(message.threadTs, equals('1512085950.000216'));
      expect(message.replyCount, isNull);
    });
  });
}
