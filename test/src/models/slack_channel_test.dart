import 'package:dart_slack/src/models/slack_channel.dart';
import 'package:test/test.dart';

void main() {
  group('SlackChannel', () {
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
    });
  });
}
