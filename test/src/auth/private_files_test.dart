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

    test('throws when chmod exits non-zero', () {
      expect(
        () => ensurePrivateDirectory(tempDir, chmod: (_, _) => 1),
        throwsA(
          isA<FileSystemException>()
              .having(
                (e) => e.message,
                'message',
                equals(
                  'Could not restrict to mode 700: chmod exited with code 1',
                ),
              )
              .having((e) => e.path, 'path', equals(tempDir.path)),
        ),
      );
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
          return Process.runSync('chmod', [mode, path]).exitCode;
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
          return 0;
        },
      );

      expect(targetExistedAtChmod, equals([false]));
    }, skip: posixOnly);

    test('an overlapping save keeps the file complete and 600', () {
      // Writer B runs a whole save while writer A is between its chmod and
      // its write. With a shared temp name, B removed A's temp and A then
      // wrote a new temp with the default umask (644).
      writePrivateFile(
        target,
        'writer A',
        chmod: (mode, path) {
          final exitCode = Process.runSync('chmod', [mode, path]).exitCode;
          writePrivateFile(target, 'writer B');
          return exitCode;
        },
      );

      expect(target.readAsStringSync(), equals('writer A'));
      expect(_permissions(target), equals(0x180));
      expect(
        tempDir.listSync().map((e) => e.uri.pathSegments.last),
        equals(['secret.json']),
      );
    }, skip: posixOnly);

    test('a failed save removes only its own temp file', () {
      final other = File('${target.path}.1.0000abcd.tmp')
        ..writeAsStringSync('another writer');
      String? ownTemp;

      expect(
        () => writePrivateFile(
          target,
          'xoxp-secret',
          chmod: (mode, path) {
            ownTemp = path;
            throw const FileSystemException('chmod failed');
          },
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(ownTemp, isNot(equals(other.path)));
      expect(File(ownTemp!).existsSync(), isFalse);
      expect(other.readAsStringSync(), equals('another writer'));
      expect(target.existsSync(), isFalse);
    }, skip: posixOnly);

    test(
      'fails the save and removes its temp file when chmod exits non-zero',
      () {
        target.writeAsStringSync('old');
        String? ownTemp;

        expect(
          () => writePrivateFile(
            target,
            'xoxp-secret',
            chmod: (mode, path) {
              ownTemp = path;
              return 1;
            },
          ),
          throwsA(
            isA<FileSystemException>()
                .having(
                  (e) => e.message,
                  'message',
                  equals(
                    'Could not restrict to mode 600: chmod exited with code 1',
                  ),
                )
                .having((e) => e.path, 'path', endsWith('.tmp')),
          ),
        );

        expect(File(ownTemp!).existsSync(), isFalse);
        expect(target.readAsStringSync(), equals('old'));
      },
      skip: posixOnly,
    );
  });

  group('stale temp files', () {
    late Directory tempDir;
    late File target;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('private_files_test_');
      target = File('${tempDir.path}/secret.json');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    /// Creates [name] in the test directory and returns it with its mtime.
    (File, DateTime) leftover(String name) {
      final file = File('${tempDir.path}/$name')..createSync();
      return (file, file.lastModifiedSync());
    }

    test('a save removes a temp file older than staleTempAge', () {
      final (stale, modified) = leftover('secret.json.4242.0000abcd.tmp');

      writePrivateFile(
        target,
        'new',
        chmod: (_, _) => 0,
        now: () => modified.add(staleTempAge + const Duration(seconds: 1)),
      );

      expect(stale.existsSync(), isFalse);
      expect(target.readAsStringSync(), equals('new'));
    });

    test('a save keeps a temp file younger than staleTempAge', () {
      final (recent, modified) = leftover('secret.json.4242.0000abcd.tmp');

      writePrivateFile(
        target,
        'new',
        chmod: (_, _) => 0,
        now: () => modified.add(staleTempAge - const Duration(seconds: 1)),
      );

      expect(recent.existsSync(), isTrue);
    });

    test('a save removes stale temp files of other files in the directory', () {
      final (stale, modified) = leftover('config.json.7.89abcdef.tmp');

      writePrivateFile(
        target,
        'new',
        chmod: (_, _) => 0,
        now: () => modified.add(const Duration(days: 1)),
      );

      expect(stale.existsSync(), isFalse);
    });

    test('a save keeps old files whose name this tool does not create', () {
      final names = [
        'notes.tmp',
        'secret.json.tmp',
        'secret.json.bak',
        'secret.json.4242.0000ABCD.tmp',
        'secret.json.4242.abcd.tmp',
        'secret.json.pid.0000abcd.tmp',
        'secret.json.4242.0000abcd.tmp.keep',
      ];
      final kept = [for (final name in names) leftover(name).$1];
      final directory = Directory('${tempDir.path}/secret.json.1.0000abcd.tmp')
        ..createSync();

      writePrivateFile(
        target,
        'new',
        chmod: (_, _) => 0,
        now: () => DateTime.now().add(const Duration(days: 1)),
      );

      for (final file in kept) {
        expect(file.existsSync(), isTrue, reason: file.path);
      }
      expect(directory.existsSync(), isTrue);
    });
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
