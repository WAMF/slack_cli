import 'package:dart_slack/src/cli/commands/send_command.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

void main() {
  group('SendCommand', () {
    late Logger logger;
    late SendCommand command;

    setUp(() {
      logger = _MockLogger();
      command = SendCommand(logger: logger);
    });

    test('has correct name and description', () {
      expect(command.name, equals('send'));
      expect(command.description, isNotEmpty);
    });

    test('requires channel and text options', () {
      final options = command.argParser.options;
      expect(options['channel']?.mandatory, isTrue);
      expect(options['text']?.mandatory, isTrue);
    });

    test('has correct abbreviations', () {
      final options = command.argParser.options;
      expect(options['channel']?.abbr, equals('c'));
      expect(options['text']?.abbr, equals('t'));
    });
  });
}
