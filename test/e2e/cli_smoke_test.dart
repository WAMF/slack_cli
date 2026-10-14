@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:dart_slack/src/cli/version.dart';
import 'package:test/test.dart';

/// Runs the real `bin/dart_slack.dart` entry point as a child process.
///
/// These tests cover what the in-process runner tests cannot: the exit code
/// that `main` passes to `exit()`, the stdout/stderr flush, and the wiring from
/// `main` to the command runner.
///
/// Only argument paths that fail or finish before any credential is read are
/// used, and the child gets a minimal environment with an empty `HOME` and no
/// `SLACK_TOKEN`, so it can never reach Slack.
void main() {
  late Directory home;
  late String executable;

  // Compile once: starting the app from source costs several seconds per run.
  setUpAll(() async {
    home = Directory.systemTemp.createTempSync('dart_slack_e2e_home_');
    executable = '${home.path}/dart_slack';
    final compiled = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'exe',
      'bin/dart_slack.dart',
      '-o',
      executable,
    ]);
    expect(compiled.exitCode, 0, reason: '${compiled.stderr}');
  });

  tearDownAll(() => home.deleteSync(recursive: true));

  Future<ProcessResult> run(List<String> args) => Process.run(
    executable,
    args,
    includeParentEnvironment: false,
    environment: {
      'PATH': Platform.environment['PATH'] ?? '',
      'HOME': home.path,
    },
  );

  void expectRun(
    String name,
    List<String> args, {
    required int exitCode,
    required String stream,
    required String expected,
  }) {
    test(name, () async {
      final result = await run(args);
      expect(
        result.exitCode,
        exitCode,
        reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}',
      );
      final output = stream == 'stdout' ? result.stdout : result.stderr;
      expect(output, contains(expected));
    });
  }

  expectRun(
    '--help exits 0',
    ['--help'],
    exitCode: 0,
    stream: 'stdout',
    expected: 'Usage: dart_slack',
  );
  expectRun(
    '--version exits 0 and prints the package version',
    ['--version'],
    exitCode: 0,
    stream: 'stdout',
    expected: packageVersion,
  );
  expectRun(
    'unknown command exits 64',
    ['not-a-command'],
    exitCode: 64,
    stream: 'stderr',
    expected: 'not-a-command',
  );
  expectRun(
    'search without --query exits 64',
    ['search'],
    exitCode: 64,
    stream: 'stderr',
    expected: 'Missing --query',
  );
  expectRun(
    'search with --limit 0 exits 64',
    ['search', '-q', 'x', '-l', '0'],
    exitCode: 64,
    stream: 'stderr',
    expected: 'Invalid --limit value',
  );
  expectRun(
    'search with an invalid --channel exits 64',
    ['search', '-q', 'x', '-c', '#'],
    exitCode: 64,
    stream: 'stderr',
    expected: 'Invalid --channel value',
  );
  expectRun(
    'send without message text exits 64',
    ['send', '-c', 'C1'],
    exitCode: 64,
    stream: 'stderr',
    expected: 'Missing the message text',
  );
  // Pins current behaviour on main: with no credentials, `history` stops at the
  // login check with exit 67 before it validates arguments. PR #58 changes this
  // to 64 with "Option channel is mandatory."
  expectRun(
    'history without credentials exits 67',
    ['history'],
    exitCode: 67,
    stream: 'stderr',
    expected: 'Not logged in',
  );
}
