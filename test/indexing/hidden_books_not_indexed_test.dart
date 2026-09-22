import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
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
}
