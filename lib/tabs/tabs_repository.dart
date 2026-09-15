import 'dart:async';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;
import 'package:otzaria/core/windowing/shared_hive_store.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/utils/file/hive_utils.dart';
import 'package:flutter/foundation.dart';

class TabsRepository {
  static const String boxName = 'tabs';
  static const String _tabsBoxKey = 'key-tabs';
  static const String _currentTabKey = 'key-current-tab';
  static const String _legacySplitModeKey = 'key-side-by-side-mode';

  /// המשבצת שקובעת את מפתחות הסשן, או null בחלון הראשון.
  int? get _windowSlot =>
      WindowRole.isSecondary ? WindowBus.instance.slot : null;

  /// המפתח שהחלון הזה **כותב** אליו.
  ///
  /// ⚠️ חלון משני כותב תחת מפתח משלו, ב-box של הבעלים. קודם לכן הוא כתב
  /// ל-`Hive.box('tabs')` — כלומר לשורש ה-Hive הפרטי שלו, שנוצר מחדש בכל
  /// הפעלה ואינו נקרא אף פעם. התוצאה: הכרטיסיות שלו לא נשמרו כלל, וספר
  /// שהועבר אליו נעלם משני החלונות אחרי סגירת התוכנה.
  String get _sessionTabsKey =>
      SharedHiveStore.tabsKeyForWindow(_windowSlot, _tabsBoxKey);

  String get _sessionCurrentKey =>
      SharedHiveStore.tabsKeyForWindow(_windowSlot, _currentTabKey);

  /// האם החלון הזה יכול לשמור.
  ///
  /// ⚠️ חלון משני בלי משבצת באפיק אינו שומר, ובשום מצב אינו נופל למפתח של
  /// החלון הראשון — זו הייתה דריסת הכרטיסיות שלו.
  bool get _canPersist =>
      !WindowRole.isSecondary || WindowBus.instance.slot != null;

  /// הטאבים הפתוחים והטאב הפעיל, גולמיים, לגיבוי.
  ///
  /// גולמי (ה-JSON כפי שנשמר) ולא [OpenedTab]: טאב שאינו נטען במחשב היעד
  /// (ספר חסר) מדולג בטעינה על ידי [loadTabs], ואין להשמיט אותו מהגיבוי מראש.
  ///
  /// ⚠️ תמיד הסשן של החלון **הראשון**, גם כשהגיבוי מופעל מחלון משני: גיבוי
  /// הוא של התוכנה ולא של החלון, ומה שנטען בהפעלה קרה הוא המפתח ההיסטורי.
  Future<Map<String, dynamic>> exportRaw() async {
    final tabs = await SharedHiveStore.instance.read(boxName, _tabsBoxKey);
    final current = await SharedHiveStore.instance.read(
      boxName,
      _currentTabKey,
    );
    // ⚠️ "לא הצלחנו לשאול" אינו "אין כרטיסיות". בלי הבדיקה גיבוי שנוצר
    // בחלון משני בזמן שהבעלים עסוק כתב `openTabs: {tabs: []}` בלי שגיאה,
    // ושחזור ממנו סגר את כל הכרטיסיות של המשתמש.
    if (!tabs.authoritative || !current.authoritative) {
      throw SharedHiveUnavailable.report(
        SharedHiveKey(boxName, _tabsBoxKey),
        (tabs.authoritative ? current.reason : tabs.reason)!,
      );
    }
    return {
      'tabs': tabs.value ?? <dynamic>[],
      'currentTab': current.value ?? 0,
    };
  }

  /// כתיבת הטאבים מגיבוי, בדריסת הטאבים השמורים.
  Future<void> importRaw(Map<String, dynamic> data) async {
    await SharedHiveStore.instance.write(
      boxName,
      _tabsBoxKey,
      data['tabs'] ?? <dynamic>[],
    );
    await SharedHiveStore.instance.write(
      boxName,
      _currentTabKey,
      data['currentTab'] ?? 0,
    );
  }

