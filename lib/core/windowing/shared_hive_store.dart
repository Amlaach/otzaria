import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/core/windowing/window_role.dart';

/// מפתח של ערך משותף — שם ה-box והמפתח בתוכו.
@immutable
class SharedHiveKey {
  const SharedHiveKey(this.box, this.key);

  final String box;
  final String key;

  @override
  bool operator ==(Object other) =>
      other is SharedHiveKey && other.box == box && other.key == key;

  @override
  int get hashCode => Object.hash(box, key);

  @override
  String toString() => '$box/$key';
}

/// ערך משותף כפי שנקרא, עם הגרסה שממנה נלקח.
@immutable
class SharedHiveValue {
  const SharedHiveValue({
    required this.revision,
    required this.value,
    this.reason,
  });

  /// מונה שהבעלים מקדם בכל כתיבה.
  ///
  /// כתיבה שנשענת על גרסה שאינה עוד הנוכחית נדחית. זה מה שמונע מחלון
  /// שמחזיק עותק מיושן למחוק את מה שחלון אחר כתב בינתיים.
  final int revision;

  final Object? value;

  /// למה הערך אינו מוסמך. null כשהוא כן — ומועבר הלאה לחריגה שהקורא זורק,
  /// כדי שהלוג יבחין בין "אין בעלים" ל"פקע הזמן" ל"אין מטפל".
  ///
  /// הסיבה היא גם המקור ל-[authoritative], כדי שערך לא-מוסמך לא יוכל לצאת
  /// בלעדיה — הקורא זורק ורושם אותה.
  final SharedHiveUnavailableReason? reason;

  /// האם הערך הגיע מהבעלים.
  ///
  /// ⚠️ `false` פירושו **"לא הצלחנו לשאול"**, ולא "ריק". ההבחנה הזו היא כל
  /// ההגנה: קריאה שנכשלה החזירה בעבר רשימה ריקה, ה-bloc קיבע אותה לכל חיי
  /// החלון, והכתיבה הראשונה שלו מחקה 200 רשומות אצל הבעלים.
  bool get authoritative => reason == null;

  List<dynamic> get asList {
    final v = value;
    return v is List ? v : const [];
  }
}

/// למה הבעלים לא סיפק תשובה שאפשר להסתמך עליה.
///
/// ⚠️ ההבחנה אינה קוסמטית: פקיעת זמן היא בעלים **עסוק** (ותחזור אחרי
/// הטעינה שלו), ואילו [noHandler] היא מרוץ אתחול — הבעלים ענה לפני
/// ש-`WindowBusHost.initState` קבע את `onRequest`. בלוג הן נראו זהות.
enum SharedHiveUnavailableReason {
  /// כינוי הבעלים אינו רשום כלל באפיק.
  noOwner('אין חלון בעלים רשום'),

  /// הבעלים לא ענה בתוך הזמן שהוקצב.
  timeout('הבעלים לא ענה בזמן'),

  /// הבעלים ענה null — עדיין אין לו מטפל בקשות.
  noHandler('הבעלים ענה בלי מטפל בקשות'),

  /// הבקשה זרקה אצל הבעלים.
  ownerError('הבקשה נכשלה אצל הבעלים'),

  /// הבעלים ענה שגם הוא לא הצליח לקרוא מ-Hive.
  ownerReadFailed('גם הבעלים לא הצליח לקרוא');

  const SharedHiveUnavailableReason(this.description);

  final String description;
}

/// הבעלים לא ענה, ולכן אין על מה לבסס כתיבה.
class SharedHiveUnavailable implements Exception {
  const SharedHiveUnavailable(this.id, this.reason);

  /// בונה את החריגה ורושם אותה ללוג.
  ///
  /// הרישום עצמו ב-[_log]: המופע הראשון לכל (מפתח, סיבה) נרשם מיד, וחזרות
  /// מתקבצות לרשומה מסכמת אחת לכל היותר ב-[_summaryInterval].
  static SharedHiveUnavailable report(
    SharedHiveKey id,
    SharedHiveUnavailableReason reason,
  ) {
    final error = SharedHiveUnavailable(id, reason);
    _log(error);
    return error;
  }

  final SharedHiveKey id;
  final SharedHiveUnavailableReason reason;

  /// יעד הרישום. מוחלף בבדיקות כדי שלא ייכתב errors.txt אמיתי של המפתח.
  @visibleForTesting
  static void Function(String text) logSink = ErrorLogFile.appendText;

  @visibleForTesting
  static DateTime Function() logClock = DateTime.now;

