import 'package:dart_slack/src/cli/commands/reply_command.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

void main() {
  group('ReplyCommand', () {
    late Logger logger;
    late ReplyCommand command;

    setUp(() {
      logger = _MockLogger();
      command = ReplyCommand(logger: logger);
    });

    test('has correct name and description', () {
      expect(command.name, equals('reply'));
      expect(command.description, isNotEmpty);
    });

    test('requires channel, thread, and text options', () {
      final options = command.argParser.options;
      expect(options['channel']?.mandatory, isTrue);
      expect(options['thread']?.mandatory, isTrue);
      expect(options['text']?.mandatory, isTrue);
    });

    test('has correct abbreviations', () {
      final options = command.argParser.options;
      expect(options['channel']?.abbr, equals('c'));
      expect(options['thread']?.abbr, equals('r'));
      expect(options['text']?.abbr, equals('t'));
    });
  });
}
