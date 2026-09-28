import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// הפורט של כל מדפסת מותקנת ב-Windows, לפי שמה. חבילת `printing` אינה חושפת
/// את הפורט, והוא הסימן האמין לזיהוי מדפסת-לקובץ. לעולם לא זורק; בכשל או
/// בפלטפורמה אחרת מחזיר מפה ריקה והסינון נופל לזיהוי לפי שם.
Map<String, String> windowsPrinterPorts() {
  if (!Platform.isWindows) return const {};
  try {
    return _enumeratePorts();
  } catch (_) {
    return const {};
  }
}

Map<String, String> _enumeratePorts() {
  const flags = PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS;
  const level = 2;
  final needed = calloc<Uint32>();
  final returned = calloc<Uint32>();
  try {
    EnumPrinters(flags, null, level, null, 0, needed, returned);
    if (needed.value == 0) return const {};
    final buffer = calloc<Uint8>(needed.value);
    try {
      final ok = EnumPrinters(
        flags,
        null,
        level,
        buffer,
        needed.value,
        needed,
        returned,
      ).value;
      if (!ok) return const {};
      final infos = buffer.cast<PRINTER_INFO_2>();
      final ports = <String, String>{};
      for (var i = 0; i < returned.value; i++) {
        final info = infos[i];
        if (info.pPrinterName.address == 0) continue;
        final name = info.pPrinterName.toDartString();
        final port = info.pPortName.address == 0
            ? ''
            : info.pPortName.toDartString();
        ports[name] = port;
      }
      return ports;
    } finally {
      calloc.free(buffer);
    }
  } finally {
    calloc.free(needed);
    calloc.free(returned);
  }
}
