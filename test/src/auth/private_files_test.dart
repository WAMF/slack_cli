import 'dart:io';

import 'package:dart_slack/src/auth/private_files.dart';
import 'package:test/test.dart';

/// The permission bits of [entity], without the file type bits.
int _permissions(FileSystemEntity entity) => entity.statSync().mode & 0x1FF;

void main() {
  final posixOnly = !Platform.isMacOS && !Platform.isLinux
      ? 'File permissions only testable on POSIX'
      : null;

  group('ensurePrivateDirectory', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('private_files_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('creates a missing directory with mode 700', () {
      final directory = Directory('${tempDir.path}/a/b');

      ensurePrivateDirectory(directory);

      expect(directory.existsSync(), isTrue);
      // 0x1C0 = octal 700
      expect(_permissions(directory), equals(0x1C0));
    }, skip: posixOnly);

    test('tightens an existing group- and world-readable directory', () {
      Process.runSync('chmod', ['755', tempDir.path]);

      ensurePrivateDirectory(tempDir);

      expect(_permissions(tempDir), equals(0x1C0));
    }, skip: posixOnly);
  });

  group('writePrivateFile', () {
    late Directory tempDir;
    late File target;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('private_files_test_');
      target = File('${tempDir.path}/secret.json');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('writes the contents with mode 600 and leaves no temp file', () {
      writePrivateFile(target, 'xoxp-secret');

      expect(target.readAsStringSync(), equals('xoxp-secret'));
      // 0x180 = octal 600
      expect(_permissions(target), equals(0x180));
      expect(
        tempDir.listSync().map((e) => e.uri.pathSegments.last),
        equals(['secret.json']),
      );
    }, skip: posixOnly);

    test('replaces an existing world-readable file with a 600 file', () {
      target.writeAsStringSync('old');
      Process.runSync('chmod', ['644', target.path]);

      writePrivateFile(target, 'new');

      expect(target.readAsStringSync(), equals('new'));
      expect(_permissions(target), equals(0x180));
    }, skip: posixOnly);

    test('restricts the file before any secret byte is written', () {
      final lengthsAtChmod = <int>[];
      final modesAtChmod = <String>[];

      writePrivateFile(
        target,
        'xoxp-secret',
        chmod: (mode, path) {
          modesAtChmod.add(mode);
          lengthsAtChmod.add(File(path).lengthSync());
          Process.runSync('chmod', [mode, path]);
        },
      );

      expect(modesAtChmod, equals(['600']));
      expect(
        lengthsAtChmod,
        equals([0]),
        reason: 'the token must never sit in a file with the default umask',
      );
      expect(target.readAsStringSync(), equals('xoxp-secret'));
    }, skip: posixOnly);

    test('never exposes the secret under the final name before it is 600', () {
      final targetExistedAtChmod = <bool>[];

      writePrivateFile(
        target,
        'xoxp-secret',
        chmod: (mode, path) {
          targetExistedAtChmod.add(target.existsSync());
          expect(path, isNot(equals(target.path)));
        },
      );

      expect(targetExistedAtChmod, equals([false]));
    }, skip: posixOnly);
  });

  group('dartSlackConfigPath', () {
    test('uses HOME when it is set', () {
      expect(
        dartSlackConfigPath({'HOME': '/home/u', 'USERPROFILE': r'C:\u'}),
        equals('/home/u/.dart_slack'),
      );
    });

    test('falls back to USERPROFILE when HOME is unset', () {
      expect(
        dartSlackConfigPath({'USERPROFILE': r'C:\u'}),
        equals(r'C:\u/.dart_slack'),
      );
    });

    test('falls back to the current directory, never the string "null"', () {
      expect(
        dartSlackConfigPath({}),
        equals('${Directory.current.path}/.dart_slack'),
      );
    });
  });
}
