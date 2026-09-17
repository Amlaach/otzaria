import 'package:flutter/foundation.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';

/// Converts a sqlite3 [ResultSet] to a list of dynamic maps.
extension ResultSetExt on ResultSet {
  List<Map<String, dynamic>> toMapList() =>
      map((row) => Map<String, dynamic>.from(row)).toList();
}

/// Returns the first integer value from a single-column [ResultSet], or null.
int? firstIntValue(ResultSet result) {
  if (result.isEmpty) return null;
  final value = result.first.values.first;
  if (value == null) return null;
  return value as int;
}

/// Runs [fn] inside an explicit SQLite transaction.
/// Commits on success, rolls back on error.
void withTransaction(Database db, void Function() fn) {
  db.execute('BEGIN');
  try {
    fn();
    db.execute('COMMIT');
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  }
}

/// סוגר חיבור כתיבה אחרי מיזוג ה-WAL לקובץ הראשי. בלי המיזוג, חיבור פתוח
/// של חלון מוסתר הופך את הסגירה ללא-אחרונה, והשינויים נשארים בקובץ ה-WAL.
void closeWithCheckpoint(Database db) {
  try {
    db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
  } catch (_) {}
  db.close();
}

/// פותח DB כתיב עם הכוונון האחיד לכל מסדי הנתונים של האפליקציה.
Database openWritableDatabase(String path, String label) {
  final db = sqlite3.open(path);
  tuneWritableDatabase(db, label);
  return db;
}

/// כוונון אחיד לחיבור כתיב: המתנה לנעילה, ו-WAL כשהאחסון תומך בו.
void tuneWritableDatabase(Database db, String label) {
  try {
    // המתנה במקום כישלון מיידי ב-SQLITE_BUSY: מופע שני של התוכנה או נעילה
    // שנשארה מסגירה כפויה היו מפילים את ה-DDL הראשון.
    db.execute('PRAGMA busy_timeout=5000');
  } catch (e) {
    debugPrint('[$label] busy_timeout failed: $e');
  }
  enableWalBestEffort(db, label);
}

/// מפעיל WAL כשאפשר, ולא מפיל את פתיחת ה-DB כשלא.
///
/// המעבר ל-WAL קוטם את קובץ ה-journal, וקטימה חסומה (נעילה שנשארה מסגירה
/// כפויה, אנטי-וירוס) אינה סיבה שכל התכונה לא תעלה: ה-DB נשאר שמיש במצב
/// ה-journal הקיים. [label] מזהה את הקורא בלוג.
void enableWalBestEffort(Database db, String label) {
  try {
    db.execute('PRAGMA journal_mode=WAL');
    // ה-PRAGMA מצליח גם כשהמצב אינו שמיש: קובץ ה-shared-memory של WAL נפתח
    // רק בטרנזקציה הראשונה, וכרטיס SD ב-Android נכשל שם (IOERR_SHMOPEN).
    db.execute('BEGIN IMMEDIATE');
    db.execute('COMMIT');
  } catch (e) {
    debugPrint('[$label] journal_mode=WAL failed: $e');
    _revertToRollbackJournal(db, label);
  }
}

/// מחזיר את ה-DB ל-journal רגיל אחרי ש-WAL התגלה כלא שמיש.
/// locking_mode=EXCLUSIVE הוא התנאי שבו SQLite עוזב WAL בלי קובץ shm.
void _revertToRollbackJournal(Database db, String label) {
  try {
    db.execute('ROLLBACK');
  } catch (_) {}
  try {
    db.execute('PRAGMA locking_mode=EXCLUSIVE');
    db.execute('PRAGMA journal_mode=DELETE');
    db.execute('PRAGMA locking_mode=NORMAL');
  } catch (e) {
    debugPrint('[$label] fallback to rollback journal failed: $e');
  }
}