  @visibleForTesting
  static void resetLogForTest() => _logged.clear();

  @override
  String toString() => 'החלון הראשי לא זמין ($id): ${reason.description}';
}

/// כל כמה זמן לכל היותר נרשמת רשומה מסכמת על חזרות של אותה תקלה.
const Duration _summaryInterval = Duration(minutes: 5);

/// מה שנרשם עד כה על (מפתח, סיבה) אחד.
class _UnavailableLog {
  _UnavailableLog(this.since);

  /// מתי נרשמה הרשומה האחרונה — ממנה נספרות החזרות.
  DateTime since;
  int repeats = 0;
}

final Map<String, _UnavailableLog> _logged = {};

/// רושם את התקלה — מיד בפעם הראשונה, ואחריה כסיכום מקובץ.
///
/// בלי הקיבוץ תקלה שחוזרת כל 6 שניות (issue #1339) הייתה ממלאת את
/// errors.txt, ובלי הסיכום החזרתיות שלה הייתה נעלמת לגמרי.
void _log(SharedHiveUnavailable error) {
  final key = '${error.id}/${error.reason.name}';
  final now = SharedHiveUnavailable.logClock();
  final entry = _logged[key];
  if (entry == null) {
    _logged[key] = _UnavailableLog(now);
    _appendLog(error, repeats: null);
    return;
  }
  entry.repeats++;
  if (now.difference(entry.since) < _summaryInterval) return;
  _appendLog(
    error,
    repeats: 'אירע ${entry.repeats} פעמים מאז ${entry.since.toIso8601String()}',
  );
  entry.since = now;
  entry.repeats = 0;
}

/// הכתיבה נדחית לסיבוב הבא של תור האירועים כדי שהזורק לא ימתין לה,
/// וכשל בה לעולם אינו מחליף את החריגה. הכתיבה עצמה סינכרונית וקצרה.
void _appendLog(SharedHiveUnavailable error, {required String? repeats}) {
  final slot = WindowBus.instance.slot;
  unawaited(
    Future(() {
      try {
        SharedHiveUnavailable.logSink(
          ErrorLogFile.formatEntry(
            title: 'מאגר משותף לא זמין',
            error: error,
            details: {
              'box': error.id.box,
              'key': error.id.key,
              'reason': error.reason.name,
              'slot': '$slot',
              'repeats': repeats,
            },
          ),
        );
      } catch (_) {}
    }),
  );
}

/// הקריאה מ-Hive עצמו נכשלה — לא בעיית ניתוב בין חלונות.
///
/// נפרד מ-[SharedHiveUnavailable] כדי שחלון יחיד לא יקבל את ההודעה "החלון
/// הראשי לא זמין" על תקלה מקומית.
class SharedHiveReadFailed implements Exception {
  const SharedHiveReadFailed(this.id, this.reason);

  final SharedHiveKey id;
  final String reason;

  @override
  String toString() => 'קריאה מ-$id נכשלה: $reason';
}

/// הגרסה שהכתיבה נשענה עליה אינה עוד הנוכחית — חלון אחר כתב בינתיים.
class SharedHiveConflict implements Exception {
  const SharedHiveConflict(this.id, this.fresh);

  final SharedHiveKey id;

  /// הערך הנוכחי אצל הבעלים, כדי שהקורא יוכל להחיל את כוונתו מחדש עליו.
  final SharedHiveValue fresh;

  @override
  String toString() => 'התנגשות גרסאות ב-$id (גרסה ${fresh.revision})';
}

/// הכתיבה הגיעה לבעלים ונכשלה שם.
class SharedHiveWriteFailed implements Exception {
  const SharedHiveWriteFailed(this.id, this.reason);

  final SharedHiveKey id;
  final String reason;

  @override
  String toString() => 'כתיבה ל-$id נכשלה: $reason';
}

