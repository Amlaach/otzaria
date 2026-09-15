import 'package:flutter/foundation.dart';
import 'package:otzaria/core/windowing/shared_hive_store.dart';
import 'package:otzaria/utils/file/hive_utils.dart';

/// Generic repository for managing lists of objects in Hive.
/// T must have `fromJson(Map<String, dynamic>)` and `toJson()` methods.
///
/// ## הגישה עוברת דרך [SharedHiveStore] ולא ישירות ל-`Hive.box`
///
/// היסטוריה, סימניות ושולחנות עבודה משותפים לכל חלונות אוצריא, אבל
/// `hive_ce` נועל את קובצי ה-`.lock` בלעדית ולכן כל חלון פותח קבצים משלו.
/// ה-store מנתב את המאגרים האלה לחלון הראשון, שהוא היחיד שפתח את הקבצים
/// שבשורש הנתונים האמיתי. כל שאר ה-boxes נשארים מקומיים ועוברים דרכו ללא
/// שינוי.
///
/// ## שני נתיבים, ורק אחד מהם כותב
///
/// [load] סובלני לרשומה פגומה (היא מדולגת) אבל **לא** לקריאה שלא הצליחה:
/// שם הוא זורק, כי "לא ידוע" אינו "ריק". [mutate] הוא נתיב הכתיבה היחיד
/// למאגר משותף, והוא מחיל את השינוי על הרשימה **הטרייה** של הבעלים ולא על
/// עותק שבזיכרון.
///
/// ⚠️ ההבחנה אינה סטייל. קודם לכן ה-bloc החזיק עותק, חישב ממנו רשימה
/// חדשה, וכתב אותה במלואה — ולכן כל חלון מחק ברציפות את מה שהאחר הוסיף,
/// גם בלי שום מרוץ. `mutate` הוא מה שמונע זאת.
class HiveListRepository<T> {
  final String boxName;
  final String key;
  final T Function(Map<String, dynamic>) fromJson;
  final Map<String, dynamic> Function(T) toJson;

  HiveListRepository({
    required this.boxName,
    required this.key,
    required this.fromJson,
    required this.toJson,
  });

  /// כמה פעמים לנסות מחדש כשחלון אחר כתב בין הקריאה לכתיבה.
  ///
  /// ההתנגשות נדירה — הבעלים משדר כל שינוי ולכן העותקים מתעדכנים — ושני
  /// ניסיונות נוספים מכסים גם שני חלונות שכותבים באותו רגע.
  static const int _maxAttempts = 3;

  /// אות שהרשימה הזו שונתה בחלון אחר.
  ///
  /// ⚠️ מסונן ליוזם אצל ה-store: כתיבה שהחלון הזה עשה אינה מחזירה אות,
  /// אחרת כל שמירה הייתה גוררת טעינה מחדש.
  Stream<void> get remoteChanges => SharedHiveStore.instance.changes.where(
    (changed) => changed.box == boxName && changed.key == key,
  );

  /// טוען את הרשימה.
  ///
  /// זורק [SharedHiveUnavailable] כשלא הצלחנו לשאול את הבעלים. ⚠️ הבחנה
  /// הכרחית: החזרת `[]` במקרה הזה הופכת "לא ידוע" ל"ריק", וגיבוי שנוצר
  /// בחלון משני בזמן שהבעלים עסוק נכתב כגיבוי ריק **תקין** — ושחזור ממנו
  /// מוחק את הנתונים.
  ///
  /// כשל קריאה מקומי (Hive פגום, box שאינו פתוח) כן מחזיר `[]`: הנתונים על
  /// הדיסק נשארים שלמים, נתיב הכתיבה היחיד ([mutate]) חוסם בעצמו, ותצוגה
  /// ריקה עדיפה על מסך שבור.
  Future<List<T>> load() async {
    final SharedHiveValue snapshot;
    try {
      snapshot = await SharedHiveStore.instance.read(boxName, key);
    } on SharedHiveReadFailed catch (e) {
      debugPrint('⚠️ HiveListRepository.load($boxName/$key) failed: $e');
      return [];
    }
    if (!snapshot.authoritative) {
      throw SharedHiveUnavailable.report(
        SharedHiveKey(boxName, key),
        snapshot.reason!,
      );
    }
    return _decode(snapshot.asList).items;
  }

