import 'dart:io';

import 'package:path/path.dart' as p;

/// The file stayed locked by another handle after all retries.
class AttachedUpdateFileLocked implements Exception {
  final String path;
  const AttachedUpdateFileLocked(this.path);

  @override
  String toString() => 'AttachedUpdateFileLocked: $path';
}

/// החלפת קובץ המסד בקובץ המעודכן, עם גיבוי ושחזור.
///
/// The old file (and its SQLite side files, whose WAL must never meet the new
/// database) moves to `<file>.bak-update`, the staged file is renamed into
/// place, and the backup is deleted only after the new file was verified. A
/// `.bak-update` left by a crash is restored on the next start ([recover]).
class AttachedUpdateFileSwap {
  const AttachedUpdateFileSwap({
    this.lockRetries = 6,
    this.lockRetryDelay = const Duration(milliseconds: 250),
  });

  final int lockRetries;
  final Duration lockRetryDelay;

  static const sideSuffixes = ['-wal', '-shm', '-journal'];

  static String backupPathFor(String target) => '$target.bak-update';

  /// Next to the target so the final rename stays on one volume. The leading
  /// dot keeps folder scans from listing it as a database.
  static String stagedPathFor(String target) =>
      p.join(p.dirname(target), '.${p.basename(target)}.update-new');

  /// Download file for an uncompressed artifact, which becomes the staged
  /// file by a rename and so must share its folder.
  static String localDownloadPathFor(String target) =>
      p.join(p.dirname(target), '.${p.basename(target)}.update-download');

  Future<void> swapIn(String target, String staged) async {
    final backup = backupPathFor(target);
    await _rename(target, backup);
    try {
      for (final suffix in sideSuffixes) {
        if (await File('$target$suffix').exists()) {
          await _rename('$target$suffix', '$backup$suffix');
        }
      }
      await _rename(staged, target);
    } catch (_) {
      await restore(target);
      rethrow;
    }
  }

  /// Puts the backup back over whatever is at [target]. No-op without one.
  Future<void> restore(String target) async {
    final backup = backupPathFor(target);
    if (!await File(backup).exists()) return;
    // Without a new main file, side files still at the target are the old
    // database's own (a crash before they moved) — deleting them loses data.
    final swappedIn = await File(target).exists();
    for (final suffix in ['', ...sideSuffixes]) {
      if (suffix.isNotEmpty && !swappedIn) continue;
      final file = File('$target$suffix');
      if (await file.exists()) await _retry(file.path, file.delete);
    }
    await _rename(backup, target);
    for (final suffix in sideSuffixes) {
      if (await File('$backup$suffix').exists()) {
        await _rename('$backup$suffix', '$target$suffix');
      }
    }
  }

  Future<void> discardBackup(String target) async {
    final backup = backupPathFor(target);
    // The main file last: while it exists, [recover] still finds the rest.
    for (final suffix in [...sideSuffixes, '']) {
      final file = File('$backup$suffix');
      if (await file.exists()) await file.delete();
    }
  }

  /// Crash recovery for [target]: restores a leftover backup and removes a
  /// leftover staged file. Returns whether the backup was restored.
  Future<bool> recover(String target) async {
    var restored = false;
    if (await File(backupPathFor(target)).exists()) {
      await restore(target);
      restored = true;
    }
    final staged = File(stagedPathFor(target));
    if (await staged.exists()) await staged.delete();
    return restored;
  }

  Future<void> _rename(String from, String to) =>
      _retry(from, () => File(from).rename(to));

  /// Retries while another handle (an index or link-sync isolate that is
  /// finishing a read) still holds the file.
  Future<T> _retry<T>(String path, Future<T> Function() operation) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await operation();
      } on FileSystemException catch (e) {
        if (!isLockError(e)) rethrow;
        if (attempt >= lockRetries) throw AttachedUpdateFileLocked(path);
        await Future<void>.delayed(lockRetryDelay);
      }
    }
  }

  /// ERROR_SHARING_VIOLATION / ERROR_LOCK_VIOLATION (Windows only).
  static bool isLockError(FileSystemException e) {
    final code = e.osError?.errorCode;
    return Platform.isWindows && (code == 32 || code == 33);
  }
}