/// גישה ל-Hive של מאגרים שמשותפים לכל חלונות אוצריא.
///
/// ## למה בכלל ניתוב
///
/// `hive_ce` נועל את קובצי ה-`.lock` בלעדית, והנעילה היא פר-handle — שני
/// חלונות באותו תהליך נכשלים בדיוק כמו שני תהליכים. לכן חלון משני מקבל
/// שורש Hive פרטי, ו"שיתוף" חייב להיות ניתוב אל מי שכן פתח את הקבצים
/// שבשורש הנתונים האמיתי: **החלון הראשון**, שנקרא כאן הבעלים.
///
/// ## מודל העקביות: הבעלים הוא הבורר
///
/// לכל מפתח יש **גרסה** שהבעלים מקדם בכל כתיבה. קריאה מחזירה את הגרסה
/// יחד עם הערך; כתיבה יכולה להצהיר על הגרסה שהיא נשענת עליה, והבעלים דוחה
/// אותה אם היא אינה עוד הנוכחית. בלי זה שני חלונות היו כותבים כל אחד את
/// הרשימה השלמה **שלו** — מצב שבו כל כתיבה מוחקת את מה שהאחר הוסיף, לנצח,
/// גם בלי שום מרוץ.
///
/// המיזוג עצמו נעשה **אצל הקורא** ולא אצל הבעלים
/// (`HiveListRepository.mutate`): הזהות של רשומה היא getter מחושב
/// (`Bookmark.historyKey`, `Workspace.id`), ולבעלים יש רק JSON. במקום
/// לשכפל את הלוגיקה מעבר לגבול ה-isolate, הקורא מחיל את כוונתו על הערך
/// הטרי ומנסה שוב — והגרסה היא מה שמבטיח שהניסיון נשען על מה שבאמת שם.
///
/// אחרי כל כתיבה הבעלים **משדר** לשאר החלונות שהמפתח השתנה, כדי שהעותק
/// שבזיכרון שלהם לא יתיישן ([changes]).
class SharedHiveStore {
  SharedHiveStore._() : _forceOwner = false;

  /// מופע שמתנהג כבעלים ללא תלות ב-[WindowRole].
  ///
  /// ⚠️ קיים כדי שבדיקה אחת תוכל להריץ את **שני** הצדדים עם ההיגיון
  /// האמיתי שלהם. הבדיקה הקודמת החליפה את צד הבעלים במימוש חלופי, ולכן
  /// `handleRequest` — הקוד שמשרת כל חלון משני — לא נבדק כלל.
  @visibleForTesting
  SharedHiveStore.owner() : _forceOwner = true;

  static final SharedHiveStore instance = SharedHiveStore._();

  /// האם המופע הזה הוא הבעלים בהגדרה, גם בחלון משני.
  final bool _forceOwner;

  /// סוגי הבקשות באפיק.
  static const String requestRead = 'sharedHiveRead';
  static const String requestWrite = 'sharedHiveWrite';
  static const String requestChanged = 'sharedHiveChanged';

  /// המאגרים שמנותבים לבעלים.
  ///
  /// `tabs` **כן** ברשימה, אבל לא כדי שכל החלונות יציגו את אותן כרטיסיות:
  /// כל חלון כותב שם תחת מפתח משלו ([tabsKeyForWindow]). בלי זה הכרטיסיות
  /// של חלון משני נכתבו לשורש הפרטי שנוצר מחדש בכל הפעלה — כלומר לא נשמרו
  /// כלל, והכרטיסיה שהועברה לשם נעלמה משני החלונות.
  ///
  /// `notes` **אינו** ברשימה: אין box בשם הזה. ההערות האישיות יושבות
  /// ב-SQLite (`personal_notes.db`) ואינן עוברות כאן כלל.
  ///
  /// ⚠️ **פער ידוע:** `error_reports_queue` ו-`plugin_reports_queue` אינם
  /// ברשימה, ולכן דיווח שנוצר בחלון משני ולא נשלח (המשתמש אופליין) נכתב
  /// לשורש ה-Hive הפרטי שלו ואובד. הוספה פשוטה לרשימה כאן **אינה** הפתרון:
  /// שני השירותים כותבים ב-`overwrite` בלי בדיקת גרסה, ולכן שני חלונות
  /// היו מוחקים זה לזה את התור. הפתרון דורש הכרעה — מפתח פר-חלון עם אימוץ
  /// בהפעלה קרה (כמו `TabsRepository.adoptOrphanWindowSessions`), או מסירה
  /// לבעלים באפיק בסגירת החלון — ושתיהן משנות את סמנטיקת הדה-דופליקציה של
  /// הדיווחים. ההשפעה מוגבלת לטלמטריה: אין כאן נתוני משתמש.
  static const Set<String> sharedBoxes = {
    'history',
    'bookmarks',
    'workspaces',
    'tabs',
  };

  static bool isShared(String boxName) => sharedBoxes.contains(boxName);

