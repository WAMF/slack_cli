import 'dart:io';

import 'package:dart_slack/src/cli/slack_app.dart';
import 'package:test/test.dart';

void main() {
  group('SlackApp', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('slack_app_test_');
    });

    tearDown(() {
      SlackApp.resetForTesting();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('reads credentials from .env file', () {
      File('${tempDir.path}/.env').writeAsStringSync(
        'SLACK_CLIENT_ID=test-id\nSLACK_CLIENT_SECRET=test-secret\n',
      );
      SlackApp.resetForTesting(dotEnvPath: '${tempDir.path}/.env');

      expect(SlackApp.clientId, equals('test-id'));
      expect(SlackApp.clientSecret, equals('test-secret'));
    });

    test('skips empty lines and comments', () {
      File('${tempDir.path}/.env').writeAsStringSync(
        '# A comment\n'
        '\n'
        'SLACK_CLIENT_ID=id-val\n'
        '\n'
        'SLACK_CLIENT_SECRET=secret-val\n',
      );
      SlackApp.resetForTesting(dotEnvPath: '${tempDir.path}/.env');

      expect(SlackApp.clientId, equals('id-val'));
      expect(SlackApp.clientSecret, equals('secret-val'));
    });

    test('skips lines without equals sign', () {
      File('${tempDir.path}/.env').writeAsStringSync(
        'INVALID_LINE\n'
        'SLACK_CLIENT_ID=id\n'
        'SLACK_CLIENT_SECRET=secret\n',
      );
      SlackApp.resetForTesting(dotEnvPath: '${tempDir.path}/.env');

      expect(SlackApp.clientId, equals('id'));
      expect(SlackApp.clientSecret, equals('secret'));
    });

    test('throws StateError when SLACK_CLIENT_ID is missing', () {
      File('${tempDir.path}/.env').writeAsStringSync(
        'SLACK_CLIENT_SECRET=secret\n',
      );
      SlackApp.resetForTesting(dotEnvPath: '${tempDir.path}/.env');

      expect(() => SlackApp.clientId, throwsA(isA<StateError>()));
    });

    test('throws StateError when SLACK_CLIENT_SECRET is missing', () {
      File('${tempDir.path}/.env').writeAsStringSync(
        'SLACK_CLIENT_ID=id\n',
      );
      SlackApp.resetForTesting(dotEnvPath: '${tempDir.path}/.env');

      expect(() => SlackApp.clientSecret, throwsA(isA<StateError>()));
    });

    test('handles missing .env file gracefully', () {
      SlackApp.resetForTesting(
        dotEnvPath: '${tempDir.path}/nonexistent.env',
      );

      // Without SLACK_CLIENT_ID in the real environment this should throw.
      expect(() => SlackApp.clientId, throwsA(isA<StateError>()));
    });

    test('trims whitespace around keys and values', () {
      File('${tempDir.path}/.env').writeAsStringSync(
        '  SLACK_CLIENT_ID  =  spaced-id  \n'
        '  SLACK_CLIENT_SECRET  =  spaced-secret  \n',
      );
      SlackApp.resetForTesting(dotEnvPath: '${tempDir.path}/.env');

      expect(SlackApp.clientId, equals('spaced-id'));
      expect(SlackApp.clientSecret, equals('spaced-secret'));
    });
  });
}
