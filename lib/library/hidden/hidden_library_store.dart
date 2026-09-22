import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

/// שמירה וטעינה של רשימת ההסתרות (issue #1448).
///
/// יושב ב-`app_preferences`, ולכן מגובה אוטומטית: `BackupService` סורק את כל
/// מפתחות ההגדרות. אין כאן box חדש ואין קובץ נפרד.
class HiddenLibraryStore {
  /// המפתחות מוצהרים ב-[SettingsRepository] ונמצאים ב-`allKeys`, כדי
  /// שהגיבוי יתפוס אותם גם במסלול הנסיגה שבו Hive אינו פתוח ונאספת רשימת
  /// המפתחות המוצהרת בלבד.
  static const String bookKeysSetting = SettingsRepository.keyHiddenBookKeys;
  static const String categoryPathsSetting =
      SettingsRepository.keyHiddenCategoryPaths;

  const HiddenLibraryStore();

  HiddenLibrarySelection load() => HiddenLibrarySelection(
    bookKeys: _readSet(bookKeysSetting),
    categoryPaths: _readSet(categoryPathsSetting),
  );

  Future<void> save(HiddenLibrarySelection selection) async {
    await Settings.setValue<String>(
      bookKeysSetting,
      jsonEncode(selection.bookKeys.toList()..sort()),
    );
    await Settings.setValue<String>(
      categoryPathsSetting,
      jsonEncode(selection.categoryPaths.toList()..sort()),
    );
  }

  /// ערך פגום או הגדרות שטרם אותחלו אינם מפילים את מסך הספרייה — במקרה כזה
  /// אין הסתרות, וזו ברירת המחדל הבטוחה: ספר מוצג ולא נעלם בשקט.
  Set<String> _readSet(String key) {
    final String? raw;
    try {
      raw = Settings.getValue<String>(key);
    } catch (error) {
      debugPrint('[HiddenLibrary] settings unavailable for $key: $error');
      return const {};
    }
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const {};
      return decoded
          .whereType<String>()
          .where((value) => value.isNotEmpty)
          .toSet();
    } catch (error) {
      debugPrint('[HiddenLibrary] corrupt value for $key: $error');
      return const {};
    }
  }
}
