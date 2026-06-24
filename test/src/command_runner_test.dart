import 'package:args/command_runner.dart';
import 'package:cli_completion/cli_completion.dart';
import 'package:dart_slack/src/cli/command_runner.dart';
import 'package:dart_slack/src/cli/version.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

void main() {
  group('DartSlackCommandRunner', () {
    late Logger logger;
    late DartSlackCommandRunner commandRunner;

    setUp(() {
      logger = _MockLogger();
      commandRunner = DartSlackCommandRunner(logger: logger);
    });

    test(
      'fast-tracks the completion command and exits successfully',
      () async {
        final result = await commandRunner.run(['completion']);
        expect(result, equals(ExitCode.success.code));
      },
    );

    test(
      'can be instantiated without an explicit logger instance',
      () {
        final commandRunner = DartSlackCommandRunner();
        expect(commandRunner, isNotNull);
        expect(commandRunner, isA<CompletionCommandRunner<int>>());
      },
    );

    test('handles FormatException', () async {
      const exception = FormatException('oops!');
      var isFirstInvocation = true;
      when(() => logger.info(any())).thenAnswer((_) {
        if (isFirstInvocation) {
          isFirstInvocation = false;
          throw exception;
        }
      });
      final result = await commandRunner.run(['--version']);
      expect(result, equals(ExitCode.usage.code));
      verify(() => logger.err(exception.message)).called(1);
      verify(() => logger.info(commandRunner.usage)).called(1);
    });

    test('handles UsageException', () async {
      final exception = UsageException('oops!', 'exception usage');
      var isFirstInvocation = true;
      when(() => logger.info(any())).thenAnswer((_) {
        if (isFirstInvocation) {
          isFirstInvocation = false;
          throw exception;
        }
      });
      final result = await commandRunner.run(['--version']);
      expect(result, equals(ExitCode.usage.code));
      verify(() => logger.err(exception.message)).called(1);
      verify(() => logger.info('exception usage')).called(1);
    });

    group('--version', () {
      test('outputs current version', () async {
        final result = await commandRunner.run(['--version']);
        expect(result, equals(ExitCode.success.code));
        verify(() => logger.info(packageVersion)).called(1);
      });
    });

    group('--verbose', () {
      test('enables verbose logging', () async {
        final result = await commandRunner.run(['--verbose']);
        expect(result, equals(ExitCode.success.code));

        verify(
          () => logger.detail('Argument information:'),
        ).called(1);
        verify(
          () => logger.detail('  Top level options:'),
        ).called(1);
        verify(
          () => logger.detail('  - verbose: true'),
        ).called(1);
        verifyNever(
          () => logger.detail('    Command options:'),
        );
      });
    });
  });
}