  /// מחיל [apply] על הרשימה הטרייה ושומר את התוצאה. מחזיר את מה שנשמר.
  ///
  /// זורק [SharedHiveUnavailable] כשהבעלים לא ענה — כלומר אין על מה לבסס
  /// כתיבה, ועדיף להודיע למשתמש מלכתוב רשימה שאינה מבוססת על כלום.
  /// [SharedHiveConflict] אחרי [_maxAttempts] ניסיונות.
  ///
  /// ⚠️ [apply] נקרא שוב בכל ניסיון, ולכן הוא חייב להיות **טהור**: לחשב
  /// מהרשימה שקיבל ולא מ-state חיצוני, ולא לגרום לתופעות לוואי.
  Future<List<T>> mutate(List<T> Function(List<T> current) apply) async {
    var attempt = 0;
    while (true) {
      final snapshot = await SharedHiveStore.instance.read(boxName, key);
      if (!snapshot.authoritative) {
        throw SharedHiveUnavailable.report(
          SharedHiveKey(boxName, key),
          snapshot.reason!,
        );
      }
      final decoded = _decode(snapshot.asList);
      final next = apply(decoded.items);
      try {
        await SharedHiveStore.instance.write(
          boxName,
          key,
          // ⚠️ רשומות שלא נפענחו נשמרות. הן אינן מוצגות (הן מדולגות
          // ב-[load]), אבל כתיבה שמשמיטה אותן מוחקת נתונים של המשתמש
          // בגלל באג פענוח — וזה בדיוק מה שאסור.
          [...next.map(toJson), ...decoded.undecodable],
          ifRevision: snapshot.revision,
        );
        return next;
      } on SharedHiveConflict {
        if (++attempt >= _maxAttempts) rethrow;
        debugPrint(
          'HiveListRepository($boxName/$key): גרסה התקדמה, ניסיון $attempt',
        );
      }
    }
  }

  /// כתיבת הרשימה במלואה, בלי מיזוג ובלי בדיקת גרסה.
  ///
  /// ⚠️ **דריסה מוחלטת.** שני שימושים מוצדקים בלבד: מאגר שאינו משותף (תור
  /// דיווחים), ושחזור מגיבוי — שם הכוונה היא בדיוק להחליף את מה שיש. לכל
  /// שינוי אחר במאגר משותף השתמש ב-[mutate]: כתיבת רשימה שלמה היא בדיוק
  /// מה שמוחק את מה שחלון אחר הוסיף.
  Future<void> overwrite(List<T> items) async {
    await SharedHiveStore.instance.write(
      boxName,
      key,
      items.map(toJson).toList(),
    );
  }

  /// Clear the list
  ///
  /// דריסה מכוונת ובלי בדיקת גרסה: "מחק הכול" פירושו הכול, כולל מה שחלון
  /// אחר הוסיף בשנייה האחרונה.
  Future<void> clear() async {
    await SharedHiveStore.instance.write(boxName, key, const []);
  }

  // ⚠️ הוסרו `addItem` ו-`removeAt`: אין להם צרכן, והשני היה מלכודת —
  // אינדקס אינו יציב במאגר משותף שחלון אחר יכול להוסיף לראשו. כל צרכן
  // עובר דרך [mutate] עם תנאי על **הזהות** של הרשומה.

  _Decoded<T> _decode(List<dynamic> raw) {
    final items = <T>[];
    final undecodable = <dynamic>[];
    for (final entry in raw) {
      try {
        items.add(fromJson(castMap(entry)));
      } catch (e) {
        debugPrint('⚠️ $boxName/$key: skipping undecodable entry: $e');
        undecodable.add(entry);
      }
    }
    return _Decoded(items, undecodable);
  }
}

class _Decoded<T> {
  const _Decoded(this.items, this.undecodable);

  final List<T> items;
  final List<dynamic> undecodable;
}
