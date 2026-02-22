/// A single page of results from a cursor-paginated Slack API endpoint.
class CursorPage<T> {
  /// Creates a [CursorPage].
  const CursorPage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

  /// The items in this page.
  final List<T> items;

  /// Whether more pages are available.
  final bool hasMore;

  /// The cursor to pass for the next page, or `null` if this is the last.
  final String? nextCursor;
}
