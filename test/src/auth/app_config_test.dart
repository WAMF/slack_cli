import 'package:dart_slack/src/auth/app_config.dart';
import 'package:test/test.dart';

void main() {
  group('AppConfig', () {
    const appToken = 'xapp-1-A0123-test-token';

    test('fromJson parses token', () {
      final config = AppConfig.fromJson({'app_token': appToken});
      expect(config.appToken, equals(appToken));
    });

    test('toJson produces expected map', () {
      const config = AppConfig(appToken: appToken);
      expect(config.toJson(), {'app_token': appToken});
    });

    test('round-trip fromJson(toJson) preserves value', () {
      const original = AppConfig(appToken: appToken);
      final restored = AppConfig.fromJson(original.toJson());
      expect(restored.appToken, equals(original.appToken));
    });
  });
}
