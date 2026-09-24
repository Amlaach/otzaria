import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';

/// צילום זהויות הספרים המוסתרים לחיפוש, שנבנה רק כשבחירת ההסתרה משתנה.
class FindRefVisibility {
  FindRefVisibility.empty() : selection = const HiddenLibrarySelection();

  FindRefVisibility(this.selection, Library library) {
    if (selection.isEmpty) return;
    final categoryHidden = selection.booksHiddenByCategory(library);
    for (final book in library.getIndexableBooks()) {
      final hidden = selection.excludesFromIndex(
        book,
        categoryHiddenBooks: categoryHidden,
      );
      if (hidden) {
        _hiddenBooks.add(book);
        if (book is FileBook) {
          if (book.id != null) {
            _hiddenFileIds.add((book.source, book.id!, book.fileType ?? ''));
          }
          _hiddenPaths.add((book.source, book.path));
        } else if (book.id != null) {
          _hiddenTextIds.add((book.source, book.id!));
        }
        if (book is TextBook && book.source.isOfficial) {
          _hiddenTitles.add(book.title);
        }
      }
    }
  }

  final HiddenLibrarySelection selection;
  final Set<Book> _hiddenBooks = {};
  final Set<(BookSource, int)> _hiddenTextIds = {};
  final Set<(BookSource, int, String)> _hiddenFileIds = {};
  final Set<(BookSource, String)> _hiddenPaths = {};
  final Set<String> _hiddenTitles = {};

  bool allowsBook(Book book) => !_hiddenBooks.contains(book);

  bool allowsCandidate(
    BookSource source,
    int bookId,
    String filePath, {
    String fileType = 'txt',
  }) =>
      (filePath.isEmpty || !_hiddenPaths.contains((source, filePath))) &&
      (bookId <= 0 ||
          (fileType == 'txt'
              ? !_hiddenTextIds.contains((source, bookId))
              : !_hiddenFileIds.contains((source, bookId, fileType))));

  bool allowsCommentator(String title, int? bookId) {
    if (bookId != null && bookId > 0) {
      return !_hiddenTextIds.contains((BookSource.official, bookId));
    }
    return !_hiddenTitles.contains(title);
  }
}