  int _resolvePersistedCurrentTabIndex(
    Map<int, int> persistedIndexByOriginalIndex,
    int currentTabIndex,
    int originalTabsCount,
  ) {
    if (persistedIndexByOriginalIndex.isEmpty) return 0;

    final directMatch = persistedIndexByOriginalIndex[currentTabIndex];
    if (directMatch != null) return directMatch;

    for (var i = currentTabIndex - 1; i >= 0; i--) {
      final previousMatch = persistedIndexByOriginalIndex[i];
      if (previousMatch != null) return previousMatch;
    }

    for (var i = currentTabIndex + 1; i < originalTabsCount; i++) {
      final nextMatch = persistedIndexByOriginalIndex[i];
      if (nextMatch != null) return nextMatch;
    }

    return 0;
  }

  /// ממפה נתיבי קבצים שמורים של טאבים מתיקיית הספרייה הישנה [fromDir] לחדשה
  /// [toDir], כדי שספרי PDF/DOCX פתוחים ייטענו מהמיקום החדש לאחר רענון התוכנה.
  /// משכתב את שדות 'path' ו-'filePath' בכל עומק (כולל ה-book המקונן).
  Future<void> remapBookPaths(String fromDir, String toDir) async {
    // ⚠️ הסשן של החלון הראשון, גם כשההעברה מופעלת מחלון משני: העברת
    // הספרייה היא פעולה של התוכנה, וזה הסשן שנטען בהפעלה קרה.
    final stored = await SharedHiveStore.instance.read(boxName, _tabsBoxKey);
    final rawTabs = stored.value;
    if (rawTabs is! List) return;
    var changed = false;
    final remapped = rawTabs
        .map((e) => _remapNode(e, fromDir, toDir, () => changed = true))
        .toList();
    if (changed) {
      await SharedHiveStore.instance.write(boxName, _tabsBoxKey, remapped);
    }
  }

  /// ממפה נתיבי קבצים של טאבים פתוחים *בזיכרון* מ-[fromDir] ל-[toDir].
  /// טאב שהנתיב שלו לא משתנה מוחזר כאובייקט המקורי (ללא בנייה מחדש);
  /// טאב ששונה נבנה מחדש דרך toJson→fromJson עם הנתיב החדש.
  /// נדרש בנוסף ל-[remapBookPaths]: שמירה ל-Hive בלבד נדרסת ע"י שמירת
  /// הטאבים שבזיכרון בעת dispose, ולכן ספר PDF היה נטען מהנתיב הישן.
  List<OpenedTab> remapTabsInMemory(
    List<OpenedTab> tabs,
    String fromDir,
    String toDir,
  ) {
    return tabs.map((tab) {
      var changed = false;
      final remappedJson = _remapNode(
        tab.toJson(),
        fromDir,
        toDir,
        () => changed = true,
      );
      if (!changed) return tab;
      return OpenedTab.fromJson(castMap(remappedJson));
    }).toList();
  }

  dynamic _remapNode(
    dynamic node,
    String fromDir,
    String toDir,
    void Function() onChange,
  ) {
    if (node is Map) {
      final result = <String, dynamic>{};
      node.forEach((key, value) {
        final k = key.toString();
        if ((k == 'path' || k == 'filePath') &&
            value is String &&
            value.isNotEmpty &&
            (p.equals(fromDir, value) || p.isWithin(fromDir, value))) {
          result[k] = p.join(toDir, p.relative(value, from: fromDir));
          onChange();
        } else {
          result[k] = _remapNode(value, fromDir, toDir, onChange);
        }
      });
      return result;
    }
    if (node is List) {
      return node.map((e) => _remapNode(e, fromDir, toDir, onChange)).toList();
    }
    return node;
  }

