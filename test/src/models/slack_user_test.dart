import 'package:dart_slack/src/models/slack_user.dart';
import 'package:test/test.dart';

void main() {
  group('SlackUser', () {
    test('fromJson parses a complete user object', () {
      final user = SlackUser.fromJson(const {
        'id': 'U123',
        'name': 'johndoe',
        'real_name': 'John Doe',
        'is_bot': false,
        'deleted': false,
        'profile': {
          'display_name': 'John',
          'email': 'john@example.com',
          'image_48': 'https://example.com/avatar.png',
        },
      });

      expect(user.id, equals('U123'));
      expect(user.name, equals('johndoe'));
      expect(user.realName, equals('John Doe'));
      expect(user.displayName, equals('John'));
      expect(user.isBot, isFalse);
      expect(user.isDeleted, isFalse);
      expect(user.email, equals('john@example.com'));
      expect(user.imageUrl, equals('https://example.com/avatar.png'));
    });

    test('fromJson defaults optional fields when missing', () {
      final user = SlackUser.fromJson(const {
        'id': 'U456',
      });

      expect(user.id, equals('U456'));
      expect(user.name, isEmpty);
      expect(user.realName, isEmpty);
      expect(user.displayName, isEmpty);
      expect(user.isBot, isFalse);
      expect(user.isDeleted, isFalse);
      expect(user.email, isNull);
      expect(user.imageUrl, isNull);
    });

    test('fromJson parses a bot user', () {
      final user = SlackUser.fromJson(const {
        'id': 'U789',
        'name': 'slackbot',
        'real_name': 'Slackbot',
        'is_bot': true,
        'deleted': false,
        'profile': {
          'display_name': 'Slackbot',
        },
      });

      expect(user.isBot, isTrue);
      expect(user.email, isNull);
    });
  });
}
