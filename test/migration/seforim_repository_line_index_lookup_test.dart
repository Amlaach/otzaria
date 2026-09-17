// בדיקות ל-`lineIndex` של ערכי TOC/AltToc, אחרי שהשליפה שלו עברה מ-JOIN
// לטבלת `line` אל האינדקס המכסה `idx_line_book_index`.
//
// ה-JOIN קרא עמוד 16KB מלא של טקסט הספר לכל ערך TOC (185MB לחימום ה-AltToc
// הגלובלי, 217MB ל-50 ספרי מועמד) — כאן מאומת שהתוצאה זהה, כולל מקרי הקצה
// שה-COALESCE טיפל בהם, ושמסלול הנסיגה עובד כשהאינדקס חסר.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/category.dart';
import 'package:otzaria/migration/models/line.dart';
import 'package:otzaria/migration/models/toc_entry.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MyDatabase database;
  late SeforimRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('line-index-lookup-');
    database = MyDatabase.withPath(path.join(tempDir.path, 'test.db'));
    repository = SeforimRepository(database);
    await repository.ensureInitialized();
  });

  tearDown(() async {
    database.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<int> createBook(String title) async {
    final categoryId = await repository.insertCategory(
      const Category(title: 'קטגוריה', parentId: null, level: 0),
    );
    return repository.insertExternalContentBook(
      categoryId: categoryId,
      title: title,
      filePath: '/tmp/$title.txt',
      fileType: 'txt',
      fileSize: 0,
      lastModified: 0,
      isPersonal: false,
    );
  }

  /// מכניס שורות ומחזיר את מזהי ה-`line` לפי סדר ה-lineIndex.
  Future<List<int>> insertLines(int bookId, int count) async {
    final ids = <int>[];
    for (var i = 0; i < count; i++) {
      ids.add(
        await repository.insertLine(
          Line(id: 0, bookId: bookId, lineIndex: i, content: 'שורה $i'),
        ),
      );
    }
    return ids;
  }

  Future<int> insertToc({
    required int bookId,
    required String text,
    required int level,
    int? lineId,
    int? parentId,
  }) => repository.insertTocEntry(
    TocEntry(
      id: 0,
      bookId: bookId,
      parentId: parentId,
      text: text,
      level: level,
      lineId: lineId,
    ),
  );

  Future<int> insertAltEntry({
    required int structureId,
    required String text,
    required int level,
    int? lineId,
    int? parentId,
  }) async {
    final db = await database.database;
    db.execute('INSERT INTO tocText (text) VALUES (?)', [text]);
    final textId = db.lastInsertRowId;
    db.execute(
      'INSERT INTO alt_toc_entry (structureId, parentId, textId, level, lineId) '
      'VALUES (?, ?, ?, ?, ?)',
      [structureId, parentId, textId, level, lineId],
    );
    return db.lastInsertRowId;
  }

  Future<int> insertAltStructure(int bookId) async {
    final db = await database.database;
    db.execute(
      "INSERT INTO alt_toc_structure (bookId, key, title) "
      "VALUES (?, 'alt', 'alt')",
      [bookId],
    );
    return db.lastInsertRowId;
  }

  group('TOC רגיל', () {
    test('lineIndex נלקח מהשורה שאליה מצביע lineId', () async {
      final bookId = await createBook('ספר');
      final lineIds = await insertLines(bookId, 5);
      await insertToc(
        bookId: bookId,
        text: 'פרק א',
        level: 1,
        lineId: lineIds[1],
      );
      await insertToc(
        bookId: bookId,
        text: 'פרק ב',
        level: 1,
        lineId: lineIds[4],
      );

      final entries = await repository.getTocEntriesForReference(
        bookId,
        'ספר',
      );
      expect(entries.map((e) => e['segment']), [1, 4]);
      expect(entries.map((e) => e['dbLineId']), [lineIds[1], lineIds[4]]);
    });

    test('הסדר הוא לפי lineIndex ואז level', () async {
      final bookId = await createBook('ספר');
      final lineIds = await insertLines(bookId, 4);
      await insertToc(
        bookId: bookId,
        text: 'מאוחר',
        level: 1,
        lineId: lineIds[3],
      );
      final parent = await insertToc(
        bookId: bookId,
        text: 'מוקדם',
        level: 1,
        lineId: lineIds[1],
      );
      await insertToc(
        bookId: bookId,
        text: 'בן',
        level: 2,
        lineId: lineIds[1],
        parentId: parent,
      );

      final entries = await repository.getTocEntriesForReference(
        bookId,
        'ספר',
      );
      expect(entries.map((e) => e['segment']), [1, 1, 3]);
      expect(entries.map((e) => e['level']), [1, 2, 1]);
    });

    test('lineId ריק נותן segment 0', () async {
      final bookId = await createBook('ספר');
      await insertLines(bookId, 2);
      await insertToc(bookId: bookId, text: 'ללא שורה', level: 1);

      final entries = await repository.getTocEntriesForReference(
        bookId,
        'ספר',
      );
      expect(entries.single['segment'], 0);
      expect(entries.single['dbLineId'], 0);
    });

    test('lineId שמצביע לשורה חסרה נופל ל-lineId עצמו', () async {
      final bookId = await createBook('ספר');
      final lineIds = await insertLines(bookId, 2);
      final danglingId = lineIds.last + 5000;
      final db = await database.database;
      db.execute(
        'INSERT INTO tocEntry (bookId, parentId, textId, level, lineId) '
        "SELECT ?, NULL, id, 1, ? FROM tocText WHERE text = 'יתום'",
        [bookId, danglingId],
      );
      db.execute("INSERT INTO tocText (text) VALUES ('יתום')");
      db.execute(
        'INSERT INTO tocEntry (bookId, parentId, textId, level, lineId) '
        'VALUES (?, NULL, ?, 1, ?)',
        [bookId, db.lastInsertRowId, danglingId],
      );

      final entries = await repository.getTocEntriesForReference(
        bookId,
        'ספר',
      );
      expect(entries.single['segment'], danglingId);
    });
  });

  group('AltToc', () {
    test('lineIndex נלקח מהשורה, ו-lineId חסר נותן 0', () async {
      final bookId = await createBook('טור');
      final lineIds = await insertLines(bookId, 6);
      final structureId = await insertAltStructure(bookId);
      final parent = await insertAltEntry(
        structureId: structureId,
        text: 'חושן משפט',
        level: 0,
        lineId: lineIds[2],
      );
      await insertAltEntry(
        structureId: structureId,
        text: 'הלכות הלואה',
        level: 1,
        lineId: lineIds[5],
        parentId: parent,
      );
      await insertAltEntry(
        structureId: structureId,
        text: 'הלכות דיינים',
        level: 1,
        parentId: parent,
      );

      Future<Map<String, dynamic>> lookup(String token) async {
        final entries = await repository.getAltTocEntriesForReference(
          bookId,
          'טור',
          queryTokens: [token],
        );
        return entries.single;
      }

      expect((await lookup('משפט'))['segment'], 2);
      expect((await lookup('הלואה'))['segment'], 5);
      // ערך בלי lineId — כמו ה-COALESCE הישן, נופל ל-0.
      expect((await lookup('דיינים'))['segment'], 0);
    });

    test('הרשימה השטוחה הגלובלית מחזירה את אותם segments', () async {
      final bookId = await createBook('טור');
      final lineIds = await insertLines(bookId, 6);
      final structureId = await insertAltStructure(bookId);
      final parent = await insertAltEntry(
        structureId: structureId,
        text: 'חושן משפט',
        level: 0,
        lineId: lineIds[2],
      );
      await insertAltEntry(
        structureId: structureId,
        text: 'הלכות הלואה',
        level: 1,
        lineId: lineIds[5],
        parentId: parent,
      );
      await insertAltEntry(
        structureId: structureId,
        text: 'הלכות דיינים',
        level: 1,
        parentId: parent,
      );

      final flat = await repository.getAllAltTocFlatEntries();
      final segments = {
        for (final e in flat) e['reference'] as String: e['segment'],
      };
      expect(segments['חושן משפט'], 2);
      expect(segments['חושן משפט הלכות הלואה'], 5);
      expect(segments['חושן משפט הלכות דיינים'], 0);
      expect(
        flat.every((e) => e['bookId'] == bookId),
        isTrue,
      );
    });
  });

  test('בלי idx_line_book_index — אותן תוצאות דרך מסלול הנסיגה', () async {
    final bookId = await createBook('ספר');
    final lineIds = await insertLines(bookId, 5);
    await insertToc(
      bookId: bookId,
      text: 'פרק א',
      level: 1,
      lineId: lineIds[3],
    );
    final structureId = await insertAltStructure(bookId);
    await insertAltEntry(
      structureId: structureId,
      text: 'חלק',
      level: 0,
      lineId: lineIds[1],
    );

    final db = await database.database;
    db.execute('DROP INDEX idx_line_book_index');

    // repository חדש — דגל קיום האינדקס נבדק פעם אחת לכל מופע.
    final fallbackRepo = SeforimRepository(database);
    await fallbackRepo.ensureInitialized();

    final toc = await fallbackRepo.getTocEntriesForReference(bookId, 'ספר');
    expect(toc.single['segment'], 3);

    final alt = await fallbackRepo.getAltTocEntriesForReference(
      bookId,
      'ספר',
      queryTokens: const ['חלק'],
    );
    expect(alt.single['segment'], 1);

    final flat = await fallbackRepo.getAllAltTocFlatEntries();
    expect(flat.single['segment'], 1);
  });
}
