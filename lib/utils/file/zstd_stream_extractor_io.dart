/// מחלץ קבצי `.zst` בזרימה (streaming) דרך ZSTD FFI — מעבד נתחים של ~128KB
/// ישירות לדיסק, כך שצריכת ה-RAM נשארת בכמה מאות KB גם לקבצים בגודל ג'יגות.
///
/// טעינת הקובץ כולו ל-RAM (`Zstandard().decompress`) קרסה על מכשירים עם
/// 8GB RAM (DB של ~6.5GB פרוס). שיטה זו אינה חורגת מכמה מאות KB.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:otzaria/utils/file/zstd_library.dart';
import 'package:otzaria/utils/file/zstd_stream_extractor.dart';
import 'package:zstandard_native/zstandard_native_bindings.dart';

/// מחלץ את [archivePath] (קובץ `.zst`) אל [outputPath]. רץ ב-isolate נפרד
/// כדי לא לחסום את ה-UI. [onProgress] מקבל ערך 0.0–1.0.
Future<void> extractToFile(
  String archivePath,
  String outputPath, {
  void Function(double progress)? onProgress,
  int? maxOutputBytes,
}) {
  return _runWithProgress(
    onProgress,
    (port) => Isolate.run(
      () => _decompressWithLib(
        archivePath,
        outputPath,
        openZstandardLib(),
        port,
        maxOutputBytes,
      ),
    ),
  );
}

/// מאזין לעדכוני התקדמות מ-isolate ומעביר אותם הלאה.
///
/// [runInIsolate] נקראת מקומית (לא נשלחת ל-isolate); היא עצמה אחראית להפעיל
/// את [Isolate.run]. ה-isolate שולח `double` (0.0–1.0) דרך ה-[SendPort].
Future<void> _runWithProgress(
  void Function(double progress)? onProgress,
  Future<void> Function(SendPort progressPort) runInIsolate,
) async {
  final progressPort = ReceivePort();
  final sub = progressPort.listen((message) {
    if (message is double) onProgress?.call(message);
  });
  try {
    await runInIsolate(progressPort.sendPort);
  } finally {
    await sub.cancel();
    progressPort.close();
  }
}

/// נקודת כניסה לבדיקות בלבד: מריצה את החילוץ סינכרונית עם [lib] מוזרק,
/// כדי לאמת את לוגיקת ה-FFI גם בלי ה-framework של Flutter (למשל מול
/// libzstd סטנדרטי במערכת).
void decompressSyncForTest(
  String archivePath,
  String outputPath,
  DynamicLibrary lib, {
  int? maxOutputBytes,
}) => _decompressWithLib(archivePath, outputPath, lib, null, maxOutputBytes);

/// חילוץ ZST streaming דרך ZSTD FFI. בכשל מוחק את קובץ הפלט החלקי, אחרת
/// קובץ חתוך נשאר ומפיל את פתיחת ה-DB בעלייה הבאה.
void _decompressWithLib(
  String archivePath,
  String outputPath,
  DynamicLibrary dylib,
  SendPort? progressPort,
  int? maxOutputBytes,
) {
  try {
    _decompressCore(
      archivePath,
      outputPath,
      dylib,
      progressPort,
      maxOutputBytes,
    );
  } catch (_) {
    try {
      final partial = File(outputPath);
      if (partial.existsSync()) partial.deleteSync();
    } catch (_) {}
    rethrow;
  }
}

