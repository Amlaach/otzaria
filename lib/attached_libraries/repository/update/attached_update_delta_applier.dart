import 'dart:io';
import 'dart:isolate';

import 'package:otzaria/attached_libraries/models/attached_update_manifest.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_artifact_builder.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_fetcher.dart';
import 'package:otzaria/utils/file/zstd_patch_decoder.dart';
import 'package:otzaria/utils/file/zstd_stream_extractor.dart';

/// Stops once the output exceeds [maxOutputBytes] ([ZstdOutputLimitExceeded]):
/// a check afterwards would let a small patch fill the disk first.
typedef AttachedUpdatePatchDecoder =
    Future<void> Function(
      String patchPath,
      String basePath,
      String outputPath,
      int maxOutputBytes,
      ZstdCancelFlag? cancel,
    );

/// בונה את קובץ ה-.db מתיקון `zstd --patch-from` שהורד בחלקים: הקובץ המותקן
/// משמש prefix, והתוצאה נבדקת מול אותם גודל ו-sha256 של המסלול המלא.
class AttachedUpdateDeltaApplier {
  const AttachedUpdateDeltaApplier({this.decodePatch = _zstdPatch});

  final AttachedUpdatePatchDecoder decodePatch;

  static Future<void> _zstdPatch(
    String patch,
    String base,
    String output,
    int max,
    ZstdCancelFlag? cancel,
  ) => decodePatchToFile(
    patch,
    base,
    output,
    maxOutputBytes: max,
    cancelAddress: cancel?.address ?? 0,
  );

  /// [combinedPath] הוא התיקון המשורשר, [basePath] המסד המותקן (אינו נכתב).
  /// בהצלחה [combinedPath] נמחק; בכשל הפלט נמחק ו-[combinedPath] נשאר.
  Future<void> apply(
    AttachedUpdateArtifact artifact,
    String combinedPath,
    String basePath,
    String outputPath, {
    AttachedUpdateCancelToken? cancel,
  }) async {
    if (artifact.compression != AttachedUpdateCompression.zstdPatch) {
      throw const AttachedUpdateArtifactMismatch(
        'delta artifact must be zstd-patch',
      );
    }
    await _deleteIfExists(outputPath);
    try {
      if (!await File(basePath).exists()) {
        throw const AttachedUpdateArtifactMismatch(
          'the installed database to patch is missing',
        );
      }
      final flag = ZstdCancelFlag();
      final unsubscribe = cancel?.onCancel(flag.cancel);
      if (cancel?.isCancelled ?? false) flag.cancel();
      try {
        await decodePatch(
          combinedPath,
          basePath,
          outputPath,
          artifact.size,
          flag,
        );
      } on ZstdOutputLimitExceeded {
        throw AttachedUpdateArtifactMismatch(
          'patched output exceeds ${artifact.size}',
        );
      } on ZstdDecodeCancelled {
        throw const AttachedUpdateCancelled();
      } finally {
        unsubscribe?.call();
        flag.dispose();
      }
      final size = await File(outputPath).length();
      if (size != artifact.size) {
        throw AttachedUpdateArtifactMismatch(
          'size $size, expected ${artifact.size}',
        );
      }
      final digest = await Isolate.run(
        () => AttachedUpdateArtifactBuilder.sha256OfFile(outputPath),
      );
      if (digest != artifact.sha256) {
        throw const AttachedUpdateArtifactMismatch('sha256 differs');
      }
    } catch (_) {
      await _deleteIfExists(outputPath);
      rethrow;
    }
    await _deleteIfExists(combinedPath);
  }

  static Future<void> _deleteIfExists(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
