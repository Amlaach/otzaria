import 'dart:convert';

import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';

/// תוצאת ייבוא של רשימת הסתרות מקובץ (issue #1448).
class HiddenBooksImportResult {
  /// מפתחות הספרים שהותאמו לספרייה.
  final Set<String> matchedBookKeys;

  /// שמות שלא נמצא להם ספר. מוצגים למשתמש כדי ששגיאת כתיב לא תיעלם בשקט.
  final List<String> unmatchedNames;

  /// כמה שמות היו בקובץ בסך הכול.
  final int totalNames;

  const HiddenBooksImportResult({
    required this.matchedBookKeys,
    required this.unmatchedNames,
    required this.totalNames,
  });

  bool get isEmpty => totalNames == 0;
}

/// מפרש קובץ הסתרות ומתאים את שמותיו לספרים בספרייה.
///
/// הקובץ מכיל **שמות ספרים** ולא מזהים פנימיים: מזהה כמו `o__4217__אור החיים`
/// אינו בר-כתיבה ביד, והבקשה באישו הייתה רשימה שמשתמש מכין בעצמו.
///
/// נתמכים שני פורמטים:
/// - JSON: מערך מחרוזות, או אובייקט עם המפתח `books`.
/// - CSV/טקסט: שם בכל שורה. בשורה עם פסיקים נלקחת העמודה הראשונה.
///
/// שם שמופיע יותר מפעם אחת בספרייה מסתיר את כל המופעים — ההתאמה היא לפי שם,
/// כפי שהקובץ מנוסח.
HiddenBooksImportResult parseHiddenBooksImport(
  String content,
  Library library,
) {
  final names = _extractNames(content);
  if (names.isEmpty) {
    return const HiddenBooksImportResult(
      matchedBookKeys: {},
      unmatchedNames: [],
      totalNames: 0,
    );
  }

  final booksByTitle = <String, List<String>>{};
  for (final book in library.getAllBooks()) {
    booksByTitle
        .putIfAbsent(book.title.trim(), () => <String>[])
        .add(PerBookSettings.bookKey(book));
  }

  final matched = <String>{};
  final unmatched = <String>[];
  for (final name in names) {
    final keys = booksByTitle[name];
    if (keys == null) {
      unmatched.add(name);
      continue;
    }
    matched.addAll(keys);
  }

  return HiddenBooksImportResult(
    matchedBookKeys: matched,
    unmatchedNames: unmatched,
    totalNames: names.length,
  );
}

List<String> _extractNames(String content) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) return const [];

  if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
    try {
      final decoded = jsonDecode(trimmed);
      final list = decoded is Map ? decoded['books'] : decoded;
      if (list is List) {
        return _normalize(list.whereType<String>());
      }
    } catch (_) {
      // לא JSON תקין — ממשיכים לפענוח כטקסט, שהוא המקרה הנפוץ.
    }
  }

  return _normalize(
    const LineSplitter().convert(trimmed).map((line) {
      final cell = line.split(',').first;
      // גרשיים עוטפים הם תחביר CSV, לא חלק מהשם.
      return cell.trim().replaceAll(RegExp(r'^"|"$'), '');
    }),
  );
}

/// מנקה רווחים, זורק ריקים, ושומר על סדר בלי כפילויות.
List<String> _normalize(Iterable<String> raw) {
  final seen = <String>{};
  final result = <String>[];
  for (final value in raw) {
    final name = value.trim();
    if (name.isEmpty) continue;
    if (!seen.add(name)) continue;
    result.add(name);
  }
  return result;
}