void _decompressCore(
  String archivePath,
  String outputPath,
  DynamicLibrary dylib,
  SendPort? progressPort,
  int? maxOutputBytes,
) {
  final bindings = ZstandardNativeBindings(dylib);

  final inBufSize = bindings.ZSTD_DStreamInSize();
  final outBufSize = bindings.ZSTD_DStreamOutSize();

  final dStream = bindings.ZSTD_createDStream();
  if (dStream == nullptr) throw Exception('ZSTD_createDStream נכשל');

  String zstdError(int code) =>
      bindings.ZSTD_getErrorName(code).cast<Utf8>().toDartString();

  try {
    final initRet = bindings.ZSTD_initDStream(dStream);
    if (bindings.ZSTD_isError(initRet) != 0) {
      throw Exception('ZSTD_initDStream נכשל: ${zstdError(initRet)}');
    }

    // ברירת המחדל מגבילה את חלון הדחיסה ל-128MB (windowLog=27). seforim.db.zst
    // נדחס עם `--long` ולכן נכשל עם windowTooLarge (קוד 16). 31 = חלון עד 2GB.
    final paramRet = bindings.ZSTD_DCtx_setParameter(
      dStream,
      ZSTD_dParameter.ZSTD_d_windowLogMax,
      31,
    );
    if (bindings.ZSTD_isError(paramRet) != 0) {
      throw Exception(
        'ZSTD_DCtx_setParameter(windowLogMax) נכשל: ${zstdError(paramRet)}',
      );
    }

    final inNative = malloc.allocate<Uint8>(inBufSize);
    final outNative = malloc.allocate<Uint8>(outBufSize);
    final inBuf = malloc<ZSTD_inBuffer_s>();
    final outBuf = malloc<ZSTD_outBuffer_s>();

    try {
      final inputRaf = File(archivePath).openSync();
      final outFile = File(outputPath);
      if (outFile.existsSync()) outFile.deleteSync();
      final outputRaf = outFile.openSync(mode: FileMode.writeOnly);

      final totalBytes = inputRaf.lengthSync();
      var totalRead = 0;
      var lastReported = 0.0;

      try {
        final inView = inNative.asTypedList(inBufSize);

        int lastRet = 0;
        int expectedSize = -1;
        int totalWritten = 0;
        var headerParsed = false;

        while (true) {
          final bytesRead = inputRaf.readIntoSync(inView);
          if (bytesRead == 0) break;
          totalRead += bytesRead;

          if (!headerParsed) {
            expectedSize = bindings.ZSTD_getFrameContentSize(
              inNative.cast(),
              bytesRead,
            );
            headerParsed = true;
          }

          inBuf.ref.src = inNative.cast();
          inBuf.ref.size = bytesRead;
          inBuf.ref.pos = 0;

          while (inBuf.ref.pos < inBuf.ref.size) {
            outBuf.ref.dst = outNative.cast();
            outBuf.ref.size = outBufSize;
            outBuf.ref.pos = 0;

            lastRet = bindings.ZSTD_decompressStream(dStream, outBuf, inBuf);

            if (bindings.ZSTD_isError(lastRet) != 0) {
              throw Exception(
                'שגיאת ZSTD בחילוץ: ${zstdError(lastRet)} (קוד: $lastRet)',
              );
            }

            if (maxOutputBytes != null &&
                totalWritten + outBuf.ref.pos > maxOutputBytes) {
              throw ZstdOutputLimitExceeded(maxOutputBytes);
            }
            if (outBuf.ref.pos > 0) {
              outputRaf.writeFromSync(outNative.asTypedList(outBuf.ref.pos));
              totalWritten += outBuf.ref.pos;
            }
          }

          if (progressPort != null && totalBytes > 0) {
            final progress = totalRead / totalBytes;
            if (progress - lastReported >= 0.01) {
              lastReported = progress;
              progressPort.send(progress);
            }
          }
        }

        if (lastRet != 0) {
          throw Exception(
            'קובץ ה-ZST קטוע או פגום: ה-frame לא הושלם (נותרו $lastRet bytes)',
          );
        }

        // flush מפורש כדי לתפוס דיסק מלא (ENOSPC) שנבלע ב-page cache.
        outputRaf.flushSync();

        if (expectedSize >= 0 && totalWritten != expectedSize) {
          throw Exception(
            'החילוץ לא הושלם: נכתבו $totalWritten מתוך $expectedSize bytes. '
            'ככל הנראה אזל מקום האחסון.',
          );
        }
      } finally {
        inputRaf.closeSync();
        outputRaf.closeSync();
      }
    } finally {
      malloc.free(inNative);
      malloc.free(outNative);
      malloc.free(inBuf);
      malloc.free(outBuf);
    }
  } finally {
    bindings.ZSTD_freeDStream(dStream);
  }
}
