import 'package:dart_slack/src/socket_mode/socket_mode_event.dart';
import 'package:test/test.dart';

void main() {
  group('SocketModeEvent', () {
    group('fromJson', () {
      test('parses all fields', () {
        final event = SocketModeEvent.fromJson({
          'type': 'message',
          'channel': 'C123',
          'user': 'U456',
          'text': 'Hello world',
          'ts': '1234567890.123456',
          'thread_ts': '1234567880.000000',
          'reply_count': 5,
        });

        expect(event.type, equals('message'));
        expect(event.channel, equals('C123'));
        expect(event.user, equals('U456'));
        expect(event.text, equals('Hello world'));
        expect(event.ts, equals('1234567890.123456'));
        expect(event.threadTs, equals('1234567880.000000'));
        expect(event.replyCount, equals(5));
      });

      test('handles missing optional fields', () {
        final event = SocketModeEvent.fromJson({
          'type': 'message',
          'channel': 'C123',
          'user': 'U456',
          'text': 'Hello',
          'ts': '1.0',
        });

        expect(event.threadTs, isNull);
        expect(event.replyCount, isNull);
      });

      test('defaults missing required fields to empty string', () {
        final event = SocketModeEvent.fromJson(<String, dynamic>{});

        expect(event.type, isEmpty);
        expect(event.channel, isEmpty);
        expect(event.user, isEmpty);
        expect(event.text, isEmpty);
        expect(event.ts, isEmpty);
      });
    });
  });
}