  /// האם הגישה למאגר הזה צריכה לעבור דרך הבעלים.
  ///
  /// בחלון הראשון התשובה תמיד לא — הוא **הוא** הבעלים, וכל השכבה הזו
  /// מתקצרת לגישה ישירה ל-Hive. חלון יחיד אינו משלם דבר.
  bool _routesToOwner(String boxName) =>
      !_forceOwner && WindowRole.isSecondary && isShared(boxName);

  /// המפתח שבו חלון שומר את הכרטיסיות שלו.
  ///
  /// החלון הראשון שומר במפתח ההיסטורי, כי הוא זה שנטען בהפעלה קרה ואין
  /// לשבור נתונים שכבר על הדיסק.
  static String tabsKeyForWindow(int? windowSlot, String baseKey) =>
      windowSlot == null ? baseKey : '$baseKey-window-$windowSlot';

  /// מאגרים שאין טעם לשדר שינוי בהם.
  ///
  /// ⚠️ `tabs` מנותב לבעלים כדי שהכרטיסיות **יישמרו**, אבל כל חלון כותב
  /// תחת מפתח משלו ואף אחד אינו מאזין למפתח של האחר. בלי החרגה כאן כל
  /// החלפת כרטיסיה בחלון הראשי הייתה שולחת שלוש הודעות אפיק שאין להן
  /// נמען — והחלפת כרטיסיה היא הפעולה השכיחה בתוכנה.
  static const Set<String> _privateToWindow = {'tabs'};

  static bool _notifiesPeers(String boxName) =>
      !_privateToWindow.contains(boxName);

  /// גרסה נוכחית לכל מפתח — נשמרת אצל הבעלים.
  ///
  /// בזיכרון ולא בדיסק: היא צריכה להיות מונוטונית לאורך חיי התהליך בלבד,
  /// וכל החלונות מקבלים אותה מאותו מקור.
  final Map<SharedHiveKey, int> _revisions = {};

  /// כתיבה בתהליך לכל מפתח, כדי שבדיקת הגרסה והקידום שלה יהיו אטומיים.
  ///
  /// ⚠️ `box.put` הוא נקודת yield. בלי התור שתי כתיבות עם אותו `ifRevision`
  /// עברו שתיהן את הבדיקה, הראשונה נדרסה בשקט, והגרסה עלתה ב-1 בלבד.
  final Map<SharedHiveKey, Future<void>> _writesInFlight = {};

  final StreamController<SharedHiveKey> _changes =
      StreamController<SharedHiveKey>.broadcast(sync: true);

  /// מפתחות שהשתנו — אצל הבעלים בכתיבה שלו, ובחלון משני כשהבעלים שידר.
  Stream<SharedHiveKey> get changes => _changes.stream;

  Box<dynamic> _box(String boxName) => Hive.box<dynamic>(boxName);

  /// ⚠️ timeout נדיב, ובמכוון.
  ///
  /// ברירת המחדל של [WindowBus.peers] היא 2,500ms, ונמדד שהבעלים עסוק
  /// 2,092ms בזמן טעינת קטלוג הספרייה — כלומר בדיוק ברגע שבו נפתח חלון
  /// שני. קריאה שפקעה שם החזירה רשימה ריקה, וזה היה מסלול אובדן הנתונים
  /// החמור ביותר בענף.
  @visibleForTesting
  static Duration ownerTimeout = const Duration(seconds: 8);

  /// "לא ידוע מה יש שם" — לא "ריק". נושא את הסיבה כדי שהזורק בהמשך
  /// ([HiveListRepository], [TabsRepository]) יוכל לרשום אותה.
  static SharedHiveValue _unknown(SharedHiveUnavailableReason reason) =>
      SharedHiveValue(revision: 0, value: null, reason: reason);

  static SharedHiveUnavailableReason _reasonFor(WindowBusFailure? failure) =>
      switch (failure) {
        WindowBusFailure.timeout => SharedHiveUnavailableReason.timeout,
        WindowBusFailure.error => SharedHiveUnavailableReason.ownerError,
        // היעד ענה, ותשובתו null — `onRequest` טרם נקבע אצלו.
        null => SharedHiveUnavailableReason.noHandler,
      };

