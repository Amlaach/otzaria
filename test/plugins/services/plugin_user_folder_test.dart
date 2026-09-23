import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_user_folder.dart';
import 'package:path/path.dart' as p;

void main() {
  group('parseUserFolderRelativePath', () {
    test('ריק ו-"." הם השורש', () {
      expect(parseUserFolderRelativePath(''), isEmpty);
      expect(parseUserFolderRelativePath('  '), isEmpty);
      expect(parseUserFolderRelativePath('.'), isEmpty);
    });

    test('מפרק לפי / ומדלג על רכיבים ריקים', () {
      expect(parseUserFolderRelativePath('a/b//c/./d.docx'), [
        'a',
        'b',
        'c',
        'd.docx',
      ]);
    });

    test('דוחה .., נתיב מוחלט ו-UNC', () {
      expect(parseUserFolderRelativePath('..'), isNull);
      expect(parseUserFolderRelativePath('a/../../b'), isNull);
      expect(parseUserFolderRelativePath('/etc'), isNull);
      expect(parseUserFolderRelativePath(r'\\server\share'), isNull);
      expect(parseUserFolderRelativePath('//server/share'), isNull);
    });

    test('בווינדוס דוחה נתיב עם כונן ומפריד \\', () {
      if (!Platform.isWindows) return;
      expect(parseUserFolderRelativePath(r'C:\Windows'), isNull);
      expect(parseUserFolderRelativePath('C:x'), isNull);
      expect(parseUserFolderRelativePath('a.txt:stream'), isNull);
      expect(parseUserFolderRelativePath(r'a\..\..\b'), isNull);
      expect(parseUserFolderRelativePath(r'a\b'), ['a', 'b']);
    });
  });

  group('normalizeUserFolderExtensions', () {
    test('מוריד נקודה ורישיות, ומשמיט ריקים', () {
      expect(
        normalizeUserFolderExtensions(['.DOCX', 'odt', ' .Rtf ', '', '.']),
        {
          'docx',
          'odt',
          'rtf',
        },
      );
      expect(normalizeUserFolderExtensions(null), isNull);
    });
  });

  test('isHiddenUserFolderEntry', () {
    expect(isHiddenUserFolderEntry('.git'), isTrue);
    expect(isHiddenUserFolderEntry(r'~$מסמך.docx'), isTrue);
    expect(isHiddenUserFolderEntry('a.docx.1234.OTZTMP'), isTrue);
    expect(isHiddenUserFolderEntry('מסמך.docx'), isFalse);
    expect(isHiddenUserFolderEntry('~draft.docx'), isFalse);
  });

  group('resolveUserFolderPath / listUserFolderEntries', () {
    late Directory temp;
    late String root;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('user_folder_test_');
      root = p.join(temp.path, 'root');
      await Directory(root).create();
      root = await Directory(root).resolveSymbolicLinks();
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    Future<UserFolderListing> list({
      String dir = '',
      Set<String>? extensions,
      int maxEntries = kUserFolderMaxEntries,
    }) async {
      final segments = parseUserFolderRelativePath(dir)!;
      final resolved = (await resolveUserFolderPath(root, segments))!;
      return listUserFolderEntries(
        canonicalRoot: root,
        canonicalDir: resolved,
        relativePath: joinUserFolderRelativePath(segments),
        extensions: extensions,
        maxEntries: maxEntries,
      );
    }

    test('תיקיות לפני קבצים, כל קבוצה לפי שם (לא תלוי רישיות)', () async {
      for (final f in ['b.docx', 'A.docx', 'c.odt']) {
        File(p.join(root, f)).writeAsStringSync('x' * 3);
      }
      for (final d in ['zeta', 'Alpha']) {
        Directory(p.join(root, d)).createSync();
      }
      final result = await list();
      expect(result.entries.map((e) => e['name']), [
        'Alpha',
        'zeta',
        'A.docx',
        'b.docx',
        'c.odt',
      ]);
      expect(result.truncated, isFalse);
      final dir = result.entries.first;
      expect(dir['type'], 'dir');
      expect(dir['size'], 0);
      expect(dir['path'], 'Alpha');
      final file = result.entries[2];
      expect(file['type'], 'file');
      expect(file['size'], 3);
      expect(
        DateTime.parse(file['modified'] as String).isUtc,
        isTrue,
        reason: 'modified חייב להיות ISO-8601 ב-UTC',
      );
      expect((file['modified'] as String).endsWith('Z'), isTrue);
    });

    test('מסנן נסתרים, קובצי נעילה ו-staging', () async {
      for (final f in [
        '.hidden.docx',
        r'~$doc.docx',
        '.doc.docx.abcd.otztmp',
        'plain.otztmp',
        'doc.docx',
      ]) {
        File(p.join(root, f)).writeAsStringSync('x');
      }
      Directory(p.join(root, '.git')).createSync();
      final result = await list();
      expect(result.entries.map((e) => e['name']), ['doc.docx']);
    });

    test('extensions מסנן קבצים בלבד — תיקיות נשארות', () async {
      File(p.join(root, 'a.DOCX')).writeAsStringSync('x');
      File(p.join(root, 'b.pdf')).writeAsStringSync('x');
      Directory(p.join(root, 'sub.pdf')).createSync();
      final result = await list(extensions: {'docx'});
      expect(result.entries.map((e) => e['name']), ['sub.pdf', 'a.DOCX']);
    });

    test('תת-תיקייה: path של הרשומות יחסי לשורש ומופרד ב-/', () async {
      final sub = Directory(p.join(root, 'a', 'b'))
        ..createSync(recursive: true);
      File(p.join(sub.path, 'x.docx')).writeAsStringSync('x');
      final result = await list(dir: 'a/b');
      expect(result.entries.single['path'], 'a/b/x.docx');
    });

    test('חיתוך ב-maxEntries: truncated, ותיקיות קודמות לקבצים', () async {
      for (var i = 0; i < 5; i++) {
        File(p.join(root, 'f$i.docx')).writeAsStringSync('x');
      }
      Directory(p.join(root, 'd')).createSync();
      final result = await list(maxEntries: 3);
      expect(result.truncated, isTrue);
      expect(result.entries.map((e) => e['name']), ['d', 'f0.docx', 'f1.docx']);
    });

    test('קישור שיוצא מהשורש אינו מוחזר ואינו ניתן לפתרון', () async {
      final outside = Directory(p.join(temp.path, 'outside'))..createSync();
      File(p.join(outside.path, 'secret.docx')).writeAsStringSync('x');
      final inside = Directory(p.join(root, 'inside'))..createSync();
      File(p.join(inside.path, 'ok.docx')).writeAsStringSync('x');
      try {
        Link(p.join(root, 'out-link')).createSync(outside.path);
        Link(p.join(root, 'in-link')).createSync(inside.path);
      } on FileSystemException {
        markTestSkipped('אין הרשאה ליצור קישורים במכונה הזו');
        return;
      }

      final result = await list();
      expect(result.entries.map((e) => e['name']), ['in-link', 'inside']);
      expect(await resolveUserFolderPath(root, ['out-link']), isNull);
      expect(
        await resolveUserFolderPath(root, ['out-link', 'secret.docx']),
        isNull,
      );
      expect(
        await resolveUserFolderPath(root, ['in-link', 'ok.docx']),
        p.join(inside.path, 'ok.docx'),
      );
    });

    test('מדידה: 3000 קבצים עם סינון סיומת', () async {
      for (var i = 0; i < 3000; i++) {
        File(
          p.join(root, 'f$i.${i % 3 == 0 ? 'docx' : 'txt'}'),
        ).writeAsStringSync('x');
      }
      final sw = Stopwatch()..start();
      final result = await list(extensions: {'docx'});
      sw.stop();
      expect(result.entries, hasLength(1000));
      // ignore: avoid_print
      print(
        'listUserFolderEntries: 3000 קבצים → 1000 אחרי סינון, '
        '${sw.elapsedMilliseconds}ms',
      );
    });
  });
}
