import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';

/// המפתחות היציבים של האינדקס ששייכים לספרים שהמשתמש הסתיר (issue #1448).
///
/// נגזר מהפרש בין העץ המלא לעץ המסונן, ולא מבדיקת הסתרה לכל ספר בנפרד: כך
/// הסתרת קטגוריה נלקחת בחשבון בלי לשכפל כאן את כללי העץ.
///
/// התוצאות מסוננות אחרי שהמנוע החזיר אותן, ולא על ידי הוצאת הספר מהאינדקס.
/// המשמעות: מונה התוצאות וספירות חלונית הסינון מגיעים מהמנוע ועשויים לכלול
/// גם מה שהוסתר. זו נקודת פתיחה מודעת — ביטול הסתרה מיידי ואינו דורש
/// אינדוקס מחדש.
Set<String> hiddenIndexedFilePaths({
  required Map<String, Book> fullIndex,
  required Map<String, Book> visibleIndex,
}) {
  if (fullIndex.length == visibleIndex.length) return const {};
  return fullIndex.keys.where((key) => !visibleIndex.containsKey(key)).toSet();
}

/// `true` אם התוצאה שייכת לספר מוסתר ואין להציגה.
bool isHiddenSearchResult(
  String indexedFilePath,
  Set<String> hiddenIndexedFilePaths,
) => hiddenIndexedFilePaths.contains(indexedFilePath);

/// עוזר לבדיקות ולקריאות: מפה של ספרי [library] לפי המפתח היציב.
typedef IndexedBooksBuilder = Map<String, Book> Function(Library library);

/// כותרות הספרים שהמשתמש הסתיר (issue #1448).
///
/// נגזר מהפרש בין העץ המלא למסונן. כותרת שיש לה גם ספר גלוי אינה נחשבת
/// מוסתרת — בספק מציגים.
Set<String> hiddenBookTitles({
  required Library full,
  required Library visible,
}) {
  final visibleTitles = visible.getAllBooks().map((b) => b.title).toSet();
  return full
      .getAllBooks()
      .map((b) => b.title)
      .where((title) => !visibleTitles.contains(title))
      .toSet();
}
