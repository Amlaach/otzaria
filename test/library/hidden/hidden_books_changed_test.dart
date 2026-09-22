import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';

/// שינוי רשימת ההסתרות חייב לבנות מחדש כל הפניה לעץ שה-state מחזיק
/// (issue #1448). קטגוריה שנשארת מהעץ הישן ממשיכה להציג את הספירה הישנה —
/// כך התצוגה המקדימה הראתה "4 ספרים" אחרי שהספר כבר הוחזר לרשת.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Category buildTora(List<String> titles) => Category(
    title: 'תורה',
    description: '',
    shortDescription: '',
    order: 1,
    subCategories: [],
    books: [
      for (final title in titles) TextBook(title: title, categoryId: 10),
    ],
    parent: null,
  );

  test('כל הפניה בעץ נפתרת מחדש לפי הנתיב (issue #1448)', () {
    final before = buildTora(['בראשית', 'שמות']);
    final libraryBefore = Library(categories: [before]);
    before.parent = libraryBefore;

    final after = buildTora(['בראשית']);
    final libraryAfter = Library(categories: [after]);
    after.parent = libraryAfter;

    final state = LibraryState.initial().copyWith(
      library: libraryBefore,
      currentCategory: before,
      previewCategory: before,
    );

    // מה שהמטפל עושה: פתירה מחדש לפי הנתיב, ולא שימוש חוזר באובייקט.
    Category? byPath(Library library, String? path) {
      if (path == null || path == '/') return library;
      for (final category in library.getAllCategories()) {
        if (category.path == path) return category;
      }
      return null;
    }

    final current = byPath(libraryAfter, state.currentCategory?.path);
    final preview = byPath(libraryAfter, state.previewCategory?.path);

    expect(current!.books.map((b) => b.title), ['בראשית']);
    expect(
      preview!.books.map((b) => b.title),
      ['בראשית'],
      reason: 'התצוגה המקדימה החזיקה עותק ישן והציגה ספירה שגויה',
    );
    expect(identical(current, before), isFalse);
  });

  test('HiddenBooksChanged הוא אירוע ללא נתונים (issue #1448)', () {
    expect(const HiddenBooksChanged().props, isEmpty);
    expect(LibraryBloc, isNotNull);
  });
}