  /// הטאבים כפי שנשמרו. פיצול מקונן מגרסה קודמת מנורמל אצל הקורא דרך
  /// [flattenRestoredSplits], יחד עם האינדקס הפעיל — שהנירמול מזיז.
  ///
  /// ⚠️ **חלון משני אינו משחזר כרטיסיות, ומחזיר רשימה ריקה.** הוא נפתח עם
  /// הכרטיסיה שהועברה אליו, וזה מה שהמשתמש ביקש לראות. מפתח הסשן שלו קיים
  /// כדי **לשמור** — כדי שכיבוי התוכנה לא יאבד את מה שפתוח בו — ולא כדי
  /// שחלון חדש יקבל את השרידים של קודמו באותה משבצת.
  List<OpenedTab> loadTabs() {
    if (WindowRole.isSecondary) return const [];
    try {
      final box = Hive.box('tabs');
      unawaited(box.delete(_legacySplitModeKey));
      final rawTabs = box.get(_tabsBoxKey, defaultValue: []) as List;
      final tabs = <OpenedTab>[];
      for (final e in rawTabs) {
        try {
          tabs.add(OpenedTab.fromJson(castMap(e)));
        } catch (tabError) {
          debugPrint('⚠️ Skipping tab that failed to restore: $tabError');
        }
      }
      return tabs;
    } catch (e) {
      debugPrint('⚠️ Error loading tabs from disk: $e');
      return [];
    }
  }

  int loadCurrentTabIndex() {
    if (WindowRole.isSecondary) return 0;
    return Hive.box('tabs').get(_currentTabKey, defaultValue: 0);
  }

  Future<void> saveTabs(List<OpenedTab> tabs, int currentTabIndex) async {
    if (!_canPersist) {
      debugPrint('⚠️ saveTabs: אין משבצת אפיק לחלון הזה — הסשן לא נשמר');
      return;
    }
    final persistedTabs = <OpenedTab>[];
    final persistedIndexByOriginalIndex = <int, int>{};

    for (var i = 0; i < tabs.length; i++) {
      persistedIndexByOriginalIndex[i] = persistedTabs.length;
      persistedTabs.add(tabs[i]);
    }

    final persistedCurrentIndex = _resolvePersistedCurrentTabIndex(
      persistedIndexByOriginalIndex,
      currentTabIndex,
      tabs.length,
    );
    await SharedHiveStore.instance.write(
      boxName,
      _sessionTabsKey,
      persistedTabs.map((tab) => tab.toJson()).toList(),
    );
    await SharedHiveStore.instance.write(
      boxName,
      _sessionCurrentKey,
      persistedCurrentIndex,
    );
    if (_windowSlot == null) {
      await Hive.box(boxName).delete(_legacySplitModeKey);
    }
  }

  /// מוחק את סשן החלון הזה.
  ///
  /// ⚠️ נקרא כשהמשתמש **סוגר** חלון שאינו האחרון, אחרי ה-flush. בלי המחיקה
  /// הסשן היה נשאר על הדיסק, ו-[adoptOrphanWindowSessions] היה מחזיר
  /// בהפעלה הבאה כרטיסיות שהמשתמש סגר במכוון. מה שכן צריך לשרוד סגירה הוא
  /// `Ctrl+Shift+T`, והוא נשען על המנוע שנשאר חי בזיכרון ולא על הדיסק.
  ///
  /// ⚠️ **חל גם על החלון הראשון**, וההצדקה זהה: הוא נסגר במכוון בעוד
  /// חלונות אחרים נשארו פתוחים, ולכן הכרטיסיות שלו אינן "פתוחות" יותר.
  /// מפתח הסשן שלו הוא ההיסטורי, ולכן הוא נכתב כרשימה ריקה ואינו נמחק:
  /// `loadTabs` ו-`NavigationBloc` קוראים אותו בהפעלה קרה, ומפתח חסר אינו
  /// מבחין בין "אין כרטיסיות" לבין "טרם נשמר".
  Future<void> discardWindowSession() async {
    try {
      if (_windowSlot == null) {
        await SharedHiveStore.instance.write(
          boxName,
          _sessionTabsKey,
          const [],
        );
        await SharedHiveStore.instance.write(boxName, _sessionCurrentKey, 0);
        return;
      }
      await SharedHiveStore.instance.delete(boxName, _sessionTabsKey);
      await SharedHiveStore.instance.delete(boxName, _sessionCurrentKey);
    } catch (e) {
      debugPrint('⚠️ discardWindowSession failed: $e');
    }
  }

