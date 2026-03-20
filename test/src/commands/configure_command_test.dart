import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_slack/src/auth/app_config.dart';
import 'package:dart_slack/src/auth/app_config_store.dart';
import 'package:dart_slack/src/cli/commands/configure_command.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockAppConfigStore extends Mock implements AppConfigStore {}

class _MockStdout extends Mock implements Stdout {}

/// Fake [Stdin] that records [echoMode] changes and returns a preset line.
class _FakeStdin extends Fake implements Stdin {
  String? lineToReturn;
  final echoModeHistory = <bool>[];
  bool _echoMode = true;

  @override
  bool get echoMode => _echoMode;

  @override
  set echoMode(bool value) {
    _echoMode = value;
    echoModeHistory.add(value);
  }

  @override
  String? readLineSync({
    Encoding encoding = systemEncoding,
    bool retainNewlines = false,
  }) => lineToReturn;
}

void main() {
  group('ConfigureCommand', () {
    late _MockLogger logger;
    late _MockAppConfigStore configStore;
    late _FakeStdin fakeStdin;
    late _MockStdout mockStdout;

    setUpAll(() {
      registerFallbackValue(const AppConfig(appToken: ''));
    });

    setUp(() {
      logger = _MockLogger();
      configStore = _MockAppConfigStore();
      fakeStdin = _FakeStdin();
      mockStdout = _MockStdout();

      when(() => logger.info(any())).thenReturn(null);
      when(() => logger.err(any())).thenReturn(null);
      when(() => logger.success(any())).thenReturn(null);
      when(() => mockStdout.write(any())).thenReturn(null);
      when(() => mockStdout.writeln(any())).thenReturn(null);
      when(() => mockStdout.writeln()).thenReturn(null);
    });

    CommandRunner<int> buildRunner() {
      return CommandRunner<int>('test', 'test')..addCommand(
        ConfigureCommand(
          logger: logger,
          configStore: configStore,
          stdin: fakeStdin,
          stdout: mockStdout,
        ),
      );
    }

    test('has correct name and description', () {
      final command = ConfigureCommand(logger: logger);
      expect(command.name, equals('configure'));
      expect(command.description, isNotEmpty);
    });

    test('saves valid token with hidden input', () async {
      when(() => configStore.hasConfig).thenReturn(false);
      when(() => configStore.save(any())).thenReturn(null);
      fakeStdin.lineToReturn = 'xapp-1-A0123-token';

      final runner = buildRunner();
      final exitCode = await runner.run(['configure']);

      expect(exitCode, equals(ExitCode.success.code));

      final captured =
          verify(() => configStore.save(captureAny())).captured.first
              as AppConfig;
      expect(captured.appToken, equals('xapp-1-A0123-token'));

      verify(
        () => logger.success(any(that: contains('App token saved'))),
      ).called(1);
    });

    test('disables echo during token input', () async {
      when(() => configStore.hasConfig).thenReturn(false);
      when(() => configStore.save(any())).thenReturn(null);
      fakeStdin.lineToReturn = 'xapp-1-test';

      final runner = buildRunner();
      await runner.run(['configure']);

      expect(fakeStdin.echoModeHistory, equals([false, true]));
    });

    test('rejects tokens without xapp- prefix', () async {
      when(() => configStore.hasConfig).thenReturn(false);
      fakeStdin.lineToReturn = 'xoxp-invalid-token';

      final runner = buildRunner();
      final exitCode = await runner.run(['configure']);

      expect(exitCode, equals(ExitCode.usage.code));

      verify(() => logger.err(any(that: contains('Invalid token')))).called(1);
      verifyNever(() => configStore.save(any()));
    });

    test('rejects empty input', () async {
      when(() => configStore.hasConfig).thenReturn(false);
      fakeStdin.lineToReturn = '';

      final runner = buildRunner();
      final exitCode = await runner.run(['configure']);

      expect(exitCode, equals(ExitCode.usage.code));

      verify(() => logger.err(any(that: contains('No token')))).called(1);
    });

    test('--clear removes stored config', () async {
      when(() => configStore.delete()).thenReturn(true);

      final runner = buildRunner();
      final exitCode = await runner.run(['configure', '--clear']);

      expect(exitCode, equals(ExitCode.success.code));

      verify(
        () => logger.success(any(that: contains('removed'))),
      ).called(1);
    });

    test('--clear handles no existing config', () async {
      when(() => configStore.delete()).thenReturn(false);

      final runner = buildRunner();
      final exitCode = await runner.run(['configure', '--clear']);

      expect(exitCode, equals(ExitCode.success.code));

      verify(
        () => logger.info(any(that: contains('No app configuration'))),
      ).called(1);
    });

    test('prompts before overwriting existing config', () async {
      when(() => configStore.hasConfig).thenReturn(true);
      when(() => configStore.load()).thenReturn(
        const AppConfig(appToken: 'xapp-1-existing'),
      );
      when(() => logger.confirm(any())).thenReturn(false);

      final runner = buildRunner();
      final exitCode = await runner.run(['configure']);

      expect(exitCode, equals(ExitCode.success.code));

      verify(
        () => logger.confirm(any(that: contains('Reconfigure'))),
      ).called(1);
      verifyNever(() => configStore.save(any()));
    });

    test('overwrites when user confirms', () async {
      when(() => configStore.hasConfig).thenReturn(true);
      when(() => configStore.load()).thenReturn(
        const AppConfig(appToken: 'xapp-1-existing'),
      );
      when(() => logger.confirm(any())).thenReturn(true);
      when(() => configStore.save(any())).thenReturn(null);
      fakeStdin.lineToReturn = 'xapp-1-new-token';

      final runner = buildRunner();
      final exitCode = await runner.run(['configure']);

      expect(exitCode, equals(ExitCode.success.code));

      final captured =
          verify(() => configStore.save(captureAny())).captured.first
              as AppConfig;
      expect(captured.appToken, equals('xapp-1-new-token'));
    });
  });
}
