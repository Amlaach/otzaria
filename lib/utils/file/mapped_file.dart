/// מיפוי קובץ לזיכרון לקריאה בלבד, כדי להעביר ל-FFI מצביע רציף לקובץ שלם
/// בלי לקרוא אותו ל-heap (קריאת מסד של 2GB ל-RAM מפילה מכונות של 8GB).
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// המיפוי נכשל — הקובץ חסר, ריק, או שה-OS סירב.
class MappedFileException implements Exception {
  final String message;
  const MappedFileException(this.message);

  @override
  String toString() => 'MappedFileException: $message';
}

/// תצוגת קריאה-בלבד של קובץ בזיכרון. חובה לשחרר ב-[unmap]; על Windows מיפוי
/// שנשאר פתוח נועל את הקובץ ומונע את החלפתו.
class MappedFile {
  MappedFile._(this.data, this.length, this._release);

  /// תחילת הקובץ בזיכרון.
  final Pointer<Uint8> data;

  /// אורך הקובץ בבתים.
  final int length;

  final void Function() _release;
  var _released = false;

  void unmap() {
    if (_released) return;
    _released = true;
    _release();
  }

  /// ממפה את [path], מריץ את [body] ומשחרר תמיד. ערך ההחזרה חייב לא להחזיק
  /// את [MappedFile.data] אחרי שה-[body] הסתיים.
  static T use<T>(String path, T Function(MappedFile file) body) {
    final mapped = open(path);
    try {
      return body(mapped);
    } finally {
      mapped.unmap();
    }
  }

  static MappedFile open(String path) {
    final file = File(path);
    final int length;
    try {
      length = file.lengthSync();
    } on FileSystemException catch (e) {
      throw MappedFileException('cannot stat $path: ${e.osError?.message}');
    }
    if (length <= 0) throw MappedFileException('$path is empty');
    return Platform.isWindows
        ? _openWindows(path, length)
        : _openPosix(path, length);
  }

  static MappedFile _openWindows(String path, int length) {
    final name = path.toNativeUtf16();
    try {
      // בלי FILE_SHARE_WRITE: קיצור הקובץ בזמן שהוא ממופה מפיל את התהליך
      // ב-EXCEPTION_IN_PAGE_ERROR שאי אפשר לתפוס. כותב קיים מכשיל את הפתיחה,
      // וזה בסך הכול מחזיר את העדכון לקובץ המלא.
      final handle = _createFileW(
        name,
        _genericRead,
        _fileShareRead | _fileShareDelete,
        nullptr,
        _openExisting,
        _fileAttributeNormal,
        0,
      );
      if (handle == _invalidHandle) {
        throw MappedFileException('CreateFileW failed for $path');
      }
      final mapping = _createFileMappingW(
        handle,
        nullptr,
        _pageReadonly,
        0,
        0,
        nullptr,
      );
      if (mapping == 0) {
        _closeHandle(handle);
        throw MappedFileException('CreateFileMappingW failed for $path');
      }
      final view = _mapViewOfFile(mapping, _fileMapRead, 0, 0, 0);
      if (view == nullptr) {
        _closeHandle(mapping);
        _closeHandle(handle);
        throw MappedFileException('MapViewOfFile failed for $path');
      }
      return MappedFile._(view.cast<Uint8>(), length, () {
        _unmapViewOfFile(view);
        _closeHandle(mapping);
        _closeHandle(handle);
      });
    } finally {
      malloc.free(name);
    }
  }

  static MappedFile _openPosix(String path, int length) {
    final name = path.toNativeUtf8();
    try {
      final fd = _open(name, _oRdonly);
      if (fd < 0) throw MappedFileException('open failed for $path');
      final view = _mmap(nullptr, length, _protRead, _mapPrivate, fd, 0);
      // הזיכרון נשאר ממופה גם אחרי סגירת ה-fd, ואין טעם להחזיק אותו פתוח.
      _close(fd);
      if (view.address == -1 || view == nullptr) {
        throw MappedFileException('mmap failed for $path');
      }
      return MappedFile._(
        view.cast<Uint8>(),
        length,
        () => _munmap(view, length),
      );
    } finally {
      malloc.free(name);
    }
  }
}

const _genericRead = 0x80000000;
const _fileShareRead = 0x00000001;
const _fileShareDelete = 0x00000004;
const _openExisting = 3;
const _fileAttributeNormal = 0x00000080;
const _pageReadonly = 0x02;
const _fileMapRead = 0x04;
const _invalidHandle = -1;

const _oRdonly = 0;
const _protRead = 1;
const _mapPrivate = 2;

final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

final _createFileW = _kernel32
    .lookupFunction<
      IntPtr Function(
        Pointer<Utf16>,
        Uint32,
        Uint32,
        Pointer<Void>,
        Uint32,
        Uint32,
        IntPtr,
      ),
      int Function(
        Pointer<Utf16>,
        int,
        int,
        Pointer<Void>,
        int,
        int,
        int,
      )
    >('CreateFileW');

final _createFileMappingW = _kernel32
    .lookupFunction<
      IntPtr Function(
        IntPtr,
        Pointer<Void>,
        Uint32,
        Uint32,
        Uint32,
        Pointer<Utf16>,
      ),
      int Function(int, Pointer<Void>, int, int, int, Pointer<Utf16>)
    >('CreateFileMappingW');

final _mapViewOfFile = _kernel32
    .lookupFunction<
      Pointer<Void> Function(IntPtr, Uint32, Uint32, Uint32, IntPtr),
      Pointer<Void> Function(int, int, int, int, int)
    >('MapViewOfFile');

final _unmapViewOfFile = _kernel32
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'UnmapViewOfFile',
    );

final _closeHandle = _kernel32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');

final DynamicLibrary _libc = DynamicLibrary.process();

final _open = _libc
    .lookupFunction<
      Int32 Function(Pointer<Utf8>, Int32),
      int Function(Pointer<Utf8>, int)
    >('open');

final _close = _libc.lookupFunction<Int32 Function(Int32), int Function(int)>(
  'close',
);

final _mmap = _libc
    .lookupFunction<
      Pointer<Void> Function(Pointer<Void>, IntPtr, Int32, Int32, Int32, Int64),
      Pointer<Void> Function(Pointer<Void>, int, int, int, int, int)
    >('mmap');

final _munmap = _libc
    .lookupFunction<
      Int32 Function(Pointer<Void>, IntPtr),
      int Function(Pointer<Void>, int)
    >('munmap');
