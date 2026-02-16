import 'dart:io';

import 'package:dart_slack/src/auth/credentials.dart';
import 'package:dart_slack/src/auth/credentials_store.dart';
import 'package:test/test.dart';

void main() {
  group('CredentialsStore', () {
    late Directory tempDir;
    late CredentialsStore store;

    const credentials = Credentials(
      accessToken: 'xoxp-test-token',
      teamId: 'T12345',
      teamName: 'Test Team',
      userId: 'U12345',
    );

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('slackcli_test_');
      store = CredentialsStore(configDirectory: tempDir);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('load returns null when no credentials file exists', () {
      expect(store.load(), isNull);
    });

    test('hasCredentials returns false before save', () {
      expect(store.hasCredentials, isFalse);
    });

    test('save creates the file and directory', () {
      store.save(credentials);

      final file = File('${tempDir.path}/credentials.json');
      expect(file.existsSync(), isTrue);
    });

    test('load returns correct Credentials after save', () {
      store.save(credentials);
      final loaded = store.load();

      expect(loaded, isNotNull);
      expect(loaded!.accessToken, equals(credentials.accessToken));
      expect(loaded.teamId, equals(credentials.teamId));
      expect(loaded.teamName, equals(credentials.teamName));
      expect(loaded.userId, equals(credentials.userId));
    });

    test('hasCredentials returns true after save', () {
      store.save(credentials);
      expect(store.hasCredentials, isTrue);
    });

    test('delete removes the file', () {
      store.save(credentials);
      expect(store.delete(), isTrue);
      expect(store.hasCredentials, isFalse);
    });

    test('delete returns false when no file exists', () {
      expect(store.delete(), isFalse);
    });

    test(
      'save sets file permissions to 600 on POSIX',
      () {
        store.save(credentials);

        final file = File('${tempDir.path}/credentials.json');
        final stat = file.statSync();
        // 600 in octal = 384 in decimal, but FileStat.mode
        // includes the file type bits. Mask with 0x1FF (octal 777).
        final permissions = stat.mode & 0x1FF;
        // 0x180 = octal 600
        expect(permissions, equals(0x180));
      },
      skip: !Platform.isMacOS && !Platform.isLinux
          ? 'File permissions only testable on POSIX'
          : null,
    );
  });
}
