import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_asset_scheme.dart';
import 'package:path/path.dart' as p;

void main() {
  group('pluginAssetHost', () {
    test('מזהה תקין נשאר כפי שהוא', () {
      expect(pluginAssetHost('com.tikkun.koraim'), 'com.tikkun.koraim');
    });

    test('תווים שאינם חוקיים ב-host מוחלפים', () {
      expect(
        pluginAssetHost('com.otzaria_word_editor.superdoc'),
        'com.otzaria-word-editor.superdoc',
      );
      expect(pluginAssetHost('Com.Example'), 'com.example');
    });
  });

  group('pluginAssetUri', () {
    test('נקודת כניסה בשורש התוסף', () {
      final uri = pluginAssetUri(
        pluginId: 'com.tikkun.koraim',
        rootPath: p.join('plugins', 'koraim'),
        filePath: p.join('plugins', 'koraim', 'index.html'),
      );
      expect(uri.toString(), 'otzaria-plugin://com.tikkun.koraim/index.html');
    });

    test('נקודת כניסה בתת-תיקייה', () {
      final uri = pluginAssetUri(
        pluginId: 'com.example',
        rootPath: p.join('plugins', 'x'),
        filePath: p.join('plugins', 'x', 'dist', 'index.html'),
      );
      expect(uri.toString(), 'otzaria-plugin://com.example/dist/index.html');
    });

    test('רכיבי נתיב עם רווח או עברית מקודדים', () {
      final uri = pluginAssetUri(
        pluginId: 'com.example',
        rootPath: p.join('plugins', 'x'),
        filePath: p.join('plugins', 'x', 'a b', 'תוסף.js'),
      );
      expect(
        uri.toString(),
        'otzaria-plugin://com.example/a%20b/${Uri.encodeComponent('תוסף.js')}',
      );
    });
  });

  group('resolvePluginAssetFile', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('plugin_asset_scheme');
      File(p.join(root.path, 'index.html')).writeAsStringSync('<html></html>');
      Directory(p.join(root.path, 'assets')).createSync();
      File(p.join(root.path, 'assets', 'app.js')).writeAsStringSync('//');
    });

    tearDown(() => root.deleteSync(recursive: true));

    test('קובץ בשורש התוסף מוגש', () {
      final file = resolvePluginAssetFile(
        urlPath: '/index.html',
        rootPath: root.path,
      );
      expect(file, isNotNull);
      expect(p.basename(file!.path), 'index.html');
    });

    test('קובץ בתת-תיקייה מוגש', () {
      expect(
        resolvePluginAssetFile(
          urlPath: '/assets/app.js',
          rootPath: root.path,
        ),
        isNotNull,
      );
    });

    test('נתיב מקודד מפוענח', () {
      File(p.join(root.path, 'a b.js')).writeAsStringSync('//');
      expect(
        resolvePluginAssetFile(urlPath: '/a%20b.js', rootPath: root.path),
        isNotNull,
      );
    });

    test('חריגה מתיקיית התוסף נחסמת', () {
      File(p.join(root.parent.path, 'secret.txt')).writeAsStringSync('x');
      addTearDown(
        () => File(p.join(root.parent.path, 'secret.txt')).deleteSync(),
      );
      expect(
        resolvePluginAssetFile(
          urlPath: '/../secret.txt',
          rootPath: root.path,
        ),
        isNull,
      );
    });

    test('חריגה עמוקה נחסמת גם דרך תת-תיקייה', () {
      expect(
        resolvePluginAssetFile(
          urlPath: '/assets/../../secret.txt',
          rootPath: root.path,
        ),
        isNull,
      );
    });

    test('קובץ חסר מחזיר null', () {
      expect(
        resolvePluginAssetFile(urlPath: '/missing.js', rootPath: root.path),
        isNull,
      );
    });

    test('נתיב ריק מחזיר null', () {
      expect(resolvePluginAssetFile(urlPath: '/', rootPath: root.path), isNull);
    });
  });

  group('pluginAssetContentType', () {
    test('JavaScript — חובה לטיפוס מדויק, אחרת WebKit יסרב להריץ', () {
      expect(pluginAssetContentType('app.js'), 'text/javascript');
      expect(pluginAssetContentType('worker.mjs'), 'text/javascript');
    });

    test('טיפוסים נפוצים נוספים', () {
      expect(pluginAssetContentType('index.html'), 'text/html');
      expect(pluginAssetContentType('engine.wasm'), 'application/wasm');
      expect(pluginAssetContentType('Assistant-Bold.TTF'), 'font/ttf');
    });

    test('סיומת לא מוכרת נופלת ל-octet-stream', () {
      expect(pluginAssetContentType('data.bin'), 'application/octet-stream');
      expect(pluginAssetContentType('noext'), 'application/octet-stream');
    });
  });
}