  Future<SharedHiveValue> read(String boxName, String key) async {
    final id = SharedHiveKey(boxName, key);
    if (!_routesToOwner(boxName)) {
      final local = _readLocal(id, authoritative: true);
      if (local.error != null) throw SharedHiveReadFailed(id, '${local.error}');
      return local.value;
    }

    final owner = WindowBus.instance.ownerPort;
    if (owner == null) return _unknown(SharedHiveUnavailableReason.noOwner);

    final answer = await WindowBus.instance.requestPortDetailed(
      owner,
      {'type': requestRead, 'box': boxName, 'key': key},
      timeout: ownerTimeout,
    );
    final result = answer.result;
    if (result is Map) {
      // ⚠️ הבעלים ענה — אבל התשובה שלו יכולה להיות "גם אני לא הצלחתי לקרוא".
      // סימון עיוור של `true` כאן הפך כשל קריאה אצל הבעלים ל-null מוסמך,
      // כלומר לרשימה ריקה תקינה אצל הקורא.
      return SharedHiveValue(
        revision: (result['revision'] as int?) ?? 0,
        value: result['value'],
        reason: result['authoritative'] == false
            ? SharedHiveUnavailableReason.ownerReadFailed
            : null,
      );
    }
    // ⚠️ אין עותק מקומי, ובמכוון. חלון משני מקבל שורש Hive פרטי וריק, ולכן
    // "העותק המקומי" הוא רשימה ריקה שנראית כמו נתונים אמיתיים. עדיף להצהיר
    // שלא ידוע מה יש שם מלהחזיר ריק שיירשם בחזרה.
    final reason = _reasonFor(answer.failure);
    debugPrint(
      'SharedHiveStore: owner did not answer read of $id (${reason.name})',
    );
    return _unknown(reason);
  }

  /// כותב את [value], ואם [ifRevision] אינו null — רק אם זו עדיין הגרסה
  /// הנוכחית.
  ///
  /// זורק [SharedHiveConflict] כשהגרסה התקדמה, [SharedHiveUnavailable]
  /// כשהבעלים לא ענה, ו-[SharedHiveWriteFailed] כשהכתיבה עצמה נכשלה.
  ///
  /// ⚠️ כשל **חייב** להתפשט. שלוש שכבות תלויות בו: ההודעה למשתמש שסימנייה
  /// לא נשמרה, הניסיון החוזר ב-`PreCloseRegistry`, ודיווח
  /// `PreCloseFlushFailure` ל-Sentry. בליעה כאן הפכה את שלושתן לקוד מת.
  Future<void> write(
    String boxName,
    String key,
    Object? value, {
    int? ifRevision,
  }) async {
    final id = SharedHiveKey(boxName, key);
    if (!_routesToOwner(boxName)) {
      await _writeAsOwner(id, value, ifRevision: ifRevision, origin: null);
      return;
    }

    final owner = WindowBus.instance.ownerPort;
    if (owner == null) {
      throw SharedHiveUnavailable.report(
        id,
        SharedHiveUnavailableReason.noOwner,
      );
    }

    final answer = await WindowBus.instance.requestPortDetailed(
      owner,
      {
        'type': requestWrite,
        'box': boxName,
        'key': key,
        'value': value,
        'ifRevision': ?ifRevision,
        // כדי שהבעלים לא ישדר לנו בחזרה שינוי שאנחנו יזמנו.
        'origin': ?WindowBus.instance.slot,
      },
      timeout: ownerTimeout,
    );
    final result = answer.result;
    if (result is! Map) {
      throw SharedHiveUnavailable.report(id, _reasonFor(answer.failure));
    }
    if (result['ok'] == true) return;
    if (result['conflict'] == true) {
      throw SharedHiveConflict(
        id,
        SharedHiveValue(
          revision: (result['revision'] as int?) ?? 0,
          value: result['value'],
        ),
      );
    }
    throw SharedHiveWriteFailed(id, '${result['error']}');
  }

  /// מוחק מפתח. משמש לניקוי סשן של חלון שנסגר.
  Future<void> delete(String boxName, String key) => write(boxName, key, null);

  /// קריאה ישירה מ-Hive, עם התקלה עצמה כשהיא נכשלה.
  ///
  /// ה-[error] נדרש כדי להבדיל בין תקלה מקומית לבין בעלים שלא ענה — שתיהן
  /// `authoritative: false`, אבל רק אחת מהן מצדיקה את ההודעה על חלון ראשי.
  ({SharedHiveValue value, Object? error}) _readLocal(
    SharedHiveKey id, {
    required bool authoritative,
  }) {
    try {
      return (
        value: SharedHiveValue(
          revision: _revisions[id] ?? 0,
          value: _box(id.box).get(id.key),
          reason: authoritative
              ? null
              : SharedHiveUnavailableReason.ownerReadFailed,
        ),
        error: null,
      );
    } catch (e) {
      debugPrint('SharedHiveStore: local read of $id failed: $e');
      return (
        value: SharedHiveValue(
          revision: _revisions[id] ?? 0,
          value: null,
          reason: SharedHiveUnavailableReason.ownerReadFailed,
        ),
        error: e,
      );
    }
  }

