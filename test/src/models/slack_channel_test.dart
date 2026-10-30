import 'package:dart_slack/src/models/slack_channel.dart';
import 'package:test/test.dart';

void main() {
  group('SlackChannel', () {
    test('fromJson parses a documented one-to-one DM without a name', () {
      // https://docs.slack.dev/reference/methods/conversations.info/
      final channel = SlackChannel.fromJson(const {
        'id': 'C012AB3CD',
        'created': 1507235627,
        'is_im': true,
        'is_org_shared': false,
        'user': 'U27FFLNF4',
        'last_read': '1513718191.000038',
        'latest': {
          'type': 'message',
          'user': 'U5R3PALPN',
          'text': 'Psssst!',
          'ts': '1513718191.000038',
        },
        'unread_count': 0,
        'unread_count_display': 0,
        'is_open': true,
        'locale': 'en-US',
        'priority': 0.043016851216706,
      });

      expect(channel.id, equals('C012AB3CD'));
      expect(channel.name, isEmpty);
      expect(channel.isIm, isTrue);
      expect(channel.userId, equals('U27FFLNF4'));
      expect(channel.isPrivate, isTrue);
      expect(channel.created, equals(1507235627));
    });

    test('fromJson parses a public channel', () {
      final channel = SlackChannel.fromJson(const {
        'id': 'C123',
        'name': 'general',
        'is_private': false,
      });

      expect(channel.id, equals('C123'));
      expect(channel.name, equals('general'));
      expect(channel.isPrivate, isFalse);
    });

    test('fromJson parses a private channel', () {
      final channel = SlackChannel.fromJson(const {
        'id': 'G456',
        'name': 'secret',
        'is_private': true,
      });

      expect(channel.id, equals('G456'));
      expect(channel.name, equals('secret'));
      expect(channel.isPrivate, isTrue);
    });

    test('fromJson defaults isPrivate to false when missing', () {
      final channel = SlackChannel.fromJson(const {
        'id': 'C789',
        'name': 'open',
      });

      expect(channel.isPrivate, isFalse);
    });

    test('fromJson parses topic and purpose from nested maps', () {
      final channel = SlackChannel.fromJson(const {
        'id': 'C123',
        'name': 'general',
        'is_private': false,
        'topic': {'value': 'Company-wide announcements'},
        'purpose': {'value': 'General discussion'},
        'num_members': 42,
        'is_archived': false,
        'created': 1449252889,
      });

      expect(channel.topic, equals('Company-wide announcements'));
      expect(channel.purpose, equals('General discussion'));
      expect(channel.memberCount, equals(42));
      expect(channel.isArchived, isFalse);
      expect(channel.created, equals(1449252889));
    });

    test('fromJson defaults new fields when missing', () {
      final channel = SlackChannel.fromJson(const {
        'id': 'C789',
        'name': 'minimal',
      });

      expect(channel.topic, isEmpty);
      expect(channel.purpose, isEmpty);
      expect(channel.memberCount, isZero);
      expect(channel.isArchived, isFalse);
      expect(channel.created, isZero);
      expect(channel.isIm, isFalse);
      expect(channel.userId, isNull);
    });
  });
}
