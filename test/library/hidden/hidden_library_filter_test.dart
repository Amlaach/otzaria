import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/hidden/hidden_library_filter.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/library/hidden/hidden_titles.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';

/// עץ בדיקה: תנ"ך › תורה › {בראשית, שמות}, ומדרש › {תנחומא}.
Library _buildLibrary() {
  final tanach = Category(
    title: 'תנ"ך',
    description: '',
    shortDescription: '',
    order: 1,
    subCategories: [],
    books: [],
    parent: null,
  );
  final tora = Category(
    title: 'תורה',
    description: '',
    shortDescription: '',
    order: 1,
    subCategories: [],
    books: [],
    parent: tanach,
  );
  tanach.subCategories.add(tora);
  tora.books.addAll([
    TextBook(title: 'בראשית', categoryId: 10),
    TextBook(title: 'שמות', categoryId: 10),
  ]);

  final midrash = Category(
    title: 'מדרש',
    description: '',
    shortDescription: '',
    order: 2,
    subCategories: [],
    books: [],
    parent: null,
  );
  midrash.books.add(TextBook(title: 'תנחומא', categoryId: 20));

  final library = Library(categories: [tanach, midrash]);
  tanach.parent = library;
  midrash.parent = library;
  return library;
}

List<String> _titles(Library library) =>
    library.getAllBooks().map((b) => b.title).toList()..sort();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ספר מוסתר נעלם מהעץ המסונן (issue #1448)', () {
    final library = _buildLibrary();
    final hidden = HiddenLibrarySelection(
      bookKeys: {
        PerBookSettings.bookKey(TextBook(title: 'שמות', categoryId: 10)),
      },
    );

    final filtered = filterHiddenFromLibrary(library, hidden);

    expect(_titles(filtered), ['בראשית', 'תנחומא']);
  });

  test('קטגוריה מוסתרת נעלמת על כל תוכנה (issue #1448)', () {
    final library = _buildLibrary();
    final hidden = HiddenLibrarySelection(categoryPaths: {'/תנ"ך'});

    final filtered = filterHiddenFromLibrary(library, hidden);

    expect(_titles(filtered), ['תנחומא']);
    expect(
      filtered.subCategories.map((c) => c.title),
      ['מדרש'],
      reason: 'הקטגוריה עצמה יורדת, לא רק ספריה',
    );
  });

  test('תת-קטגוריה מוסתרת אינה מפילה את ההורה (issue #1448)', () {
    final library = _buildLibrary();
    final hidden = HiddenLibrarySelection(categoryPaths: {'/תנ"ך/תורה'});

    final filtered = filterHiddenFromLibrary(library, hidden);

    expect(_titles(filtered), ['תנחומא']);
    expect(filtered.subCategories.map((c) => c.title), ['תנ"ך', 'מדרש']);
  });

  test('בלי הסתרות העץ חוזר שלם (issue #1448)', () {
    final filtered = filterHiddenFromLibrary(
      _buildLibrary(),
      const HiddenLibrarySelection(),
    );

    expect(_titles(filtered), ['בראשית', 'שמות', 'תנחומא']);
  });

  test('הסינון אינו נוגע בעץ המקורי (issue #1448)', () {
    final library = _buildLibrary();
    final hidden = HiddenLibrarySelection(categoryPaths: {'/תנ"ך'});

    filterHiddenFromLibrary(library, hidden);

    expect(
      _titles(library),
      ['בראשית', 'שמות', 'תנחומא'],
      reason:
          'העץ של DataRepository משותף עם גשר התוספים ועם קוד התחזוקה — '
          'ההסתרה היא של הממשק בלבד',
    );
  });

  test('ההורים בעץ המסונן מצביעים על העותק המסונן (issue #1448)', () {
    final library = _buildLibrary();
    final hidden = HiddenLibrarySelection(
      bookKeys: {
        PerBookSettings.bookKey(TextBook(title: 'שמות', categoryId: 10)),
      },
    );

    final filtered = filterHiddenFromLibrary(library, hidden);
    final tanach = filtered.subCategories.firstWhere((c) => c.title == 'תנ"ך');

    expect(identical(tanach.parent, filtered), isTrue);
    expect(identical(tanach.subCategories.single.parent, tanach), isTrue);
  });

  test('כותרות מפרשים נסרקות בלי לשכפל עץ וקטגוריית אב מסתירה צאצאים', () {
    final library = _buildLibrary();
    final originalCategory = library.subCategories.first;
    final hidden = HiddenLibrarySelection(categoryPaths: {'/תנ"ך'});

    expect(hiddenBookTitlesForSelection(library, hidden), {'בראשית', 'שמות'});
    expect(identical(library.subCategories.first, originalCategory), isTrue);
    expect(hiddenBookTitlesForSelection(library, hidden), {'בראשית', 'שמות'});
  });

  test('שם כפול נשאר גלוי אם לפחות אחד הספרים גלוי', () {
    final library = _buildLibrary();
    library.subCategories.last.books.add(
      TextBook(title: 'בראשית', categoryId: 20),
    );

    expect(
      hiddenBookTitlesForSelection(
        library,
        HiddenLibrarySelection(categoryPaths: {'/תנ"ך'}),
      ),
      {'שמות'},
    );
    expect(
      hiddenBookTitlesForSelection(library, const HiddenLibrarySelection()),
      isEmpty,
    );
  });

  test('מפתח ספר מסתיר כותרת אחת בלבד, בלי קטגוריה', () {
    final library = _buildLibrary();
    final hidden = HiddenLibrarySelection(
      bookKeys: {
        PerBookSettings.bookKey(TextBook(title: 'שמות', categoryId: 10)),
      },
    );

    expect(hiddenBookTitlesForSelection(library, hidden), {'שמות'});
  });
}
