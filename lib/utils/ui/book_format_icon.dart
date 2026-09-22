import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/utils/book_versions_action.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/utils/file/document_format.dart';

/// אייקון הספר לפי פורמט המסמך — מקור יחיד לכל רשימות הספרייה, תוצאות
/// החיפוש, ההיסטוריה והתצוגות המקדימות.
///
/// הפורמט קודם למחלקת הספר: רשומות היסטוריה ותיקות של ספרי מסמך נשמרו
/// כ-`PdfBook`, ורק הנתיב מגלה שאינן PDF.
IconData bookFormatIcon(Book book) {
  final path = book is FileBook ? book.path : book.filePath;
  // הסיומת קודמת ל-`fileType`: ‏`PdfBook.fileType` הוא ברירת מחדל של הבנאי
  // ולא עובדה שנשמרה, ולכן ספר מסמך שנשמר בהיסטוריה כ-PdfBook היה מוצג
  // כ-PDF לנצח.
  final format =
      (path == null ? null : documentFormatFromExtension(path)) ??
      documentFormatFromFileType(book.fileType);
  if (format == null) {
    return book is PdfBook
        ? OtzariaIcons.book_pdf_24_regular
        : _plainTextIcon(book);
  }
  if (format == DocumentFormat.pdf) return OtzariaIcons.book_pdf_24_regular;
  if (format.isWordDocument) return OtzariaIcons.document_word_24_regular;
  if (format.isHtmlDocument) return OtzariaIcons.document_html_24_regular;
  if (book.isUserBook &&
      (format == DocumentFormat.md || format == DocumentFormat.markdown)) {
    return OtzariaIcons.document_md_24_regular;
  }
  return _plainTextIcon(book);
}

/// ספרי הספרייה הרשמית הם כולם טקסט, ולכן הפורמט אינו מבדיל ביניהם והם
/// נושאים את המסמך הגנרי. בספר אישי הפורמט הוא מידע — שם `document_alef`
/// אומר "טקסט", לצד `document_md`, `document_word` ו-`document_html`.
IconData _plainTextIcon(Book book) => book.isUserBook
    ? OtzariaIcons.document_alef_24_regular
    : FluentIcons.document_text_24_regular;

/// אייקון הספר ברשימות הספרייה. ספר שיש לו מהדורות נוספות לבחירה מקבל את
/// `document_multiple` במקום אייקון הפורמט — אותה בדיקה בדיוק שמציגה לו את
/// פריט "גרסאות" בתפריט השורה, כך שהאייקון והתפריט לעולם אינם סותרים.
///
/// הבדיקה היא שאילתת DB, ולכן היא מורצת פעם אחת לכל ספר ונשמרת ב-state:
/// [FutureBuilder] שנבנה מחדש בכל `build` היה מריץ אותה בכל גלילה.
class BookFormatIcon extends StatefulWidget {
  const BookFormatIcon({
    super.key,
    required this.book,
    this.color,
    this.size,
  });

  final Book book;
  final Color? color;
  final double? size;

  @override
  State<BookFormatIcon> createState() => _BookFormatIconState();
}

class _BookFormatIconState extends State<BookFormatIcon> {
  late Future<bool> _hasVersions;

  @override
  void initState() {
    super.initState();
    _hasVersions = hasBookVersionsToOpen(widget.book);
  }

  /// הזהות שעליה נשענת השאילתה. שורת רשימה ממוחזרת נקשרת לספר אחר בלי
  /// שה-state נבנה מחדש, ולכן ההשוואה חייבת לכסות *כל* שדה ש-
  /// [hasBookVersionsToOpen] קורא — ולא רק את המזהה והשם. בספרייה
  /// מבוססת-קבצים `id` הוא null בכל הספרים ושם זהה חוזר בשתי קטגוריות,
  /// וספר רשמי וספר אישי יכולים לחלוק שם ומזהה — בכל אחד מהמקרים האלה
  /// הושארה הדגל של הספר הקודם.
  static List<Object?> _versionsKey(Book book) => [
    book.id,
    book.title,
    book.isUserBook,
    book.categoryId,
    book is TextBook ? book.versionTitle : null,
    book.runtimeType,
  ];

  @override
  void didUpdateWidget(BookFormatIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(_versionsKey(oldWidget.book), _versionsKey(widget.book))) {
      _hasVersions = hasBookVersionsToOpen(widget.book);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasVersions,
      builder: (context, snapshot) {
        final icon = snapshot.data == true
            ? FluentIcons.document_multiple_24_regular
            : bookFormatIcon(widget.book);
        return Icon(icon, color: widget.color, size: widget.size);
      },
    );
  }
}
