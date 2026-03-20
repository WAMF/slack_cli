import 'package:dart_slack/src/models/slack_reaction.dart';
import 'package:test/test.dart';

void main() {
  group('SlackReaction', () {
    test('fromJson parses name and count', () {
      final reaction = SlackReaction.fromJson(const {
        'name': 'thumbsup',
        'count': 5,
        'users': ['U1', 'U2'],
      });

      expect(reaction.name, equals('thumbsup'));
      expect(reaction.count, equals(5));
    });
  });
}
