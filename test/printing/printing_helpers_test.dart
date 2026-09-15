import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/printing/printing_helpers.dart';
import 'package:pdfrx/pdfrx.dart';

/// Stub פשוט של PdfOutlineNode לטסטים, ללא תלות במסמך אמיתי.
class _FakeOutlineNode implements PdfOutlineNode {
  @override
  final String title;
  final int? page;
  @override
  final List<PdfOutlineNode> children;

  _FakeOutlineNode({
    required this.title,
    this.page,
    this.children = const [],
  });

  @override
  PdfDest? get dest =>
      page == null ? null : PdfDest(page!, PdfDestCommand.fitB, null);
}

void main() {
  group('buildPdfPageLabels', () {
    test('outline ריק מחזיר מפה ריקה', () {
      expect(buildPdfPageLabels([]), isEmpty);
    });

    test('node ברמה ראשונה ממופה לעמוד שלו', () {
      final outline = [
        _FakeOutlineNode(title: 'דף ב.', page: 2),
        _FakeOutlineNode(title: 'דף ג.', page: 3),
      ];
      final labels = buildPdfPageLabels(outline);
      expect(labels[2], 'דף ב.');
      expect(labels[3], 'דף ג.');
    });

    test('עוברת רקורסיבית על children', () {
      final outline = [
        _FakeOutlineNode(
          title: 'פרק ראשון',
          page: 1,
          children: [
            _FakeOutlineNode(title: 'משנה א', page: 5),
            _FakeOutlineNode(title: 'משנה ב', page: 8),
          ],
        ),
      ];
      final labels = buildPdfPageLabels(outline);
      expect(labels[1], 'פרק ראשון');
      expect(labels[5], 'משנה א');
      expect(labels[8], 'משנה ב');
    });

    test('כשיש שני nodes על אותו עמוד נשמרת רק התווית הראשונה', () {
      final outline = [
        _FakeOutlineNode(title: 'ראשון', page: 7),
        _FakeOutlineNode(title: 'שני', page: 7),
      ];
      final labels = buildPdfPageLabels(outline);
      expect(labels[7], 'ראשון');
    });

    test('מתעלם מ-nodes ללא dest', () {
      final outline = [
        _FakeOutlineNode(title: 'אין dest'), // page=null
        _FakeOutlineNode(title: 'יש dest', page: 4),
      ];
      final labels = buildPdfPageLabels(outline);
      expect(labels.containsKey(4), isTrue);
      expect(labels.length, 1);
    });

    test('מתעלם מ-nodes עם title ריק', () {
      final outline = [
        _FakeOutlineNode(title: '', page: 4),
        _FakeOutlineNode(title: 'תקין', page: 5),
      ];
      final labels = buildPdfPageLabels(outline);
      expect(labels.containsKey(4), isFalse);
      expect(labels[5], 'תקין');
    });
  });

  group('labelForPdfPage', () {
    test('מחזיר את התווית כשהעמוד קיים במפה', () {
      final labels = {2: 'דף ב.', 3: 'דף ג.'};
      expect(labelForPdfPage(labels, 2), 'דף ב.');
      expect(labelForPdfPage(labels, 3), 'דף ג.');
    });

    test('מחזיר את מספר העמוד כשאין תווית', () {
      final labels = {2: 'דף ב.'};
      expect(labelForPdfPage(labels, 5), '5');
    });

    test('מחזיר מספר עבור מפה ריקה', () {
      expect(labelForPdfPage(<int, String>{}, 1), '1');
      expect(labelForPdfPage(<int, String>{}, 100), '100');
    });
  });

  group('computePdfPrintEndPage', () {
    test('מחזיר null כשלא במצב PDF', () {
      expect(
        computePdfPrintEndPage(
          isPdfMode: false,
          pdfEndPage: 50,
          totalPdfPages: 100,
        ),
        isNull,
      );
    });

    test('מחזיר null כש-pdfEndPage הוא 0 (לא נקבע)', () {
      expect(
        computePdfPrintEndPage(
          isPdfMode: true,
          pdfEndPage: 0,
          totalPdfPages: 100,
        ),
        isNull,
      );
    });

    test('מחזיר null כש-pdfEndPage שלילי', () {
      expect(
        computePdfPrintEndPage(
          isPdfMode: true,
          pdfEndPage: -3,
          totalPdfPages: 100,
        ),
        isNull,
      );
    });

    test('מחזיר את pdfEndPage כשהוא בתוך טווח המסמך', () {
      expect(
        computePdfPrintEndPage(
          isPdfMode: true,
          pdfEndPage: 36,
          totalPdfPages: 125,
        ),
        36,
      );
    });

    test('מחזיר את pdfEndPage כשהוא שווה ל-totalPdfPages (העמוד האחרון)', () {
      // הבאג שתוקן: <= במקום <
      expect(
        computePdfPrintEndPage(
          isPdfMode: true,
          pdfEndPage: 125,
          totalPdfPages: 125,
        ),
        125,
      );
    });

    test('מחזיר null כש-pdfEndPage חורג מ-totalPdfPages', () {
      expect(
        computePdfPrintEndPage(
          isPdfMode: true,
          pdfEndPage: 200,
          totalPdfPages: 125,
        ),
        isNull,
      );
    });

    test('סומך על pdfEndPage כש-totalPdfPages עדיין 0 (טרם נטען המסמך)', () {
      // נדרש כדי שה-render הראשון ב-initState יצליח לפני שהמסמך נפתח.
      expect(
        computePdfPrintEndPage(
          isPdfMode: true,
          pdfEndPage: 36,
          totalPdfPages: 0,
        ),
        36,
      );
    });
  });

  group('findLastHeaderIndexAtOrBefore', () {
    // helper לבניית רשימת כותרות עם שורות בלבד (level/text אינם משנים פה)
    List<TocEntry> headers(List<int> lineIndices) =>
        lineIndices.map((i) => TocEntry(text: 'h$i', index: i)).toList();

    test('רשימה ריקה מחזירה 0', () {
      expect(findLastHeaderIndexAtOrBefore(const [], 50), 0);
    });

    test('שורה לפני הכותרת הראשונה מחזירה 0', () {
      // כל הכותרות אחרי השורה - fallback לאינדקס 0
      final h = headers([10, 20, 30]);
      expect(findLastHeaderIndexAtOrBefore(h, 5), 0);
    });

    test('שורה בדיוק על כותרת מחזירה את האינדקס שלה', () {
      final h = headers([10, 20, 30]);
      expect(findLastHeaderIndexAtOrBefore(h, 10), 0);
      expect(findLastHeaderIndexAtOrBefore(h, 20), 1);
      expect(findLastHeaderIndexAtOrBefore(h, 30), 2);
    });

    test('שורה באמצע סעיף מחזירה את הכותרת שמעליה', () {
      final h = headers([10, 20, 30]);
      expect(findLastHeaderIndexAtOrBefore(h, 15), 0);
      expect(findLastHeaderIndexAtOrBefore(h, 25), 1);
      expect(findLastHeaderIndexAtOrBefore(h, 100), 2);
    });

    test('כותרת יחידה — תמיד מחזירה 0', () {
      final h = headers([42]);
      expect(findLastHeaderIndexAtOrBefore(h, 0), 0);
      expect(findLastHeaderIndexAtOrBefore(h, 42), 0);
      expect(findLastHeaderIndexAtOrBefore(h, 999), 0);
    });
  });

  group('hasPdfPageRange', () {
    test('startPage=1 ו-endPage=null → אין טווח', () {
      expect(hasPdfPageRange(startPage: 1, endPage: null), isFalse);
    });

    test('startPage>1 → יש טווח', () {
      expect(hasPdfPageRange(startPage: 2, endPage: null), isTrue);
      expect(hasPdfPageRange(startPage: 100, endPage: null), isTrue);
    });

    test('endPage מוגדר → יש טווח', () {
      expect(hasPdfPageRange(startPage: 1, endPage: 50), isTrue);
    });

    test('שניהם מוגדרים → יש טווח', () {
      expect(hasPdfPageRange(startPage: 30, endPage: 50), isTrue);
    });

    test('טווח עד העמוד האחרון במסמך → אין טווח (issue #1369)', () {
      expect(
        hasPdfPageRange(startPage: 1, endPage: 125, totalPages: 125),
        isFalse,
      );
    });

    test('טווח שנגמר לפני העמוד האחרון → יש טווח', () {
      expect(
        hasPdfPageRange(startPage: 1, endPage: 124, totalPages: 125),
        isTrue,
      );
      expect(
        hasPdfPageRange(startPage: 2, endPage: 125, totalPages: 125),
        isTrue,
      );
    });
  });

  group('pdfPageRangeSummary', () {
    test('עמוד אחד בגיליון — בלי תוספת גיליונות', () {
      expect(
        pdfPageRangeSummary(
          startPage: 1,
          endPage: 4,
          totalPages: 4,
          pagesPerSheet: 1,
        ),
        '4 עמודים מתוך 4',
      );
    });

    test('2 בגיליון — מציג את מספר הגיליונות בפועל (issue #817)', () {
      expect(
        pdfPageRangeSummary(
          startPage: 1,
          endPage: 4,
          totalPages: 4,
          pagesPerSheet: 2,
        ),
        '4 עמודים מתוך 4 (2 גיליונות)',
      );
    });

    test('טווח שאינו מתחלק — מעגל כלפי מעלה', () {
      expect(
        pdfPageRangeSummary(
          startPage: 1,
          endPage: 3,
          totalPages: 4,
          pagesPerSheet: 2,
        ),
        '3 עמודים מתוך 4 (2 גיליונות)',
      );
    });

    test('כל הטווח נכנס בגיליון אחד — לשון יחיד', () {
      expect(
        pdfPageRangeSummary(
          startPage: 3,
          endPage: 4,
          totalPages: 4,
          pagesPerSheet: 4,
        ),
        '2 עמודים מתוך 4 (גיליון אחד)',
      );
    });
  });
}
