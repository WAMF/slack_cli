import 'dart:io';

import 'package:meta/meta.dart';

/// Changes the POSIX permission bits of [path] to [mode] (octal string).
typedef Chmod = void Function(String mode, String path);

void _runChmod(String mode, String path) {
  Process.runSync('chmod', [mode, path]);
}

bool get _isPosix => Platform.isMacOS || Platform.isLinux;

/// Returns the `~/.dart_slack` config path for [environment].
///
/// Falls back from `HOME` to `USERPROFILE` (Windows) and then to the current
/// directory, so a missing `HOME` never produces a literal `null/.dart_slack`.
String dartSlackConfigPath(Map<String, String> environment) {
  final home =
      environment['HOME'] ??
      environment['USERPROFILE'] ??
      Directory.current.path;
  return '$home/.dart_slack';
}

/// Creates [directory] if needed and restricts it to its owner (mode 700) on
/// POSIX systems.
///
/// Files created inside a 700 directory cannot be opened by other users even
/// while their own mode still reflects the default umask, which closes the
/// window between creating a secret file and restricting it.
void ensurePrivateDirectory(Directory directory) {
  directory.createSync(recursive: true);
  if (_isPosix) _runChmod('700', directory.path);
}

/// Writes [contents] to [file] so the secret is never readable by other
/// users, not even briefly.
///
/// On POSIX systems the bytes go to an empty sibling temp file that is first
/// restricted to mode 600, then the temp file is renamed over [file]. The
/// rename is atomic, so a reader sees the old file or the complete new one,
/// and the final file is always 600.
void writePrivateFile(
  File file,
  String contents, {
  @visibleForTesting Chmod? chmod,
}) {
  final temp = File('${file.path}.tmp');
  try {
    temp.createSync(exclusive: true);
  } on FileSystemException {
    // A temp file left by an interrupted write: start again from empty.
    temp
      ..deleteSync()
      ..createSync(exclusive: true);
  }
  try {
    if (_isPosix) (chmod ?? _runChmod)('600', temp.path);
    temp
      ..writeAsStringSync(contents, flush: true)
      ..renameSync(file.path);
  } on Object {
    if (temp.existsSync()) temp.deleteSync();
    rethrow;
  }
}
