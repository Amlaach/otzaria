import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_fs_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late PluginFsService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('plugin_fs_test_');
    service = PluginFsService();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// יוצרת קובץ ZIP ב-[zipPath] המכיל את [entries] (שם יחסי → תוכן).
  String buildZip(String zipPath, Map<String, String> entries) {
    final srcDir = Directory(p.join(tempDir.path, 'src_${entries.hashCode}'))
      ..createSync(recursive: true);
    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    try {
      entries.forEach((name, content) {
        final f = File(p.join(srcDir.path, name))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(content);
        encoder.addFileSync(f, name);
      });
    } finally {
      encoder.closeSync();
    }
    return zipPath;
  }

  group('PluginFsService.extractZip', () {
    test('מחלץ קבצים אל תיקיית היעד ויוצר אותה אם אינה קיימת', () async {
      final zipPath = buildZip(p.join(tempDir.path, 'a.zip'), {
        'hello.txt': 'שלום עולם',
        'sub/inner.txt': 'פנימי',
      });
      final destFolder = p.join(tempDir.path, 'out', 'nested');

      await service.extractZip(zipPath, destFolder);

      final hello = File(p.join(destFolder, 'hello.txt'));
      final inner = File(p.join(destFolder, 'sub', 'inner.txt'));
      expect(await hello.exists(), isTrue);
      expect(await hello.readAsString(), 'שלום עולם');
      expect(await inner.exists(), isTrue);
      expect(await inner.readAsString(), 'פנימי');
    });

    test('זורק כשקובץ ה-ZIP אינו קיים', () async {
      await expectLater(
        service.extractZip(
          p.join(tempDir.path, 'missing.zip'),
          p.join(tempDir.path, 'out'),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('זורק error.too_large כשהגודל המחולץ חורג מהתקרה', () async {
      final tinyLimit = PluginFsService(maxUncompressedBytes: 10);
      final zipPath = buildZip(p.join(tempDir.path, 'big.zip'), {
        'big.txt': 'תוכן ארוך מהתקרה של עשרה בייטים',
      });
      final destFolder = p.join(tempDir.path, 'out');

      await expectLater(
        tinyLimit.extractZip(zipPath, destFolder),
        throwsA(predicate((e) => e.toString().contains('error.too_large'))),
      );
    });

    test('זורק error.too_large כשמספר הרשומות חורג מהתקרה', () async {
      final fewEntries = PluginFsService(maxEntries: 1);
      final zipPath = buildZip(p.join(tempDir.path, 'many.zip'), {
        'a.txt': 'a',
        'b.txt': 'b',
      });
      final destFolder = p.join(tempDir.path, 'out');

      await expectLater(
        fewEntries.extractZip(zipPath, destFolder),
        throwsA(predicate((e) => e.toString().contains('error.too_large'))),
      );
    });

    test('מדלג על רשומה שיוצאת מתיקיית היעד (path-traversal)', () async {
      final zipPath = buildZip(p.join(tempDir.path, 'evil.zip'), {
        '../escaped.txt': 'ניסיון בריחה',
        'safe.txt': 'בטוח',
      });
      final destFolder = p.join(tempDir.path, 'out', 'nested');

      await service.extractZip(zipPath, destFolder);

      final escaped = File(p.join(tempDir.path, 'out', 'escaped.txt'));
      final safe = File(p.join(destFolder, 'safe.txt'));
      expect(await escaped.exists(), isFalse);
      expect(await safe.exists(), isTrue);
    });

    test(
      'חוסם יצירת תיקיות וכתיבה דרך symlink-תיקייה קיים שמצביע מחוץ ליעד',
      () async {
        final destFolder = p.join(tempDir.path, 'out');
        Directory(destFolder).createSync(recursive: true);
        final outside = Directory(p.join(tempDir.path, 'outside'))
          ..createSync();

        // יצירת symlink-תיקייה דורשת הרשאות בחלק מהפלטפורמות (Windows ללא
        // Developer Mode) — אם נכשלה, אין מה לבדוק.
        try {
          Link(p.join(destFolder, 'linkdir')).createSync(outside.path);
        } on FileSystemException {
          markTestSkipped('יצירת symlink אינה נתמכת בסביבה זו');
          return;
        }

        final zipPath = buildZip(p.join(tempDir.path, 'evil.zip'), {
          'linkdir/sub/evil.txt': 'בריחה דרך symlink',
        });

        await service.extractZip(zipPath, destFolder);

        // לא הקובץ ולא תיקיית האב שלו נוצרו מחוץ ליעד.
        expect(
          File(p.join(outside.path, 'sub', 'evil.txt')).existsSync(),
          isFalse,
        );
        expect(Directory(p.join(outside.path, 'sub')).existsSync(), isFalse);
      },
    );
  });

  group('PluginFsService.deleteFile', () {
    test('מוחק קובץ קיים', () async {
      final file = File(p.join(tempDir.path, 'x.txt'))
        ..writeAsStringSync('data');
      expect(await file.exists(), isTrue);

      await service.deleteFile(file.path);

      expect(await file.exists(), isFalse);
    });

    test('idempotent — אינו זורק כשהקובץ אינו קיים', () async {
      await service.deleteFile(p.join(tempDir.path, 'nope.txt'));
      // ללא חריגה — הצלחה שקטה.
    });

    test('זורק כשהנתיב הוא תיקייה', () async {
      final dir = Directory(p.join(tempDir.path, 'adir'))
        ..createSync(recursive: true);
      await expectLater(
        service.deleteFile(dir.path),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('PluginFsService.deleteFolder', () {
    test('מוחקת תיקייה על כל תוכנה', () async {
      final dir = Directory(p.join(tempDir.path, 'coll'))
        ..createSync(recursive: true);
      File(p.join(dir.path, 'a.txt')).writeAsStringSync('x');
      Directory(p.join(dir.path, 'sub')).createSync();
      File(p.join(dir.path, 'sub', 'b.txt')).writeAsStringSync('y');

      await service.deleteFolder(dir.path);

      expect(await dir.exists(), isFalse);
    });

    test('idempotent — אינה זורקת כשהתיקייה אינה קיימת', () async {
      await service.deleteFolder(p.join(tempDir.path, 'nope'));
    });

    test('זורקת כשהנתיב הוא קובץ', () async {
      final file = File(p.join(tempDir.path, 'x.txt'))
        ..writeAsStringSync('data');
      await expectLater(
        service.deleteFolder(file.path),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('PluginFsService.moveEntry', () {
    test('מזיזה תיקייה עם תוכנה ליעד חדש', () async {
      final from = Directory(p.join(tempDir.path, 'old_name'))
        ..createSync(recursive: true);
      File(p.join(from.path, 'a.txt')).writeAsStringSync('שלום');
      Directory(p.join(from.path, 'sub')).createSync();
      File(p.join(from.path, 'sub', 'b.txt')).writeAsStringSync('עולם');

      final to = p.join(tempDir.path, 'new_name');
      await service.moveEntry(from.path, to);

      expect(await from.exists(), isFalse);
      expect(File(p.join(to, 'a.txt')).readAsStringSync(), 'שלום');
      expect(File(p.join(to, 'sub', 'b.txt')).readAsStringSync(), 'עולם');
    });

    test('מזיזה קובץ בודד ליעד חדש, כולל יצירת תיקיית האב', () async {
      final from = File(p.join(tempDir.path, 'a.txt'))
        ..writeAsStringSync('data');
      final to = p.join(tempDir.path, 'nested', 'deeper', 'a.txt');

      await service.moveEntry(from.path, to);

      expect(await from.exists(), isFalse);
      expect(File(to).readAsStringSync(), 'data');
    });

    test('זורקת error.not_found כשהמקור אינו קיים', () async {
      await expectLater(
        service.moveEntry(
          p.join(tempDir.path, 'nope'),
          p.join(tempDir.path, 'dest'),
        ),
        throwsA(
          predicate((e) => e is Exception && e.toString().contains('error.not_found')),
        ),
      );
    });

    test('זורקת error.invalid_params ולא דורסת כשהיעד כבר קיים', () async {
      final from = File(p.join(tempDir.path, 'a.txt'))
        ..writeAsStringSync('new content');
      final to = File(p.join(tempDir.path, 'b.txt'))
        ..writeAsStringSync('existing content');

      await expectLater(
        service.moveEntry(from.path, to.path),
        throwsA(
          predicate(
            (e) => e is Exception && e.toString().contains('error.invalid_params'),
          ),
        ),
      );
      // היעד הקיים לא נדרס, והמקור לא נמחק.
      expect(to.readAsStringSync(), 'existing content');
      expect(await from.exists(), isTrue);
    });
  });
}
