import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/text/ref_helper.dart';
import 'package:path/path.dart' as path;

/// נתיב הכותרות של שורה נקרא בשאילתה אחת, וחייב להיות זהה לפלט של מסלול
/// עץ ה-TOC — שני הצדדים משמשים את אותה השוואת dedupe בפתיחת ספר.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MyDatabase db;
  late SeforimRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria-breadcrumb-');
    db = MyDatabase.withPath(path.join(tempDir.path, 'seforim.db'));
    repo = SeforimRepository(db);
    await repo.ensureInitialized();

    final raw = await db.database;
    raw.execute(
      "INSERT INTO book (id, categoryId, sourceId, title) "
      "VALUES (1, 1, 1, 'ישעיהו')",
    );
    // רמה 0 (שם הספר) אינה חלק מהכתובת, כמו במסלול העץ.
    for (final (id, text) in [(1, 'ישעיהו'), (2, 'פרק לב'), (3, 'פסוק יא')]) {
      raw.execute('INSERT INTO tocText (id, text) VALUES (?, ?)', [id, text]);
    }
    raw.execute(
      'INSERT INTO tocEntry (id, bookId, parentId, textId, level, lineIndex) '
      'VALUES (1, 1, NULL, 1, 0, 0), (2, 1, 1, 2, 1, 5), (3, 1, 2, 3, 2, 11)',
    );
    for (var i = 0; i < 13; i++) {
      raw.execute(
        'INSERT INTO line (id, bookId, lineIndex, content) VALUES (?, 1, ?, ?)',
        [100 + i, i, 'שורה $i'],
      );
    }
    raw.execute(
      'INSERT INTO line_toc (lineId, tocEntryId) VALUES (106, 2), (111, 3)',
    );
  });

  tearDown(() async {
    db.close();
    await tempDir.delete(recursive: true);
  });

  test('נתיב הכותרות מורכב מהכותרת ומאבותיה, בלי רמה 0', () async {
    expect(await repo.getLineBreadcrumb(1, 11), 'פרק לב, פסוק יא');
    expect(await repo.getLineBreadcrumb(1, 6), 'פרק לב');
  });

  test('זהה לפלט של refFromTocList על אותו עץ', () async {
    final toc = [
      TocEntry(text: 'ישעיהו', index: 0, level: 0)
        ..children.addAll([
          TocEntry(text: 'פרק לב', index: 5, level: 1)
            ..children.add(TocEntry(text: 'פסוק יא', index: 11, level: 2)),
        ]),
    ];
    expect(await repo.getLineBreadcrumb(1, 11), refFromTocList(11, toc));
  });

  test('שורה בלי מיפוי כותרת מחזירה null', () async {
    expect(await repo.getLineBreadcrumb(1, 0), isNull);
  });

  test('ספר שאינו ב-DB מחזיר null בלי שאילתה', () async {
    expect(await refFromDbLine(TextBook(title: 'ספר קבצים'), 3), isNull);
    expect(await heRefFromDbLine(TextBook(title: 'ספר קבצים'), 3), isNull);
  });

  test('heRef של השורה כולל את רמת הפסוק, ו-null לשורה בלי', () async {
    final raw = await db.database;
    raw.execute("UPDATE line SET heRef = 'ישעיהו לב, יא' WHERE id = 111");
    raw.execute("UPDATE line SET heRef = '  ' WHERE id = 112");
    expect(await repo.getLineHeRef(1, 11), 'ישעיהו לב, יא');
    expect(await repo.getLineHeRef(1, 12), isNull);
    expect(await repo.getLineHeRef(1, 0), isNull);
  });
}
