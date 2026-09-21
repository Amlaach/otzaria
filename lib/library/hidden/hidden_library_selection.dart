import 'package:flutter/foundation.dart' show immutable, setEquals;
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';

/// הספרים והקטגוריות שהמשתמש הסתיר מהממשק (issue #1448).
///
/// ⚠️ הסתרה היא של הממשק בלבד. אין לגעת במסד הספרים, והעץ שב-
/// `DataRepository` — שגשר התוספים וקוד התחזוקה נשענים עליו — נשאר שלם.
@immutable
class HiddenLibrarySelection {
  /// מפתחות ספרים, בפורמט של [PerBookSettings.bookKey]. אותו מפתח שכבר משמש
  /// להגדרות פר-ספר, ולכן הוא יציב מול שינוי מזהי המסד בעדכון ספרייה.
  final Set<String> bookKeys;

  /// נתיבי קטגוריות, בפורמט של [Category.path] (למשל `/תנ"ך/תורה`).
  final Set<String> categoryPaths;

  const HiddenLibrarySelection({
    this.bookKeys = const {},
    this.categoryPaths = const {},
  });

  bool get isEmpty => bookKeys.isEmpty && categoryPaths.isEmpty;

  bool isBookHidden(Book book) =>
      bookKeys.contains(PerBookSettings.bookKey(book));

  bool isCategoryHidden(Category category) =>
      categoryPaths.contains(category.path);

  HiddenLibrarySelection copyWith({
    Set<String>? bookKeys,
    Set<String>? categoryPaths,
  }) => HiddenLibrarySelection(
    bookKeys: bookKeys ?? this.bookKeys,
    categoryPaths: categoryPaths ?? this.categoryPaths,
  );

  @override
  bool operator ==(Object other) =>
      other is HiddenLibrarySelection &&
      setEquals(other.bookKeys, bookKeys) &&
      setEquals(other.categoryPaths, categoryPaths);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(bookKeys),
    Object.hashAllUnordered(categoryPaths),
  );
}
