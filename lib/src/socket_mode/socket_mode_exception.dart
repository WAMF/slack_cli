/// Thrown when a Socket Mode connection or protocol error occurs.
class SocketModeException implements Exception {
  /// Creates a [SocketModeException] with the given [message].
  const SocketModeException(this.message);

  /// A description of the error.
  final String message;

  @override
  String toString() => 'SocketModeException: $message';
}
