import 'package:dart_slack/src/cli/commands/dm_command.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

void main() {
  group('DmCommand', () {
    late Logger logger;
    late DmCommand command;

    setUp(() {
      logger = _MockLogger();
      command = DmCommand(logger: logger);
    });

    test('has correct name and description', () {
      expect(command.name, equals('dm'));
      expect(command.description, isNotEmpty);
    });

    test('requires user and text options', () {
      final options = command.argParser.options;
      expect(options['user']?.mandatory, isTrue);
      expect(options['text']?.mandatory, isTrue);
    });

    test('has correct abbreviations', () {
      final options = command.argParser.options;
      expect(options['user']?.abbr, equals('u'));
      expect(options['text']?.abbr, equals('t'));
    });
  });
}
