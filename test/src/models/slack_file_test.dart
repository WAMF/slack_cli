import 'package:dart_slack/src/models/slack_file.dart';
import 'package:test/test.dart';

void main() {
  group('SlackFile', () {
    test('fromJson parses name', () {
      final file = SlackFile.fromJson(const {
        'id': 'F123',
        'name': 'report.pdf',
        'mimetype': 'application/pdf',
      });

      expect(file.name, equals('report.pdf'));
    });

    test('fromJson defaults name to untitled when missing', () {
      final file = SlackFile.fromJson(const {'id': 'F456'});

      expect(file.name, equals('untitled'));
    });
  });
}
