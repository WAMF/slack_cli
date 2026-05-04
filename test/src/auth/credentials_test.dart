import 'package:dart_slack/src/auth/credentials.dart';
import 'package:test/test.dart';

void main() {
  group('Credentials', () {
    const accessToken = 'xoxp-test-token';
    const userId = 'U12345';

    test('fromJson parses a complete JSON map', () {
      final json = <String, dynamic>{
        'access_token': accessToken,
        'user_id': userId,
      };

      final credentials = Credentials.fromJson(json);

      expect(credentials.accessToken, equals(accessToken));
      expect(credentials.userId, equals(userId));
    });

    test('fromJson handles missing optional userId', () {
      final json = <String, dynamic>{
        'access_token': accessToken,
      };

      final credentials = Credentials.fromJson(json);

      expect(credentials.accessToken, equals(accessToken));
      expect(credentials.userId, isNull);
    });

    test('toJson produces the expected map', () {
      const credentials = Credentials(
        accessToken: accessToken,
        userId: userId,
      );

      expect(credentials.toJson(), {
        'access_token': accessToken,
        'user_id': userId,
      });
    });

    test('toJson omits userId when null', () {
      const credentials = Credentials(accessToken: accessToken);

      expect(credentials.toJson(), isNot(contains('user_id')));
    });

    test('round-trip fromJson(toJson) preserves all fields', () {
      const original = Credentials(
        accessToken: accessToken,
        userId: userId,
      );

      final restored = Credentials.fromJson(original.toJson());

      expect(restored.accessToken, equals(original.accessToken));
      expect(restored.userId, equals(original.userId));
    });
  });
}
