import 'package:slackcli/src/auth/credentials.dart';
import 'package:test/test.dart';

void main() {
  group('Credentials', () {
    const accessToken = 'xoxp-test-token';
    const teamId = 'T12345';
    const teamName = 'Test Team';
    const userId = 'U12345';

    test('fromJson parses a complete JSON map', () {
      final json = <String, dynamic>{
        'access_token': accessToken,
        'team_id': teamId,
        'team_name': teamName,
        'user_id': userId,
      };

      final credentials = Credentials.fromJson(json);

      expect(credentials.accessToken, equals(accessToken));
      expect(credentials.teamId, equals(teamId));
      expect(credentials.teamName, equals(teamName));
      expect(credentials.userId, equals(userId));
    });

    test('fromJson handles missing optional userId', () {
      final json = <String, dynamic>{
        'access_token': accessToken,
        'team_id': teamId,
        'team_name': teamName,
      };

      final credentials = Credentials.fromJson(json);

      expect(credentials.userId, isNull);
    });

    test('toJson produces the expected map', () {
      const credentials = Credentials(
        accessToken: accessToken,
        teamId: teamId,
        teamName: teamName,
        userId: userId,
      );

      expect(credentials.toJson(), {
        'access_token': accessToken,
        'team_id': teamId,
        'team_name': teamName,
        'user_id': userId,
      });
    });

    test('toJson omits userId when null', () {
      const credentials = Credentials(
        accessToken: accessToken,
        teamId: teamId,
        teamName: teamName,
      );

      expect(credentials.toJson(), isNot(contains('user_id')));
    });

    test('round-trip fromJson(toJson) preserves all fields', () {
      const original = Credentials(
        accessToken: accessToken,
        teamId: teamId,
        teamName: teamName,
        userId: userId,
      );

      final restored = Credentials.fromJson(original.toJson());

      expect(restored.accessToken, equals(original.accessToken));
      expect(restored.teamId, equals(original.teamId));
      expect(restored.teamName, equals(original.teamName));
      expect(restored.userId, equals(original.userId));
    });
  });
}
