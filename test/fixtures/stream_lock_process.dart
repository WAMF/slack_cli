import 'dart:convert';
import 'dart:io';

import 'package:dart_slack/src/cli/stream_lock.dart';

Future<void> main(List<String> args) async {
  final lock = StreamLock.acquire(directory: Directory(args.single));
  stdout.writeln(lock == null ? 'busy' : 'acquired');
  await stdout.flush();
  if (lock == null) return;
  try {
    await stdin.transform(utf8.decoder).transform(const LineSplitter()).first;
  } finally {
    lock.close();
  }
}