  /// מצרף לחלון הראשון סשנים של חלונות שלא ייפתחו שוב.
  ///
  /// ⚠️ בהפעלה קרה נפתח חלון אחד בלבד, ולכן כרטיסיות שנשמרו תחת מפתח של
  /// חלון משני לא ייטענו על ידי אף אחד. מפתח כזה נשאר רק כשהתהליך מת בלי
  /// שהחלון עבר סגירה מסודרת — קריסה, כיבוי מערכת, "סיים משימה" — ולכן
  /// **הן פתוחות מבחינת המשתמש** ואין להשמיט אותן.
  ///
  /// רץ **פעם אחת בהפעלה, לפני שה-blocs נבנים**, וכותב לתוך המפתח
  /// ההיסטורי. שני קוראים שונים ([loadTabs] ו-`NavigationBloc`) קוראים
  /// אחריו ורואים בדיוק אותו דבר.
  ///
  /// מחזיר את מספר הכרטיסיות שאומצו.
  static Future<int> adoptOrphanWindowSessions() async {
    if (WindowRole.isSecondary) return 0;
    try {
      final box = Hive.box<dynamic>(boxName);
      final orphanKeys = box.keys
          .whereType<String>()
          .where((k) => k.startsWith('$_tabsBoxKey-window-'))
          .toList();
      if (orphanKeys.isEmpty) return 0;

      final adopted = <dynamic>[];
      for (final key in orphanKeys) {
        final raw = box.get(key);
        if (raw is List) adopted.addAll(raw);
        await box.delete(key);
        await box.delete(
          key.replaceFirst(_tabsBoxKey, _currentTabKey),
        );
      }
      if (adopted.isEmpty) return 0;

      final own = box.get(_tabsBoxKey, defaultValue: <dynamic>[]) as List;
      await box.put(_tabsBoxKey, [...own, ...adopted]);
      debugPrint(
        'אומצו ${adopted.length} כרטיסיות מ-${orphanKeys.length} '
        'חלונות שנסגרו בלי סגירה מסודרת',
      );
      return adopted.length;
    } catch (e) {
      debugPrint('⚠️ adoptOrphanWindowSessions failed: $e');
      return 0;
    }
  }

  /// שומר רק את אינדקס הטאב הנוכחי, בלי לקודד מחדש את כל הטאבים.
  ///
  /// מיועד למעבר בין טאבים, שבו רשימת הטאבים עצמה לא משתנה — אין טעם
  /// להריץ `toJson()` על כל הטאבים בכל מעבר. מבצע רק מיפוי אינדקסים קל
  /// ושומר ערך בודד. הכתיבה ל-Hive אסינכרונית ואינה חוסמת את ה-UI.
  Future<void> saveCurrentTabIndex(
    List<OpenedTab> tabs,
    int currentTabIndex,
  ) async {
    if (!_canPersist) return;
    final persistedIndexByOriginalIndex = <int, int>{};
    var persistedCount = 0;
    for (var i = 0; i < tabs.length; i++) {
      persistedIndexByOriginalIndex[i] = persistedCount;
      persistedCount++;
    }

    final persistedCurrentIndex = _resolvePersistedCurrentTabIndex(
      persistedIndexByOriginalIndex,
      currentTabIndex,
      tabs.length,
    );

    await SharedHiveStore.instance.write(
      boxName,
      _sessionCurrentKey,
      persistedCurrentIndex,
    );
  }
}
