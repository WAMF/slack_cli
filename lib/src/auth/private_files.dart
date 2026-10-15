import 'dart:io';
import 'dart:math';

import 'package:meta/meta.dart';

/// Changes the POSIX permission bits of [path] to [mode] (octal string) and
/// returns the exit code of `chmod`.
typedef Chmod = int Function(String mode, String path);

int _runChmod(String mode, String path) =>
    Process.runSync('chmod', [mode, path]).exitCode;

/// Runs [chmod] and throws a [FileSystemException] when it exits non-zero, so
/// a path is never assumed to be restricted when it is not.
void _restrict(String mode, String path, Chmod chmod) {
  final exitCode = chmod(mode, path);
  if (exitCode != 0) {
    throw FileSystemException(
      'Could not restrict to mode $mode: chmod exited with code $exitCode',
      path,
    );
  }
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
///
/// Throws a [FileSystemException] when `chmod` exits non-zero.
void ensurePrivateDirectory(
  Directory directory, {
  @visibleForTesting Chmod? chmod,
}) {
  directory.createSync(recursive: true);
  if (_isPosix) _restrict('700', directory.path, chmod ?? _runChmod);
}

/// Writes [contents] to [file] so the secret is never readable by other
/// users, not even briefly.
///
/// On POSIX systems the bytes go to an empty sibling temp file that is first
/// restricted to mode 600, then the temp file is renamed over [file]. The
/// rename is atomic, so a reader sees the old file or the complete new one,
/// and the final file is always 600. When `chmod` exits non-zero the save
/// fails with a [FileSystemException] and the temp file is removed.
///
/// Each call creates its own uniquely named temp file, so two overlapping
/// saves to the same [file] never write to, or delete, each other's temp
/// file. The last rename wins.
///
/// Before it writes, the call removes temp files that an interrupted save
/// left in the same directory (see [staleTempAge]).
void writePrivateFile(
  File file,
  String contents, {
  @visibleForTesting Chmod? chmod,
  @visibleForTesting DateTime Function()? now,
}) {
  _removeStaleTemps(file.parent, (now ?? DateTime.now)());
  final temp = _createUniqueTemp(file);
  try {
    if (_isPosix) _restrict('600', temp.path, chmod ?? _runChmod);
    temp
      ..writeAsStringSync(contents, flush: true)
      ..renameSync(file.path);
  } on Object {
    if (temp.existsSync()) temp.deleteSync();
    rethrow;
  }
}

/// How old a leftover temp file must be before a save removes it.
///
/// A save takes milliseconds, so a temp file this old belongs to a save that
/// was interrupted. A save that runs at the same time is never touched.
@visibleForTesting
const staleTempAge = Duration(hours: 1);

/// Matches the names that [_createUniqueTemp] gives:
/// `<name>.<pid>.<8 hex digits>.tmp`.
final _tempName = RegExp(r'^.+\.\d+\.[0-9a-f]{8}\.tmp$');

/// Removes the temp files of interrupted saves from [directory].
///
/// Only regular files whose name matches [_tempName] and that were last
/// modified more than [staleTempAge] before [now] are removed. The cleanup
/// never fails a save: a file that another process removes first, or that
/// cannot be read, is skipped.
void _removeStaleTemps(Directory directory, DateTime now) {
  final cutoff = now.subtract(staleTempAge);
  final List<FileSystemEntity> entries;
  try {
    entries = directory.listSync(followLinks: false);
  } on FileSystemException {
    return;
  }
  for (final entry in entries) {
    if (entry is! File) continue;
    if (!_tempName.hasMatch(entry.uri.pathSegments.last)) continue;
    try {
      if (entry.lastModifiedSync().isBefore(cutoff)) entry.deleteSync();
    } on FileSystemException {
      continue;
    }
  }
}

final _random = Random.secure();

/// Creates a new, empty `<file>.<pid>.<random>.tmp` that no other writer
/// owns. The exclusive create fails if the name already exists, so a
/// collision picks a new name instead of taking over another file.
File _createUniqueTemp(File file) {
  for (var attempt = 0; ; attempt++) {
    final suffix = _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    final temp = File('${file.path}.$pid.$suffix.tmp');
    try {
      temp.createSync(exclusive: true);
      return temp;
    } on FileSystemException {
      if (attempt >= 9) rethrow;
    }
  }
}
