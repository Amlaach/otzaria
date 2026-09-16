import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/indexing/models/indexing_run_result.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/models/books.dart';

void main() {
  final pdf = PdfBook(title: 'ספר בדיקה', path: r'C:\books\test.pdf');

  group('IndexingRepository.classifyFailureForTesting', () {
    test('מסווג את RangeError המדויק של rotation כ-PDF לא נתמך', () {
      final failure = IndexingRepository.classifyFailureForTesting(
        pdf,
        RangeError.index(-1, const [0, 1, 2, 3], 'rotation'),
      );

      expect(failure.kind, IndexingFailureKind.pdfUnsupported);
      expect(failure.isRetryable, isFalse);
    });

    test('RangeError רגיל אינו מסווג בטעות כבעיית PDF קבועה', () {
      final failure = IndexingRepository.classifyFailureForTesting(
        pdf,
        RangeError.index(9, const [0, 1], 'page'),
      );

      expect(failure.kind, IndexingFailureKind.unknown);
      expect(failure.isRetryable, isTrue);
    });

    test('כשל פתיחת PDF לא מוכר מסווג כלא נתמך ולא חוזר לנצח', () {
      final failure = IndexingRepository.classifyPdfExtractionFailureForTesting(
        pdf,
        Exception('unknown PDFium open error'),
      );

      expect(failure.kind, IndexingFailureKind.pdfUnsupported);
      expect(failure.isRetryable, isFalse);
      expect(failure.error, contains('unknown PDFium open error'));
    });

    for (final message in [
      'PdfException: No password supplied by PasswordProvider.',
      'password required to open document',
      'incorrect password',
    ]) {
      test('מסווג כשל סיסמה: $message', () {
        final failure = IndexingRepository.classifyFailureForTesting(
          pdf,
          Exception(message),
        );

        expect(failure.kind, IndexingFailureKind.passwordProtected);
        expect(failure.isRetryable, isFalse);
      });
    }

    for (final message in [
      'Access is denied. (os error 5)',
      'Permission denied',
      'operation not permitted',
    ]) {
      test('מסווג כשל הרשאה שאינו חוזר אוטומטית: $message', () {
        final failure = IndexingRepository.classifyFailureForTesting(
          pdf,
          Exception(message),
        );

        expect(failure.kind, IndexingFailureKind.permissionDenied);
        expect(failure.isRetryable, isFalse);
      });
    }

    test('מסווג TimeoutException ככשל חולף שראוי לניסיון חוזר', () {
      final failure = IndexingRepository.classifyFailureForTesting(
        pdf,
        TimeoutException('open timed out'),
      );

      expect(failure.kind, IndexingFailureKind.timeout);
      expect(failure.isRetryable, isTrue);
    });

    test('חריגת זמן בפתיחת PDF אינה חוזרת בכל עלייה', () {
      final failure = IndexingRepository.classifyPdfExtractionFailureForTesting(
        pdf,
        TimeoutException('open timed out'),
      );

      expect(failure.kind, IndexingFailureKind.unreadableDocument);
      expect(failure.isRetryable, isFalse);
    });

    test('גם הודעת timeout עטופה מפתיחת PDF אינה חוזרת', () {
      final failure = IndexingRepository.classifyPdfExtractionFailureForTesting(
        pdf,
        Exception('Future timed out after 0:01:00'),
      );

      expect(failure.isRetryable, isFalse);
    });

    test('מסווג הודעת timeout גם כשהחריגה עטופה', () {
      final failure = IndexingRepository.classifyFailureForTesting(
        pdf,
        Exception('Future timed out after 0:01:00'),
      );

      expect(failure.kind, IndexingFailureKind.timeout);
    });

    test('שומר כותרת, נתיב, שגיאה ו-stack', () {
      final stack = StackTrace.fromString('pdf-stack');
      final failure = IndexingRepository.classifyFailureForTesting(
        pdf,
        Exception('unknown failure'),
        stack,
      );

      expect(failure.bookTitle, 'ספר בדיקה');
      expect(failure.bookPath, r'C:\books\test.pdf');
      expect(failure.error, contains('unknown failure'));
      expect(failure.stackTrace, 'pdf-stack');
    });

    test('ספר טקסט ללא נתיב מקבל מפתח קטלוגי יציב', () {
      final book = TextBook(id: 42, title: 'ספר טקסט');
      final failure = IndexingRepository.classifyFailureForTesting(
        book,
        Exception('failure'),
      );

      expect(failure.bookPath, 'id:42');
    });
  });
}
