import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';

/// שומר מפני פתיחת תהליכים ומנהל קבצים חיצוניים במצב סייפר ובמצב קיוסק.
abstract final class SaferProcessGuard {
  /// מאפשר עקיפת הרצת התהליך עבור בדיקות יחידה.
  @visibleForTesting
  static Future<ProcessResult> Function(
    String executable,
    List<String> arguments,
  )? processRunnerOverride;

  /// פותח נתיב במנהל הקבצים של מערכת ההפעלה (Windows Explorer / Finder / xdg-open).
  ///
  /// - במצב קיוסק מנוהל (`isKioskMode`): חסום תמיד למניעת בריחה (Kiosk Breakout).
  /// - במצב סייפר רגיל: דורש אימות סיסמה דרך [verifySaferModePassword].
  /// - במצב רגיל: פותח ישירות.
  static Future<bool> openInFileManager(
    BuildContext? context,
    String path,
  ) async {
    if (path.isEmpty) return false;

    if (isKioskMode) {
      UiSnack.show('פתיחת סייר הקבצים חסומה במצב קיוסק');
      return false;
    }

    final effectiveContext = context ?? navigatorKey.currentContext;
    if (effectiveContext != null) {
      if (shouldRequireSaferModePassword(effectiveContext)) {
        if (!effectiveContext.mounted || !await verifySaferModePassword(effectiveContext)) {
          return false;
        }
      }
    } else {
      // Fail-closed: לא מאפשרים פתיחת מנהל קבצים ללא context מתאים לאימות
      return false;
    }

    final runner =
        processRunnerOverride ??
        (exe, args) => Process.run(exe, args, runInShell: false);

    try {
      if (Platform.isWindows) {
        await runner('explorer', [path]);
      } else if (Platform.isMacOS) {
        await runner('open', [path]);
      } else if (Platform.isLinux) {
        await runner('xdg-open', [path]);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// פותח את קובץ יומן השגיאות.
  ///
  /// במצב קיוסק או סייפר, במקום לפתוח את סייר הקבצים של Windows (המהווה פרצת אבטחה),
  /// מוצג דיאלוג פנימי עם תוכן הלוג ואפשרות להעתקה ללוח.
  static Future<void> openErrorLog(BuildContext context) async {
    if (isKioskMode || shouldRequireSaferModePassword(context)) {
      if (shouldRequireSaferModePassword(context)) {
        if (!await verifySaferModePassword(context)) return;
      }
      if (!context.mounted) return;
      await showErrorLogDialog(context);
      return;
    }

    // במצב חופשי — פתיחה כרגיל
    ErrorLogFile.ensureExists();
    final path = ErrorLogFile.resolvePath();
    await openInFileManager(context, path);
  }

  /// מציג את תוכן יומן השגיאות בתוך דיאלוג פנימי מעוצב.
  static Future<void> showErrorLogDialog(BuildContext context) async {
    ErrorLogFile.ensureExists();
    final file = ErrorLogFile.resolveFile();
    String content = '';
    try {
      if (await file.exists()) {
        content = await file.readAsString();
      }
    } catch (e) {
      content = 'שגיאה בקריאת קובץ היומן: $e';
    }

    if (content.trim().isEmpty) {
      content = 'קובץ יומן השגיאות ריק.';
    }

    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(FluentIcons.document_error_24_regular),
              SizedBox(width: 8),
              Text('יומן שגיאות המערכת'),
            ],
          ),
          content: SizedBox(
            width: 600,
            height: 400,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(dialogContext).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  content,
                  style: const TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: content));
                UiSnack.show('תוכן יומן השגיאות הועתק ללוח');
              },
              icon: const Icon(FluentIcons.copy_24_regular),
              label: const Text('העתק ללוח'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('סגור'),
            ),
          ],
        );
      },
    );
  }
}
