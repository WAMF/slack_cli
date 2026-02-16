import 'package:slackcli/src/models/slack_message.dart';
import 'package:test/test.dart';

void main() {
  group('SlackMessage', () {
    test('fromJson parses a postMessage response', () {
      final message = SlackMessage.fromJson({
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
      final message = SlackMessage.fromJson({
        'ok': true,
        'channel': 'C123',
        'ts': '1234567890.123456',
      });

      expect(message.text, isEmpty);
    });
  });
}
