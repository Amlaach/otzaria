import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';
import 'package:otzaria/utils/file/file_picker_dialog_options.dart';

/// שומר מרכזי עבור בוררי הקבצים של מערכת ההפעלה (Windows File Dialogs / FilePicker).
///
/// ב-Windows, פתיחת דיאלוג קבצים מאפשרת גישה מלאה לסייר הקבצים, הפעלת תוכנות
/// (Open with, CMD, PowerShell), ניווט בכל הכוננים, ובריחה ממצב קיוסק.
/// לכן:
/// 1. במצב קיוסק מנוהל (`isKioskMode`) — חסום לחלוטין תמיד.
/// 2. במצב סייפר רגיל — נדרש אימות סיסמה מוקדם.
/// 3. אם אין context זמין לאימות — נחסם (Fail-Closed).
abstract final class SaferFilePicker {
  /// עקיפות לבדיקות יחידה
  @visibleForTesting
  static Future<String?> Function()? getDirectoryPathOverride;
  @visibleForTesting
  static Future<PlatformFile?> Function()? pickFileOverride;
  @visibleForTesting
  static Future<List<PlatformFile>> Function()? pickFilesOverride;
  @visibleForTesting
  static Future<String?> Function()? saveFileOverride;

  /// בוחר תיקייה ממערכת ההפעלה.
  static Future<String?> getDirectoryPath({
    BuildContext? context,
    String? dialogTitle,
    String? initialDirectory,
    bool lockParentWindow = false,
  }) async {
    if (isKioskMode) {
      UiSnack.show('פתיחת בורר קבצים חסומה במצב קיוסק');
      return null;
    }

    final effectiveContext = context ?? navigatorKey.currentContext;
    if (effectiveContext != null) {
      if (shouldRequireSaferModePassword(effectiveContext)) {
        if (!effectiveContext.mounted ||
            !await verifySaferModePassword(effectiveContext)) {
          return null;
        }
      }
    } else {
      // Fail-closed
      return null;
    }

    if (getDirectoryPathOverride != null) {
      return getDirectoryPathOverride!();
    }

    return FilePicker.getDirectoryPath(
      dialogTitle: dialogTitle,
      initialDirectory: initialDirectory,
      lockParentWindow: lockParentWindow,
      windowsOptions: kModalWindowsOptions,
      linuxOptions: kModalLinuxOptions,
    );
  }

  /// בוחר קובץ בודד ממערכת ההפעלה.
  static Future<PlatformFile?> pickFile({
    BuildContext? context,
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool lockParentWindow = false,
  }) async {
    if (isKioskMode) {
      UiSnack.show('פתיחת בורר קבצים חסומה במצב קיוסק');
      return null;
    }

    final effectiveContext = context ?? navigatorKey.currentContext;
    if (effectiveContext != null) {
      if (shouldRequireSaferModePassword(effectiveContext)) {
        if (!effectiveContext.mounted ||
            !await verifySaferModePassword(effectiveContext)) {
          return null;
        }
      }
    } else {
      // Fail-closed
      return null;
    }

    if (pickFileOverride != null) {
      return pickFileOverride!();
    }

    return FilePicker.pickFile(
      dialogTitle: dialogTitle,
      initialDirectory: initialDirectory,
      type: type,
      allowedExtensions: allowedExtensions,
      onFileLoading: onFileLoading,
      lockParentWindow: lockParentWindow,
      windowsOptions: kModalWindowsOptions,
      linuxOptions: kModalLinuxOptions,
    );
  }

  /// בוחר מספר קבצים ממערכת ההפעלה.
  static Future<List<PlatformFile>> pickFiles({
    BuildContext? context,
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool lockParentWindow = false,
  }) async {
    if (isKioskMode) {
      UiSnack.show('פתיחת בורר קבצים חסומה במצב קיוסק');
      return const [];
    }

    final effectiveContext = context ?? navigatorKey.currentContext;
    if (effectiveContext != null) {
      if (shouldRequireSaferModePassword(effectiveContext)) {
        if (!effectiveContext.mounted ||
            !await verifySaferModePassword(effectiveContext)) {
          return const [];
        }
      }
    } else {
      // Fail-closed
      return const [];
    }

    if (pickFilesOverride != null) {
      return pickFilesOverride!();
    }

    return FilePicker.pickFiles(
      dialogTitle: dialogTitle,
      initialDirectory: initialDirectory,
      type: type,
      allowedExtensions: allowedExtensions,
      onFileLoading: onFileLoading,
      lockParentWindow: lockParentWindow,
      windowsOptions: kModalWindowsOptions,
      linuxOptions: kModalLinuxOptions,
    );
  }

  /// שומר קובץ למערכת ההפעלה.
  static Future<String?> saveFile({
    BuildContext? context,
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    bool lockParentWindow = false,
  }) async {
    if (isKioskMode) {
      UiSnack.show('שמירת קבצים למערכת ההפעלה חסומה בעמדה זו');
      return null;
    }

    final effectiveContext = context ?? navigatorKey.currentContext;
    if (effectiveContext != null) {
      if (shouldRequireSaferModePassword(effectiveContext)) {
        if (!effectiveContext.mounted ||
            !await verifySaferModePassword(effectiveContext)) {
          return null;
        }
      }
    } else {
      // Fail-closed
      return null;
    }

    if (saveFileOverride != null) {
      return saveFileOverride!();
    }

    return FilePicker.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      initialDirectory: initialDirectory,
      type: type,
      allowedExtensions: allowedExtensions,
      lockParentWindow: lockParentWindow,
      windowsOptions: kModalWindowsOptions,
      linuxOptions: kModalLinuxOptions,
    );
  }
}
