import 'dart:io';

import 'package:dart_slack/src/auth/app_config.dart';
import 'package:dart_slack/src/auth/app_config_store.dart';
import 'package:test/test.dart';

void main() {
  group('AppConfigStore', () {
    late Directory tempDir;
    late AppConfigStore store;

    const config = AppConfig(appToken: 'xapp-1-A0123-test-token');

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('slackcli_config_test_');
      store = AppConfigStore(configDirectory: tempDir);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('load returns null when no config file exists', () {
      expect(store.load(), isNull);
    });

    test('hasConfig returns false before save', () {
      expect(store.hasConfig, isFalse);
    });

    test('save creates file with correct content', () {
      store.save(config);

      final loaded = store.load();
      expect(loaded, isNotNull);
      expect(loaded!.appToken, equals(config.appToken));
    });

    test('hasConfig returns true after save', () {
      store.save(config);
      expect(store.hasConfig, isTrue);
    });

    test('delete removes the file', () {
      store.save(config);
      expect(store.delete(), isTrue);
      expect(store.hasConfig, isFalse);
    });

    test('delete returns false when no file exists', () {
      expect(store.delete(), isFalse);
    });

    test(
      'save sets file permissions to 600 on POSIX',
      () {
        store.save(config);

        final file = File('${tempDir.path}/config.json');
        final stat = file.statSync();
        final permissions = stat.mode & 0x1FF;
        expect(permissions, equals(0x180));
      },
      skip: !Platform.isMacOS && !Platform.isLinux
          ? 'File permissions only testable on POSIX'
          : null,
    );
  });
}
