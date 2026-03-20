import 'package:dart_slack/src/auth/credentials.dart';
import 'package:dart_slack/src/auth/credentials_store.dart';
import 'package:dart_slack/src/auth/oauth_flow.dart';
import 'package:dart_slack/src/cli/commands/login_command.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockCredentialsStore extends Mock implements CredentialsStore {}

class _MockOAuthFlow extends Mock implements OAuthFlow {}

void main() {
  group('LoginCommand', () {
    late Logger logger;
    late CredentialsStore credentialsStore;
    late OAuthFlow oauthFlow;
    late LoginCommand command;

    const credentials = Credentials(
      accessToken: 'xoxp-test',
      teamId: 'T123',
      teamName: 'Test Team',
      userId: 'U123',
    );

    setUp(() {
      logger = _MockLogger();
      credentialsStore = _MockCredentialsStore();
      oauthFlow = _MockOAuthFlow();
      command = LoginCommand(
        logger: logger,
        credentialsStore: credentialsStore,
        oauthFlow: oauthFlow,
      );
    });

    test('has correct name and description', () {
      expect(command.name, equals('login'));
      expect(command.description, isNotEmpty);
    });

    test('successful login stores credentials and logs success', () async {
      when(() => credentialsStore.hasCredentials).thenReturn(false);
      when(() => oauthFlow.execute()).thenAnswer(
        (_) async => credentials,
      );
      when(() => credentialsStore.save(credentials)).thenReturn(null);

      final result = await command.run();

      expect(result, equals(ExitCode.success.code));
      verify(() => credentialsStore.save(credentials)).called(1);
      verify(
        () => logger.success('Logged in to Test Team.'),
      ).called(1);
    });

    test(
      'prompts re-auth when already logged in and user declines',
      () async {
        when(() => credentialsStore.hasCredentials).thenReturn(true);
        when(() => credentialsStore.load()).thenReturn(credentials);
        when(() => logger.confirm(any())).thenReturn(false);

        final result = await command.run();

        expect(result, equals(ExitCode.success.code));
        verifyNever(() => oauthFlow.execute());
      },
    );

    test(
      'prompts re-auth when already logged in and user accepts',
      () async {
        when(() => credentialsStore.hasCredentials).thenReturn(true);
        when(() => credentialsStore.load()).thenReturn(credentials);
        when(() => logger.confirm(any())).thenReturn(true);
        when(() => oauthFlow.execute()).thenAnswer(
          (_) async => credentials,
        );
        when(
          () => credentialsStore.save(credentials),
        ).thenReturn(null);

        final result = await command.run();

        expect(result, equals(ExitCode.success.code));
        verify(() => oauthFlow.execute()).called(1);
      },
    );

    test('returns software error on OAuthException', () async {
      when(() => credentialsStore.hasCredentials).thenReturn(false);
      when(() => oauthFlow.execute()).thenThrow(
        const OAuthException('access_denied'),
      );

      final result = await command.run();

      expect(result, equals(ExitCode.software.code));
      verify(
        () => logger.err('Authentication failed: access_denied'),
      ).called(1);
    });
  });
}
