import 'package:otzaria/library/models/library.dart';

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
