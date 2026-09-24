import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/library/hidden/hidden_library_store.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;

/// מסנן יעדי קישורים לפי זהות הספר; שם לבדו אינו מבחין בין מהדורות.
class PdfCommentaryVisibility {
  static Library? _cachedLibrary;
  static HiddenLibrarySelection? _cachedSelection;
  static PdfCommentaryVisibility? _cachedVisibility;

  PdfCommentaryVisibility.empty() : selection = const HiddenLibrarySelection();

  PdfCommentaryVisibility(this.selection, Library library) {
    if (selection.isEmpty) return;
    final hiddenByCategory = selection.booksHiddenByCategory(library);
    for (final book in library.getIndexableBooks()) {
      final key = (book.source, book.title);
      _booksByTitle.putIfAbsent(key, () => []).add(book);
      if (selection.excludesFromIndex(
        book,
        categoryHiddenBooks: hiddenByCategory,
      )) {
        _hiddenBooks.add(book);
      }
    }
  }

  final HiddenLibrarySelection selection;
  final Map<(BookSource, String), List<Book>> _booksByTitle = {};
  final Set<Book> _hiddenBooks = {};

  static Future<PdfCommentaryVisibility> current() async {
    final selection = const HiddenLibraryStore().load();
    if (selection.isEmpty) return PdfCommentaryVisibility.empty();
    final library = await DataRepository.instance.library;
    if (identical(library, _cachedLibrary) && selection == _cachedSelection) {
      return _cachedVisibility!;
    }
    _cachedLibrary = library;
    _cachedSelection = selection;
    return _cachedVisibility = PdfCommentaryVisibility(selection, library);
  }

  bool allowsLink(Link link) => _allows(
    utils.getTitleFromPath(link.path2),
    link.targetSource,
    bookId: link.targetBookId,
    categoryId: link.targetCategoryId,
  );

  bool allowsSummary(LinkTargetSummary target, BookSource source) => _allows(
    utils.getTitleFromPath(target.targetTitle),
    target.targetSource ?? source,
  );

  bool _allows(
    String title,
    BookSource source, {
    int? bookId,
    int? categoryId,
  }) {
    if (selection.isEmpty) return true;
    final candidates = _booksByTitle[(source, title)];
    if (candidates == null || candidates.isEmpty) return true;
    if (bookId != null) {
      final exact = candidates.where((book) => book.id == bookId).toList();
      if (exact.isNotEmpty) {
        return exact.any((book) => !_hiddenBooks.contains(book));
      }
    }
    if (categoryId != null) {
      final exact = candidates
          .where((book) => book.categoryId == categoryId)
          .toList();
      if (exact.isNotEmpty) {
        return exact.any((book) => !_hiddenBooks.contains(book));
      }
    }
    return candidates.any((book) => !_hiddenBooks.contains(book));
  }
}

/// שומר את זהות רשימת הקישורים כדי שמטמון סוגי המפרשים יוכל לפגוע.
class PdfCommentaryVisibleLinksCache {
  List<Link>? _source;
  PdfCommentaryVisibility? _visibility;
  List<Link>? _visible;

  List<Link> forSource(List<Link> source, PdfCommentaryVisibility visibility) {
    if (visibility.selection.isEmpty) return source;
    if (identical(source, _source) && identical(visibility, _visibility)) {
      return _visible!;
    }
    _source = source;
    _visibility = visibility;
    return _visible = source.where(visibility.allowsLink).toList();
  }
}
