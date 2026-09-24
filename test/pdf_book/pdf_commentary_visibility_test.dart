import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/pdf_book/utils/pdf_commentary_visibility.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';

Link _link(int? id, {int? categoryId}) => Link(
  heRef: 'א',
  index1: 1,
  path2: 'מפרש',
  index2: 1,
  connectionType: 'COMMENTARY',
  targetBookId: id,
  targetCategoryId: categoryId,
);

void main() {
  test('ספר מוסתר מסונן לפי מזהה, וכפילות גלויה נשארת', () {
    final first = Category(
      title: 'ראשונים',
      description: '',
      shortDescription: '',
      order: 0,
      subCategories: [],
      books: [],
      parent: null,
    );
    final second = Category(
      title: 'אחרונים',
      description: '',
      shortDescription: '',
      order: 0,
      subCategories: [],
      books: [],
      parent: null,
    );
    final hidden = TextBook(
      id: 1,
      title: 'מפרש',
      category: first,
      categoryId: 10,
    );
    final visible = TextBook(
      id: 2,
      title: 'מפרש',
      category: second,
      categoryId: 20,
    );
    first.books.add(hidden);
    second.books.add(visible);
    final library = Library(categories: [first, second]);
    first.parent = library;
    second.parent = library;
    final visibility = PdfCommentaryVisibility(
      HiddenLibrarySelection(bookKeys: {PerBookSettings.bookKey(hidden)}),
      library,
    );

    expect(visibility.allowsLink(_link(1)), isFalse);
    expect(visibility.allowsLink(_link(2)), isTrue);
    expect(visibility.allowsLink(_link(null, categoryId: 10)), isFalse);
    expect(visibility.allowsLink(_link(null)), isTrue);
    final cache = PdfCommentaryVisibleLinksCache();
    final links = [_link(1), _link(2)];
    final filtered = cache.forSource(links, visibility);
    expect(filtered, [links.last]);
    expect(identical(cache.forSource(links, visibility), filtered), isTrue);
    expect(
      identical(
        cache.forSource(links, PdfCommentaryVisibility.empty()),
        links,
      ),
      isTrue,
    );
    expect(
      visibility.allowsSummary(
        const LinkTargetSummary(
          targetTitle: 'מפרש',
          connectionType: 'COMMENTARY',
          linkCount: 1,
        ),
        hidden.source,
      ),
      isTrue,
    );
  });

  test('קטגוריה מוסתרת מסננת גם ספר בלי category בשדה הספר', () {
    final category = Category(
      title: 'ראשונים',
      description: '',
      shortDescription: '',
      order: 0,
      subCategories: [],
      books: [TextBook(id: 1, title: 'מפרש', categoryId: 10)],
      parent: null,
    );
    final library = Library(categories: [category]);
    category.parent = library;
    final visibility = PdfCommentaryVisibility(
      const HiddenLibrarySelection(categoryPaths: {'/ראשונים'}),
      library,
    );

    expect(visibility.allowsLink(_link(1)), isFalse);
  });
}