  /// הצד המבצע — רץ אצל הבעלים, בין שהקריאה מקומית ובין שהגיעה באפיק.
  ///
  /// [origin] היא המשבצת שיזמה את הכתיבה, או null כשהיא מקומית. משמשת לשני
  /// דברים: לא להודיע ליוזם על שינוי שהוא עצמו עשה, ולא להודיע למאזינים
  /// המקומיים על כתיבה שהם עצמם ביקשו.
  Future<void> _writeAsOwner(
    SharedHiveKey id,
    Object? value, {
    int? ifRevision,
    required int? origin,
  }) {
    // הכתיבות לאותו מפתח מסתדרות בתור: בדיקת הגרסה, ה-put וקידום הגרסה
    // חייבים להיות רצף אחד בלי החלפת הקשר באמצע.
    final previous = _writesInFlight[id];
    final done = Completer<void>();
    _writesInFlight[id] = done.future;

    Future<void> run() async {
      if (previous != null) {
        // כשל של הכתיבה הקודמת אינו מונע מהבאה בתור לרוץ.
        await previous.catchError((_) {});
      }
      try {
        await _applyWrite(id, value, ifRevision: ifRevision, origin: origin);
      } finally {
        if (_writesInFlight[id] == done.future) _writesInFlight.remove(id);
        done.complete();
      }
    }

    return run();
  }

  Future<void> _applyWrite(
    SharedHiveKey id,
    Object? value, {
    int? ifRevision,
    required int? origin,
  }) async {
    final current = _revisions[id] ?? 0;
    if (ifRevision != null && ifRevision != current) {
      throw SharedHiveConflict(id, _readLocal(id, authoritative: true).value);
    }
    final box = _box(id.box);
    if (value == null) {
      await box.delete(id.key);
    } else {
      await box.put(id.key, value);
    }
    _revisions[id] = current + 1;
    if (origin != null) _changes.add(id);
    _broadcastChange(id, origin: origin);
  }

  /// מודיע לשאר החלונות שמפתח השתנה, כדי שהעותק שבזיכרון שלהם לא יתיישן.
  ///
  /// fire-and-forget: חלון שלא קיבל את ההודעה יקבל את הערך הנכון בקריאה
  /// הבאה שלו, ואין מה לעשות בכשל.
  void _broadcastChange(SharedHiveKey id, {required int? origin}) {
    if (WindowRole.isSecondary && !_forceOwner) return;
    if (!_notifiesPeers(id.box)) return;
    WindowBus.instance.broadcast({
      'type': requestChanged,
      'box': id.box,
      'key': id.key,
      'origin': ?origin,
    });
  }

  /// מטפל בבקשה שהגיעה מחלון אחר. מחזיר null כשהבקשה אינה שלנו.
  Future<Object?> handleRequest(Map<String, dynamic> request) async {
    final type = request['type'];
    if (type != requestRead && type != requestWrite && type != requestChanged) {
      return null;
    }
    final boxName = request['box'];
    final key = request['key'];
    if (boxName is! String || key is! String) return null;
    final id = SharedHiveKey(boxName, key);

    switch (type) {
      case requestRead:
        final snapshot = _readLocal(id, authoritative: true).value;
        return {
          'revision': snapshot.revision,
          'value': snapshot.value,
          'authoritative': snapshot.authoritative,
        };
      case requestWrite:
        try {
          await _writeAsOwner(
            id,
            request['value'],
            ifRevision: request['ifRevision'] as int?,
            origin: request['origin'] as int?,
          );
          return const {'ok': true};
        } on SharedHiveConflict catch (conflict) {
          return {
            'conflict': true,
            'revision': conflict.fresh.revision,
            'value': conflict.fresh.value,
          };
        } catch (e) {
          return {'ok': false, 'error': '$e'};
        }
      case requestChanged:
        // הבעלים הודיע. אין כאן קריאה לדיסק — רק אות למי שמאזין.
        // ⚠️ מסונן לפי היוזם: בלעדיו כל חלון היה טוען מחדש גם אחרי כתיבה
        // שהוא עצמו עשה, ומשלם קריאה מיותרת מעל האפיק על כל סימנייה.
        if (request['origin'] != WindowBus.instance.slot) _changes.add(id);
        return true;
    }
    return null;
  }

  @visibleForTesting
  void resetForTest() => _revisions.clear();
}
