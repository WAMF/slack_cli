import 'dart:convert';
import 'dart:io';

import 'package:dart_slack/src/cli/stream_lock.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('slack-stream-lock-');
  });
  tearDown(() => directory.deleteSync(recursive: true));

  test('rejects duplicate local acquisition and releases on close', () {
    final first = StreamLock.acquire(directory: directory)!;
    expect(StreamLock.acquire(directory: directory), isNull);
    first
      ..close()
      ..close();
    final next = StreamLock.acquire(directory: directory);
    expect(next, isNotNull);
    next?.close();
    expect(File('${directory.path}/stream.lock').existsSync(), isTrue);
  });

  test(
    'excludes another process and recovers when its owner is killed',
    () async {
      final child = await Process.start(Platform.resolvedExecutable, [
        '--packages=${Directory.current.path}/.dart_tool/package_config.json',
        'test/fixtures/stream_lock_process.dart',
        directory.path,
      ]);
      addTearDown(() async {
        child.kill();
        await child.exitCode;
      });
      final errors = child.stderr.transform(utf8.decoder).join();
      final state = await child.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first;
      expect(state, 'acquired');
      expect(StreamLock.acquire(directory: directory), isNull);

      expect(child.kill(ProcessSignal.sigkill), isTrue);
      await child.exitCode;
      expect(await errors, isEmpty);
      final next = StreamLock.acquire(directory: directory);
      expect(next, isNotNull);
      next?.close();
    },
  );
}
