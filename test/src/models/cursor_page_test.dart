import 'package:dart_slack/src/models/cursor_page.dart';
import 'package:test/test.dart';

void main() {
  group('CursorPage', () {
    test('stores items and pagination metadata', () {
      const page = CursorPage<String>(
        items: ['a', 'b'],
        hasMore: true,
        nextCursor: 'abc123',
      );

      expect(page.items, equals(['a', 'b']));
      expect(page.hasMore, isTrue);
      expect(page.nextCursor, equals('abc123'));
    });

    test('nextCursor defaults to null', () {
      const page = CursorPage<int>(
        items: [1],
        hasMore: false,
      );

      expect(page.nextCursor, isNull);
      expect(page.hasMore, isFalse);
    });
  });
}
