import 'package:dart_slack/src/auth/credentials_store.dart';
import 'package:dart_slack/src/cli/commands/logout_command.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockCredentialsStore extends Mock implements CredentialsStore {}

void main() {
  group('LogoutCommand', () {
    late Logger logger;
    late CredentialsStore credentialsStore;
    late LogoutCommand command;

    setUp(() {
      logger = _MockLogger();
      credentialsStore = _MockCredentialsStore();
      command = LogoutCommand(
        logger: logger,
        credentialsStore: credentialsStore,
      );
    });

    test('has correct name and description', () {
      expect(command.name, equals('logout'));
      expect(command.description, isNotEmpty);
    });

    test('deletes credentials and logs success', () async {
      when(() => credentialsStore.delete()).thenReturn(true);

      final result = await command.run();

      expect(result, equals(ExitCode.success.code));
      verify(() => credentialsStore.delete()).called(1);
      verify(() => logger.success('Logged out.')).called(1);
    });

    test(
      'logs info message when no credentials exist',
      () async {
        when(() => credentialsStore.delete()).thenReturn(false);

        final result = await command.run();

        expect(result, equals(ExitCode.success.code));
        verify(
          () => logger.info('No credentials found.'),
        ).called(1);
      },
    );
  });
}
