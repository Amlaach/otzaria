import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/utils/text/ref_key.dart';
import 'package:path/path.dart' as path;

/// אינדקס ההפניות `line_ref` מקצה לקצה מול SQLite אמיתי: בנייה, lookup
/// מאונדקס מאומת, וטווח המפרשים של שורת מקור מדויקת.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MyDatabase db;
  late SeforimRepository repo;

  /// ישעיהו לב עם שלושה פסוקים, ומפרש שכל אחד מפסוקיו מקושר לפסוק אחר.
  Future<void> seed() async {
    final raw = await db.database;
    raw.execute(
      "INSERT OR IGNORE INTO connection_type (id, name) VALUES (99, 'COMMENTARY')",
    );
    final commentaryTypeId = raw
        .select("SELECT id FROM connection_type WHERE name = 'COMMENTARY'")
        .first['id'];
    raw.execute(
      "INSERT INTO book (id, categoryId, sourceId, title) "
      "VALUES (1, 1, 1, 'ישעיהו')",
    );
    raw.execute(
      "INSERT INTO book (id, categoryId, sourceId, title) "
      "VALUES (2, 1, 1, 'רש\"י על ישעיהו')",
    );
    const verses = [
      (10, 'ישעיהו לב, י'),
      (11, 'ישעיהו לב, יא'),
      (12, 'ישעיהו לב, יב'),
    ];
    for (final (lineIndex, heRef) in verses) {
      raw.execute(
        'INSERT INTO line (id, bookId, lineIndex, content, heRef) '
        'VALUES (?, 1, ?, ?, ?)',
        [100 + lineIndex, lineIndex, 'פסוק', heRef],
      );
      raw.execute(
        'INSERT INTO line (id, bookId, lineIndex, content, heRef) '
        'VALUES (?, 2, ?, ?, ?)',
        [200 + lineIndex, lineIndex, 'פירוש', 'רש"י על $heRef'],
      );
      raw.execute(
        'INSERT INTO link (sourceBookId, sourceLineId, targetLineId, '
        'targetBookId, connectionTypeId) VALUES (1, ?, ?, 2, ?)',
        [100 + lineIndex, 200 + lineIndex, commentaryTypeId],
      );
    }
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria-line-ref-');
    db = MyDatabase.withPath(path.join(tempDir.path, 'seforim.db'));
    repo = SeforimRepository(db);
    await repo.ensureInitialized();
    await seed();
    await repo.rebuildLineRefIndex(1);
  });

  tearDown(() async {
    db.close();
    await tempDir.delete(recursive: true);
  });

  test('הפניה לפסוק נפתרת לשורת הפסוק עצמה', () async {
    final resolved = await repo.resolveRefKeyInBook(1, buildRefKey('לב יא')!);
    expect(resolved?.lineIndex, 11);
    expect(resolved?.lineId, 111);
  });

  test('מילות מיקום וטווח מגיעות לאותה שורה', () async {
    for (final query in ['פרק לב פסוק יא', 'לב יא-יג', 'לב, יא']) {
      final resolved = await repo.resolveRefKeyInBook(1, buildRefKey(query)!);
      expect(resolved?.lineIndex, 11, reason: query);
    }
  });

  test('הפניה שאינה קיימת מחזירה null', () async {
    final resolved = await repo.resolveRefKeyInBook(1, buildRefKey('לב צט')!);
    expect(resolved, isNull);
  });

  test('התנגשות hash נדחית מול ה-heRef של השורה', () async {
    // מזריקים לאינדקס מפתח שמצביע לשורה שאינה תואמת לו.
    final raw = await db.database;
    raw.execute(
      'INSERT INTO line_ref (bookId, refKeyHash, lineIndex) VALUES (1, ?, 10)',
      [refKeyHash('לב צט')],
    );
    final resolved = await repo.resolveRefKeyInBook(1, buildRefKey('לב צט')!);
    expect(resolved, isNull);
  });

  test('שאילתה מאוגדת מחזירה את כל הספרים המועמדים', () async {
    await repo.rebuildLineRefIndex(2);
    final resolved = await repo.resolveRefKeyInBooks([1, 2], 'לב יא');
    expect(resolved[1]?.lineIndex, 11);
    // heRef של המפרש הוא "רש"י על ישעיהו לב, יא" — המפתח שלו זהה בזנבו.
    expect(resolved[2]?.lineIndex, 11);
  });

  test('שורת כותרת אינה נכנסת לאינדקס', () async {
    final raw = await db.database;
    raw.execute(
      "INSERT INTO line (id, bookId, lineIndex, content, heRef) "
      "VALUES (300, 1, 20, 'כותרת', 'ישעיהו')",
    );
    await repo.rebuildLineRefIndex(1);
    final rows = raw.select(
      'SELECT lineIndex FROM line_ref WHERE bookId = 1 AND lineIndex = 20',
    );
    expect(rows, isEmpty);
  });

  test('backfill בונה אינדקס לספר שנוצר לפני האינדקס', () async {
    final raw = await db.database;
    raw.execute('DELETE FROM line_ref');
    await repo.backfillMissingLineRefIndexes();

    final resolved = await repo.resolveRefKeyInBook(1, buildRefKey('לב יא')!);
    expect(resolved?.lineIndex, 11);
  });

  // issue #1346 — "טור שט ג": הפניה שהושמט ממנה שם החלק.
  group('מפתח חלקי', () {
    Future<void> seedTur() async {
      final raw = await db.database;
      raw.execute(
        "INSERT INTO book (id, categoryId, sourceId, title) "
        "VALUES (3, 1, 1, 'טור')",
      );
      const lines = [
        (5, 'טור, חושן משפט,  שט, ג'),
        // אותה הפניה בשתי שורות רצופות — מוצעת פעם אחת, מהשורה הראשונה.
        (6, 'טור, חושן משפט,  שט, ג'),
        (9, 'טור, יורה דעה,  שט, ג'),
        (12, 'טור, יורה דעה,  שי, א'),
      ];
      for (final (lineIndex, heRef) in lines) {
        raw.execute(
          'INSERT INTO line (id, bookId, lineIndex, content, heRef) '
          'VALUES (?, 3, ?, ?, ?)',
          [300 + lineIndex, lineIndex, 'טקסט', heRef],
        );
      }
    }

    test('מחזיר מועמד לכל חלק שבו ההפניה קיימת', () async {
      await seedTur();
      await repo.rebuildLineRefIndex(3);

      final resolved = await repo.resolvePartialRefKeyInBooks([
        3,
      ], buildPartialRefKey('שט ג')!);

      expect(resolved[3]!.map((c) => c.lineIndex), [5, 9]);
    });

    test('הפניה בחלק אחד בלבד מחזירה מועמד יחיד', () async {
      await seedTur();
      await repo.rebuildLineRefIndex(3);

      final resolved = await repo.resolvePartialRefKeyInBooks([
        3,
      ], buildPartialRefKey('שי א')!);

      expect(resolved[3]!.map((c) => c.lineIndex), [12]);
    });

    test('ספר בלי חלקים בעלי שם אינו מקבל מפתחות חלקיים', () async {
      final resolved = await repo.resolvePartialRefKeyInBooks([
        1,
      ], buildPartialRefKey('לב יא')!);
      expect(resolved, isEmpty);
    });

    test('backfill משלים מפתחות חלקיים לספר שנבנה בלעדיהם', () async {
      await seedTur();
      final raw = await db.database;
      // אינדקס כמו לפני השינוי: מפתחות מלאים בלבד.
      for (final (lineIndex, key) in [
        (5, 'חושן משפט שט ג'),
        (9, 'יורה דעה שט ג'),
      ]) {
        raw.execute(
          'INSERT INTO line_ref (bookId, refKeyHash, lineIndex) VALUES (3, ?, ?)',
          [refKeyHash(key), lineIndex],
        );
      }

      await repo.backfillMissingLineRefIndexes();

      final resolved = await repo.resolvePartialRefKeyInBooks([
        3,
      ], buildPartialRefKey('שט ג')!);
      expect(resolved[3]!.map((c) => c.lineIndex), [5, 9]);
    });
  });

  group('מפרשים על שורת מקור מדויקת', () {
    test('שורת מקור מדויקת מחזירה רק את המפרש על אותו פסוק', () async {
      final rows = await repo.getCommentatorsForReference(
        bookId: 1,
        bookTitle: 'ישעיהו',
        sourceLineId: 111,
        startLineIndex: 11,
        level: 3,
        isSourceLine: true,
      );
      expect(rows, hasLength(1));
      expect(rows.single['linkCount'], 1);
      expect(rows.single['targetLineIndex'], 11);
    });

    test('בלי הדגל נאסף כל הטווח עד הכותרת הבאה', () async {
      final rows = await repo.getCommentatorsForReference(
        bookId: 1,
        bookTitle: 'ישעיהו',
        sourceLineId: 111,
        startLineIndex: 10,
        level: 3,
      );
      expect(rows.single['linkCount'], 3);
    });
  });
}
