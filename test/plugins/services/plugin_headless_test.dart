import 'dart:convert';
import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/services/plugin_asset_scheme.dart';
import 'package:otzaria/plugins/services/plugin_extended_validator.dart';
import 'package:otzaria/plugins/services/plugin_headless_shell.dart';
import 'package:otzaria/plugins/services/plugin_manifest_validator.dart';
import 'package:path/path.dart' as p;

Map<String, dynamic> _manifest({
  String entrypoint = 'main.js',
  List<String> permissions = const [
    'app.startup_contributions',
    'app.run_on_startup',
  ],
  String minAppVersion = '0.9.98',
  Map<String, dynamic>? startup = const {
    'activationEvents': ['app.startup'],
  },
  Map<String, dynamic>? toolTab,
  Object? headless = true,
}) => {
  'schemaVersion': 1,
  'id': 'test.headless',
  'name': 'Headless',
  'version': '1.0.0',
  'entrypoint': entrypoint,
  'headless': ?headless,
  'minAppVersion': minAppVersion,
  'sdkVersion': '1.x',
  'permissions': permissions,
  'contributes': {'startup': ?startup, 'toolTab': ?toolTab},
};

void main() {
  late Directory tempDir;
  late Directory pluginDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('otzaria_headless_');
    pluginDir = Directory(p.join(tempDir.path, 'plugin'))..createSync();
    File(p.join(pluginDir.path, 'main.js')).writeAsStringSync('// noop');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  List<String> extendedErrors(Map<String, dynamic> json) =>
      PluginExtendedValidator.validate(
        manifest: PluginManifest.fromJson(json),
        manifestJson: json,
        directoryPath: pluginDir.path,
      ).errors;

  Future<List<String>> manifestErrors(Map<String, dynamic> json) =>
      PluginManifestValidator.collectManifestErrors(
        manifest: PluginManifest.fromJson(json),
        directoryPath: pluginDir.path,
        skipAppVersionValidation: true,
      );

  group('מניפסט', () {
    test('headless נקרא ונשמר ב-toJson', () {
      final manifest = PluginManifest.fromJson(_manifest());
      expect(manifest.headless, isTrue);
      expect(manifest.toJson()['headless'], isTrue);
      expect(
        PluginManifest.fromJson(_manifest(headless: null)).toJson(),
        isNot(contains('headless')),
      );
    });

    test('ערך שאינו bool אינו מפיל את הטעינה ומדווח כשגיאה', () {
      final json = _manifest(headless: 'yes');
      expect(PluginManifest.fromJson(json).headless, isFalse);
      expect(
        extendedErrors(json),
        contains(contains('השדה headless חייב להיות true או false')),
      );
    });
  });

  group('PluginManifestValidator', () {
    test('תוסף תקין עובר', () async {
      expect(await manifestErrors(_manifest()), isEmpty);
    });

    test('קובץ כניסה שאינו JS נחסם', () async {
      File(p.join(pluginDir.path, 'index.html')).writeAsStringSync('<html>');
      expect(
        await manifestErrors(_manifest(entrypoint: 'index.html')),
        contains(contains('חייב להיות קובץ JS')),
      );
    });

    test('background.entrypoint נחסם', () async {
      final json = _manifest();
      (json['contributes'] as Map)['background'] = {'entrypoint': 'main.js'};
      expect(
        await manifestErrors(json),
        contains(contains('contributes.background.entrypoint')),
      );
    });
  });

  group('PluginExtendedValidator', () {
    test('תוסף תקין עובר', () {
      expect(extendedErrors(_manifest()), isEmpty);
    });

    test('בלי שום דרך להתעורר — נחסם', () {
      expect(
        extendedErrors(_manifest(startup: null)),
        contains(contains('אין שום דרך לפעול')),
      );
    });

    test('בלי הרשאת run_on_startup — נחסם', () {
      expect(
        extendedErrors(
          _manifest(permissions: const ['app.startup_contributions']),
        ),
        contains(contains('"app.run_on_startup"')),
      );
    });

    test('openPlugin בפקד — נחסם', () {
      final errors = extendedErrors(
        _manifest(
          permissions: const [
            'app.startup_contributions',
            'app.run_on_startup',
            'reader.toolbar',
          ],
          startup: const {
            'activationEvents': ['app.startup'],
            'toolbarItems': [
              {
                'id': 'b1',
                'title': 'כפתור',
                'icon': 'apps_24_regular',
                'openPlugin': true,
              },
            ],
          },
        ),
      );
      expect(errors, contains(contains('openPlugin')));
    });

    test('contributes.toolTab — נחסם', () {
      expect(
        extendedErrors(_manifest(toolTab: const {'title': 'Headless'})),
        contains(contains('contributes.toolTab')),
      );
    });

    test('minAppVersion ישן — נחסם', () {
      expect(
        extendedErrors(_manifest(minAppVersion: '0.9.97')),
        contains(contains('0.9.98')),
      );
    });
  });

  group('מעטפת', () {
    test('טוענת את קובץ הכניסה עם נתיב מקודד — כמודול רק כשמבוקש', () {
      final classic = pluginHeadlessShellHtml(
        r'src\my "code".js',
        module: false,
      );
      expect(classic, contains('<script src="src/my%20%22code%22.js">'));
      expect(classic, isNot(contains('type="module"')));
      expect(
        pluginHeadlessShellHtml('main.js', module: true),
        contains('<script type="module" src="main.js">'),
      );
    });

    test('מזהה את הנתיב הווירטואלי רק בשורש התוסף', () {
      final root = pluginDir.path;
      expect(
        isPluginHeadlessShellPath(
          p.join(root, pluginHeadlessShellFileName),
          root,
        ),
        isTrue,
      );
      expect(
        isPluginHeadlessShellPath(
          p.join(root, 'sub', pluginHeadlessShellFileName),
          root,
        ),
        isFalse,
      );
    });

    test('סכימת הנכסים מגישה את המעטפת רק לתוסף ללא ממשק', () async {
      final url = pluginAssetUri(
        pluginId: 'test.headless',
        rootPath: pluginDir.path,
        filePath: pluginHeadlessShellPath(pluginDir.path),
      );
      final served = await servePluginAsset(
        url: url,
        pluginId: 'test.headless',
        rootPath: pluginDir.path,
        headlessEntrypoint: 'main.js',
      );
      expect(served?.contentType, 'text/html');
      expect(
        utf8.decode(served!.data),
        contains('<script type="module" src="main.js">'),
      );

      expect(
        await servePluginAsset(
          url: WebUri(url.toString()),
          pluginId: 'test.headless',
          rootPath: pluginDir.path,
        ),
        isNull,
      );
    });
  });
}
