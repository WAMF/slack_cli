import 'dart:io';

import 'package:dart_slack/src/auth/private_files.dart';

/// Holds the single local CLI stream slot until closed or the process exits.
///
/// Slack distributes events between an app's connections. Separate local
/// channel listeners would acknowledge and discard each other's events.
/// Keep this file in place: removing it could let another process lock a new
/// inode while an existing listener still holds the original lock.
class StreamLock {
  new _(this._file, this._path);

  final RandomAccessFile _file;
  final String _path;
  bool _closed = false;

  // POSIX file locks belong to the process, so also reject a second command
  // in this isolate before it opens (and later closes) the same lock file.
  static final _heldPaths = <String>{};

  /// Returns null if another listener holds the slot. Other filesystem
  /// failures propagate so the CLI can report them without opening a socket.
  static StreamLock? acquire({Directory? directory}) {
    final config =
        directory ?? Directory(dartSlackConfigPath(Platform.environment));
    ensurePrivateDirectory(config);
    final path = '${config.resolveSymbolicLinksSync()}/stream.lock';
    if (!_heldPaths.add(path)) return null;

    RandomAccessFile? file;
    try {
      file = File(path).openSync(mode: FileMode.append);
      try {
        file.lockSync();
      } on FileSystemException {
        file.closeSync();
        _heldPaths.remove(path);
        return null;
      }
      return StreamLock._(file, path);
    } on Object {
      file?.closeSync();
      _heldPaths.remove(path);
      rethrow;
    }
  }

  /// Releases the slot. The OS also releases it if the process terminates.
  void close() {
    if (_closed) return;
    _closed = true;
    try {
      _file.closeSync();
    } finally {
      _heldPaths.remove(_path);
    }
  }
}
