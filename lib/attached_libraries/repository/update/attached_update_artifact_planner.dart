import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:otzaria/attached_libraries/models/attached_update_manifest.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_artifact_builder.dart';

/// תקרת החלון של zstd (2^31): prefix גדול מזה אינו ניתן להצגה לפענוח.
const int kMaxDeltaBaseBytes = 2 * 1024 * 1024 * 1024;

/// מה יורד בפועל: [delta] לא null ⇒ [artifact] הוא תיקון שיוחל על המסד המותקן.
class AttachedUpdatePlan {
  const AttachedUpdatePlan(this.artifact, {this.delta});

  final AttachedUpdateArtifact artifact;
  final AttachedUpdateDelta? delta;

  bool get isDelta => delta != null;
}

/// בוחר בין הקובץ המלא לתיקון דלתא. כל ספק — מידות, גרסה, sha256 של הקובץ
/// המותקן, מכונה 32 סיביות — מחזיר את הקובץ המלא בלי להציג שגיאה למשתמש.
class AttachedUpdateArtifactPlanner {
  const AttachedUpdateArtifactPlanner({
    this.hashFile = _sha256InIsolate,
    this.pointerSize,
    this.maxBaseBytes = kMaxDeltaBaseBytes,
  });

  /// sha256 של הקובץ המותקן; ברירת המחדל רצה ב-isolate.
  final Future<String> Function(String path) hashFile;

  /// דריסה לבדיקות של רוחב המצביע (8 = 64 סיביות).
  final int? pointerSize;

  /// גודל הקובץ המותקן שעדיין אפשר להשתמש בו כ-prefix.
  final int maxBaseBytes;

  static Future<String> _sha256InIsolate(String path) =>
      Isolate.run(() => AttachedUpdateArtifactBuilder.sha256OfFile(path));

  // המסד נשאר זהה בין בדיקה להתקנה; חישוב מחדש היה קורא גיגה-בתים שוב.
  static final _hashCache =
      <String, ({int size, int mtimeMs, String digest})>{};

  static void clearCacheForTesting() => _hashCache.clear();

  Future<AttachedUpdatePlan> plan(
    AttachedUpdateManifest manifest, {
    required String installedPath,
    required int installedDbVersion,
  }) async {
    final full = AttachedUpdatePlan(manifest.full);
    try {
      if ((pointerSize ?? sizeOf<Pointer>()) != 8) return full;
      final candidates =
          manifest.deltas
              .where(
                (d) =>
                    d.fromDbVersion == installedDbVersion &&
                    d.artifact.compression ==
                        AttachedUpdateCompression.zstdPatch &&
                    d.artifact.compressedSize < manifest.full.compressedSize,
              )
              .toList()
            ..sort(
              (a, b) => a.artifact.compressedSize.compareTo(
                b.artifact.compressedSize,
              ),
            );
      if (candidates.isEmpty) return full;
      final stat = await FileStat.stat(installedPath);
      if (stat.type != FileSystemEntityType.file ||
          stat.size <= 0 ||
          stat.size > maxBaseBytes) {
        return full;
      }
      final digest = await _installedDigest(installedPath, stat);
      for (final delta in candidates) {
        if (delta.fromSha256 == digest) {
          return AttachedUpdatePlan(delta.artifact, delta: delta);
        }
      }
      return full;
    } catch (e) {
      debugPrint('[AttachedUpdates] delta planning failed: $e');
      return full;
    }
  }

  Future<String> _installedDigest(String path, FileStat stat) async {
    final mtimeMs = stat.modified.millisecondsSinceEpoch;
    final cached = _hashCache[path];
    if (cached != null &&
        cached.size == stat.size &&
        cached.mtimeMs == mtimeMs) {
      return cached.digest;
    }
    final digest = await hashFile(path);
    _hashCache[path] = (size: stat.size, mtimeMs: mtimeMs, digest: digest);
    return digest;
  }
}
