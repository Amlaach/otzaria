import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';

/// ספר מוסתר אינו נכנס לאינדוקס כלל (issue #1448) — הוצאה מהאינדקס, ולא
/// סינון של התוצאות, היא מה ששומר על מונה התוצאות ועל ספירות חלונית הסינון.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final books = [
    TextBook(title: 'בראשית', categoryId: 10),
    TextBook(title: 'שמות', categoryId: 10),
  ];

  String key(String title) =>
      PerBookSettings.bookKey(TextBook(title: title, categoryId: 10));

  List<String> titlesFor(HiddenLibrarySelection hidden) =>
      IndexingRepository.booksForIndexing(
        books,
        includePdfBooks: true,
        hidden: hidden,
      ).map((book) => book.title).toList();

  test('ספר מוסתר יורד מרשימת האינדוקס (issue #1448)', () {
    expect(titlesFor(HiddenLibrarySelection(bookKeys: {key('שמות')})), [
      'בראשית',
    ]);
  });

  test('בלי הסתרות כל הספרים מאונדקסים (issue #1448)', () {
    expect(titlesFor(const HiddenLibrarySelection()), ['בראשית', 'שמות']);
  });

  test('הסתרת ספר שאינו ברשימה אינה משפיעה (issue #1448)', () {
    expect(
      titlesFor(const HiddenLibrarySelection(bookKeys: {'o__99__אין כזה'})),
      ['בראשית', 'שמות'],
    );
  });

  test('קטגוריית אב מוסתרת מוציאה צאצאים בלי לשנות סדר או גרסאות גלויות', () {
    final hiddenBook = TextBook(title: 'נסתר', categoryId: 11);
    final visibleBook = TextBook(title: 'גלוי', categoryId: 12);
    final version = TextBook(title: 'מהדורה אישית', categoryId: 13);
    final library = Library(categories: []);
    final parent = Category(
      title: 'אב',
      description: '',
      shortDescription: '',
      order: 0,
      subCategories: [],
      books: [],
      parent: library,
    );
    final child = Category(
      title: 'בן',
      description: '',
      shortDescription: '',
      order: 0,
      subCategories: [],
      books: [hiddenBook],
      parent: parent,
    );
    parent.subCategories.add(child);
    library.subCategories.addAll([
      parent,
      Category(
        title: 'גלויה',
        description: '',
        shortDescription: '',
        order: 1,
        subCategories: [],
        books: [visibleBook],
        parent: library,
      ),
    ]);
    library.offTreeBooks = [version];
    final eligible = IndexingRepository.booksForIndexing(
      library.getIndexableBooks(),
      includePdfBooks: true,
      hidden: HiddenLibrarySelection(categoryPaths: {parent.path}),
      library: library,
    );

    expect(eligible, [visibleBook, version]);
  });

  test('שינוי הסתרה מחזיר רק ספרים שנחשפו ומסיר רק מי שהוסתר', () {
    final first = TextBook(title: 'א', categoryId: 1);
    final second = TextBook(title: 'ב', categoryId: 2);
    final offTree = TextBook(title: 'גרסה', categoryId: 3);
    final library = Library(categories: [])..books.addAll([first, second]);
    library.offTreeBooks = [offTree];

    final delta = hiddenIndexDelta(
      library,
      HiddenLibrarySelection(bookKeys: {PerBookSettings.bookKey(first)}),
      HiddenLibrarySelection(bookKeys: {PerBookSettings.bookKey(second)}),
    );

    expect(delta.newlyHidden, [second]);
    expect(delta.newlyVisible, [first]);
    expect(library.getIndexableBooks(), [first, second, offTree]);
  });

  test('בחירה מחלון עם מצב ישן שומרת הסתרה שנוספה בחלון הראשי', () {
    const stale = HiddenLibrarySelection();
    const owner = HiddenLibrarySelection(bookKeys: {'A'});
    const requested = HiddenLibrarySelection(bookKeys: {'B'});

    final merged = applyHiddenSelectionChange(owner, stale, requested);

    expect(merged.bookKeys, {'A', 'B'});
    expect(
      applyHiddenSelectionChange(
        merged,
        requested,
        const HiddenLibrarySelection(),
      ).bookKeys,
      {'A'},
    );
  });

  test('בקשות נראות חופפות מתבצעות לפי סדר בלי למחוק בחירה', () async {
    final updates = <String>[];
    final first = HiddenLibraryUpdateQueue.instance.run(() async {
      await Future<void>.delayed(Duration.zero);
      updates.add('A');
    });
    final second = HiddenLibraryUpdateQueue.instance.run(() async {
      updates.add('B');
    });
    await Future.wait([first, second]);
    expect(updates, ['A', 'B']);
  });
}
