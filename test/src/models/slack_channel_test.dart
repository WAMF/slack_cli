import 'package:slackcli/src/models/slack_channel.dart';
import 'package:test/test.dart';

void main() {
  group('SlackChannel', () {
    test('fromJson parses a public channel', () {
      final channel = SlackChannel.fromJson({
        'id': 'C123',
        'name': 'general',
        'is_private': false,
      });

      expect(channel.id, equals('C123'));
      expect(channel.name, equals('general'));
      expect(channel.isPrivate, isFalse);
    });

    test('fromJson parses a private channel', () {
      final channel = SlackChannel.fromJson({
        'id': 'G456',
        'name': 'secret',
        'is_private': true,
      });

      expect(channel.id, equals('G456'));
      expect(channel.name, equals('secret'));
      expect(channel.isPrivate, isTrue);
    });

    test('fromJson defaults isPrivate to false when missing', () {
      final channel = SlackChannel.fromJson({
        'id': 'C789',
        'name': 'open',
      });

      expect(channel.isPrivate, isFalse);
    });
  });
}
