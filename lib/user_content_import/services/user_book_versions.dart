import 'package:otzaria/models/book_version.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/user_content_import/models/user_import_models.dart';

/// קבוצת הגרסאות של הספר האישי [bookId] — הראשית תחילה, ואחריה לפי עדיפות
/// ושם. ריק כשהספר אינו בקבוצה, או כשהגרסה הראשית אינה בקטלוג.
List<BookVersionInfo> buildUserBookVersions({
  required int bookId,
  required List<UserBookVersionRecord> records,
  required Map<int, Book> booksById,
}) {
  final primaryId =
      records
          .where((v) => v.versionBookId == bookId)
          .firstOrNull
          ?.primaryBookId ??
      bookId;
  final members = records
      .where(
        (v) => v.primaryBookId == primaryId && v.versionBookId != primaryId,
      )
      .toList();
  final primary = booksById[primaryId];
  if (members.isEmpty || primary == null) return const [];

  members.sort((a, b) {
    final byPriority = (b.priority ?? 0).compareTo(a.priority ?? 0);
    return byPriority != 0
        ? byPriority
        : a.versionTitle.compareTo(b.versionTitle);
  });
  final primaryRow = records
      .where((v) => v.versionBookId == primaryId)
      .firstOrNull;
  return [
    BookVersionInfo(
      versionTitle: primaryRow?.versionTitle ?? primary.title,
      heVersionNotes: primaryRow?.versionNotes,
      hasContent: true,
      userBook: primary,
    ),
    for (final member in members)
      if (booksById[member.versionBookId] case final target?)
        BookVersionInfo(
          versionTitle: member.versionTitle,
          heVersionNotes: member.versionNotes,
          priority: member.priority,
          hasContent: true,
          userBook: target,
        ),
  ];
}
