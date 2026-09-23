import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/update/differential/differential_update_service.dart';
import 'package:otzaria/update/differential/tree_fs.dart';
import 'package:otzaria/update/differential/update_engine.dart';
import 'package:otzaria/update/differential/update_package.dart'
    hide kUpdatePackageSchemaVersion, kUpdatePackageTreeSchemaVersion;
import 'package:otzaria/update/differential/zstd_runner.dart';
import 'package:path/path.dart' as p;

import '../../tool/release/generate_app_file_manifest.dart';
import '../../tool/release/generate_update_package.dart';
import '../support/fake_tree_file_system.dart';

const _exec = 0x1ED; // 0755
const _plain = 0x1A4; // 0644

/// bundle סינתטי בצורת macOS: frameworks עם Versions/Current, framework
/// שנוסף, framework שהוסר, יעד symlink שהשתנה, וביט הרצה שנוסף.
class _TreeFixture {
  _TreeFixture(this.root);

  final Directory root;
  static const oldTag = '0.10.1+10';
  static const newTag = '0.10.1+11';

  Directory get oldRoot => Directory(p.join(root.path, 'old', 'Otzaria.app'));
  Directory get newRoot => Directory(p.join(root.path, 'new', 'Otzaria.app'));
  File get package => File(p.join(root.path, 'package.zip'));
  File get fullPackage => File(p.join(root.path, 'package-files.zip'));

  final oldModes = <String, int>{};
  final newModes = <String, int>{};

  static const oldLinks = {
    'Contents/Frameworks/A.framework/A': 'Versions/Current/A',
    'Contents/Frameworks/A.framework/Versions/Current': 'A',
    'Contents/Frameworks/C.framework/C': 'Versions/Current/C',
    'Contents/Frameworks/C.framework/Versions/Current': 'A',
    'Contents/Frameworks/Old.framework/Old': 'Versions/Current/Old',
    'Contents/Frameworks/Old.framework/Versions/Current': 'A',
  };
  static const newLinks = {
    'Contents/Frameworks/A.framework/A': 'Versions/Current/A',
    'Contents/Frameworks/A.framework/Versions/Current': 'A',
    'Contents/Frameworks/B.framework/B': 'Versions/Current/B',
    'Contents/Frameworks/B.framework/Versions/Current': 'A',
    'Contents/Frameworks/C.framework/C': 'Versions/Current/C',
    'Contents/Frameworks/C.framework/Versions/Current': 'B',
  };

  late Map<String, Object?> oldManifest;
  late Map<String, Object?> newManifest;

  void build() {
    final body = List.generate(3000, (i) => 'otzaria line $i\n').join();
    void write(bool isNew, String path, String content, int mode) {
      final base = isNew ? newRoot : oldRoot;
      final file = File(p.join(base.path, path));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
      (isNew ? newModes : oldModes)[path] = mode;
    }

    write(false, 'Contents/MacOS/app', '$body old', _exec);
    write(true, 'Contents/MacOS/app', '$body new', _exec);
    write(false, 'Contents/Resources/data.txt', 'same', _plain);
    write(true, 'Contents/Resources/data.txt', 'same', _plain);
    // אותו תוכן, ביט הרצה חדש — אין ערך בחבילה, רק newTree.
    write(false, 'Contents/Resources/tool.sh', 'echo', _plain);
    write(true, 'Contents/Resources/tool.sh', 'echo', _exec);
    write(
      false,
      'Contents/Frameworks/A.framework/Versions/A/A',
      '$body a1',
      _exec,
    );
    write(
      true,
      'Contents/Frameworks/A.framework/Versions/A/A',
      '$body a2',
      _exec,
    );
    write(true, 'Contents/Frameworks/B.framework/Versions/A/B', 'b', _exec);
    write(false, 'Contents/Frameworks/C.framework/Versions/A/C', 'c1', _exec);
    write(true, 'Contents/Frameworks/C.framework/Versions/B/C', 'c2', _exec);
    write(
      false,
      'Contents/Frameworks/Old.framework/Versions/A/Old',
      'o',
      _exec,
    );

    oldManifest = _manifest(oldRoot, oldTag, oldModes, oldLinks);
    newManifest = _manifest(newRoot, newTag, newModes, newLinks);
    for (final (file, variant) in [
      (package, UpdatePackageVariant.patch),
      (fullPackage, UpdatePackageVariant.full),
    ]) {
      buildUpdatePackage(
        oldManifest: oldManifest,
        oldRoot: oldRoot,
        newManifest: newManifest,
        newRoot: newRoot,
        output: file,
        variant: variant,
      );
    }
  }

  static Map<String, Object?> _manifest(
    Directory root,
    String tag,
    Map<String, int> modes,
    Map<String, String> links,
  ) {
    final manifest = buildAppFileManifest(
      releaseTag: tag,
      releaseVersion: '0.10.1',
      platform: 'macos',
      architecture: 'universal',
      root: root,
      modeOf: (file) =>
          modes[p.relative(file.path, from: root.path).replaceAll(r'\', '/')]!,
    );
    manifest['links'] = [
      for (final path in links.keys.toList()..sort())
        {'path': path, 'target': links[path]},
    ];
    expect(validateAppFileManifest(manifest), isEmpty);
    return manifest;
  }

  /// התקנה של הגרסה הישנה אצל המשתמש, עם ה-symlinks וההרשאות שלה.
  Directory install(FakeTreeFileSystem fs) {
    final copy = Directory(p.join(root.path, 'Applications', 'Otzaria.app'));
    for (final entity in oldRoot.listSync(recursive: true)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: oldRoot.path);
      final target = File(p.join(copy.path, relative));
      target.parent.createSync(recursive: true);
      entity.copySync(target.path);
    }
    oldLinks.forEach((path, target) => fs.seedLink(copy, path, target));
    oldModes.forEach((path, mode) => fs.seedMode(copy, path, mode));
    return copy;
  }
}

Map<String, String> _hashes(Directory root) => {
  for (final entity in root.listSync(recursive: true))
    if (entity is File)
      p.relative(entity.path, from: root.path).replaceAll(r'\', '/'): sha256
          .convert(entity.readAsBytesSync())
          .toString(),
};

void main() {
  final hasZstd = const Zstd().isAvailable;
  const zstdSkip = 'zstd is not on PATH';
  late Directory temp;
  late _TreeFixture fixture;
  late FakeTreeFileSystem fs;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('otzaria-tree-update');
    fixture = _TreeFixture(temp);
    fs = FakeTreeFileSystem();
    if (hasZstd) fixture.build();
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  DifferentialUpdateEngine engine(
    Directory install, {
    bool allowUnmanaged = false,
  }) => DifferentialUpdateEngine(
    installRoot: install,
    workRoot: Directory(p.join(temp.path, 'work')),
    platform: 'macos',
    architecture: 'universal',
    installedReleaseTag: _TreeFixture.oldTag,
    zstd: const ZstdRunner(),
    preparedRoot: preparedTreeDirectoryFor(install),
    treeFs: fs,
    allowUnmanagedFiles: allowUnmanaged,
  );

  Map<String, Object?> manifestOf(File package) => readUpdatePackageManifest(
    ZipDecoder().decodeBytes(package.readAsBytesSync()),
  );

  group('חבילת עץ', () {
    test('נושאת symlinks, הסרות symlinks והעץ החדש המלא', () {
      final manifest = manifestOf(fixture.package);
      expect(manifest['schemaVersion'], kUpdatePackageTreeSchemaVersion);
      expect(manifest['links'], [
        {
          'path': 'Contents/Frameworks/B.framework/B',
          'target': 'Versions/Current/B',
        },
        {
          'path': 'Contents/Frameworks/B.framework/Versions/Current',
          'target': 'A',
        },
        {
          'path': 'Contents/Frameworks/C.framework/Versions/Current',
          'target': 'B',
        },
      ]);
      expect(
        [
          for (final r in (manifest['linkRemovals'] as List).cast<Map>())
            r['path'],
        ],
        [
          'Contents/Frameworks/Old.framework/Old',
          'Contents/Frameworks/Old.framework/Versions/Current',
        ],
      );
      expect(
        [for (final r in (manifest['removals'] as List).cast<Map>()) r['path']],
        [
          'Contents/Frameworks/C.framework/Versions/A/C',
          'Contents/Frameworks/Old.framework/Versions/A/Old',
        ],
      );
      final tree = treeManifestOf(manifest);
      expect(tree.links, _TreeFixture.newLinks);
      expect(tree.files['Contents/Resources/tool.sh']!.mode, _exec);
      // שינוי הרשאה בלבד אינו ערך בחבילה — newTree הוא שמיישר אותו.
      expect(
        (manifest['entries'] as List).cast<Map>().map((e) => e['path']),
        isNot(contains('Contents/Resources/tool.sh')),
      );
    }, skip: hasZstd ? null : zstdSkip);

    test('חבילת Windows נשארת בסכמה 1, בלי שדות עץ', () {
      final root = Directory(p.join(temp.path, 'win'));
      Map<String, Object?> build(String tag, String content) {
        final dir = Directory(p.join(root.path, tag));
        File(p.join(dir.path, 'otzaria.exe'))
          ..createSync(recursive: true)
          ..writeAsStringSync(content);
        return buildAppFileManifest(
          releaseTag: tag,
          releaseVersion: '0.10.1',
          platform: 'windows',
          architecture: 'x64',
          root: dir,
        );
      }

      final oldManifest = build('1', 'old');
      final newManifest = build('2', 'new');
      expect(oldManifest['schemaVersion'], kAppFileManifestSchemaVersion);
      expect(oldManifest.containsKey('links'), isFalse);
      final out = File(p.join(temp.path, 'win.zip'));
      buildUpdatePackage(
        oldManifest: oldManifest,
        oldRoot: Directory(p.join(root.path, '1')),
        newManifest: newManifest,
        newRoot: Directory(p.join(root.path, '2')),
        output: out,
      );
      final manifest = manifestOf(out);
      expect(manifest['schemaVersion'], kUpdatePackageSchemaVersion);
      for (final key in ['links', 'linkRemovals', 'newTree']) {
        expect(manifest.containsKey(key), isFalse, reason: key);
      }
    }, skip: hasZstd ? null : zstdSkip);

    test('המאמת של הבונה מחיל על עותק הישן ומשווה את העץ כולו', () async {
      await verifyTreePackage(
        fixture.package,
        fixture.install(fs),
        fixture.newManifest,
        fs: fs,
      );
    }, skip: hasZstd ? null : zstdSkip);

    test('symlink חסר בעותק הישן נתפס באימות של הבונה', () async {
      final install = fixture.install(fs);
      fs.links.remove(
        p.normalize(
          p.join(install.path, 'Contents/Frameworks/A.framework/A'),
        ),
      );
      await expectLater(
        verifyTreePackage(
          fixture.package,
          install,
          fixture.newManifest,
          fs: fs,
        ),
        throwsA(isA<UpdatePackageException>()),
      );
    }, skip: hasZstd ? null : zstdSkip);
  });

  group('הכנת העותק בלקוח', () {
    test('העותק זהה לגרסה החדשה: קבצים, symlinks, הרשאות', () async {
      final install = fixture.install(fs);
      final before = _hashes(install);
      final linksBefore = {...fs.links};

      final staged = await engine(install).prepare(fixture.package);

      expect(staged.isTree, isTrue);
      final prepared = staged.stagingRoot;
      expect(
        p.equals(prepared.path, preparedTreeDirectoryFor(install).path),
        isTrue,
      );
      expect(_hashes(prepared), _hashes(fixture.newRoot));
      final listing = await fs.list(prepared.path);
      expect(listing.links, _TreeFixture.newLinks);
      expect(listing.files['Contents/Resources/tool.sh'], _exec);
      expect(
        listing.files['Contents/Frameworks/B.framework/Versions/A/B'],
        _exec,
      );
      // framework שהוסר אינו משאיר תיקייה ריקה — codesign היה פוסל אותה.
      expect(
        Directory(
          p.join(prepared.path, 'Contents/Frameworks/Old.framework'),
        ).existsSync(),
        isFalse,
      );
      expect(
        Directory(
          p.join(prepared.path, 'Contents/Frameworks/C.framework/Versions/A'),
        ).existsSync(),
        isFalse,
      );

      // ההתקנה החיה לא נגעה.
      expect(_hashes(install), before);
      expect(
        fs.links,
        containsPair(
          p.normalize(
            p.join(install.path, 'Contents/Frameworks/Old.framework/Old'),
          ),
          'Versions/Current/Old',
        ),
      );
      for (final entry in linksBefore.entries) {
        expect(fs.links[entry.key], entry.value);
      }
    }, skip: hasZstd ? null : zstdSkip);

    test('קובץ מקומי שאינו בסיס ה-patch מושלם מחבילת הקבצים המלאים', () async {
      final install = fixture.install(fs);
      File(p.join(install.path, 'Contents/MacOS/app')).writeAsStringSync('x');
      var fetched = 0;

      final staged = await engine(install).prepare(
        fixture.package,
        fallbackPackage: () async {
          fetched++;
          return fixture.fullPackage;
        },
      );

      expect(fetched, 1);
      expect(_hashes(staged.stagingRoot), _hashes(fixture.newRoot));
    }, skip: hasZstd ? null : zstdSkip);

    test('קובץ זר ב-bundle של macOS — העדכון נזנח והעותק נמחק', () async {
      final install = fixture.install(fs);
      File(p.join(install.path, 'Contents/stray.txt')).writeAsStringSync('?');

      await expectLater(
        engine(install).prepare(fixture.package),
        throwsA(
          isA<DifferentialUpdateUnavailable>().having(
            (e) => e.reason,
            'reason',
            UpdateAbortReason.stagingVerificationFailed,
          ),
        ),
      );
      expect(preparedTreeDirectoryFor(install).existsSync(), isFalse);
    }, skip: hasZstd ? null : zstdSkip);

    test('ב-Linux קובץ זר נסבל ומועתק כמות שהוא', () async {
      final install = fixture.install(fs);
      File(p.join(install.path, 'Contents/stray.txt')).writeAsStringSync('?');

      final staged = await engine(install, allowUnmanaged: true).prepare(
        fixture.package,
      );
      expect(
        File(
          p.join(staged.stagingRoot.path, 'Contents/stray.txt'),
        ).existsSync(),
        isTrue,
      );
    }, skip: hasZstd ? null : zstdSkip);

    test('בלי תיקיית יעד לעותק — אין מסלול', () async {
      final install = fixture.install(fs);
      final bare = DifferentialUpdateEngine(
        installRoot: install,
        workRoot: Directory(p.join(temp.path, 'work')),
        platform: 'macos',
        architecture: 'universal',
        installedReleaseTag: _TreeFixture.oldTag,
        zstd: const ZstdRunner(),
        treeFs: fs,
      );
      await expectLater(
        bare.prepare(fixture.package),
        throwsA(isA<DifferentialUpdateUnavailable>()),
      );
    }, skip: hasZstd ? null : zstdSkip);

    test('discard מוחק גם את העותק שלצד ההתקנה', () async {
      final install = fixture.install(fs);
      final staged = await engine(install).prepare(fixture.package);
      await staged.discard();
      expect(staged.stagingRoot.existsSync(), isFalse);
      expect(install.existsSync(), isTrue);
    }, skip: hasZstd ? null : zstdSkip);
  });

  group('קריאת מניפסט עץ בלקוח', () {
    Map<String, Object?> base() => {
      'schemaVersion': kUpdatePackageTreeSchemaVersion,
      'variant': 'full',
      'platform': 'linux',
      'architecture': 'x64',
      'fromReleaseTag': 'a',
      'fromReleaseVersion': '1',
      'toReleaseTag': 'b',
      'toReleaseVersion': '1',
      'payloadSize': 0,
      'entries': <Object>[],
      'removals': <Object>[],
      'links': [
        {'path': 'lib/libx.so', 'target': 'libx.so.1'},
      ],
      'linkRemovals': <Object>[],
      'newTree': {
        'files': [
          {
            'path': 'lib/libx.so.1',
            'size': 1,
            'sha256': 'a' * 64,
            'mode': _exec,
          },
        ],
        'links': [
          {'path': 'lib/libx.so', 'target': 'libx.so.1'},
        ],
      },
    };

    Matcher invalid() => throwsA(
      isA<DifferentialUpdateUnavailable>().having(
        (e) => e.reason,
        'reason',
        UpdateAbortReason.packageInvalid,
      ),
    );

    test('מניפסט תקין נקרא, כולל העץ', () {
      final manifest = UpdatePackageManifest.fromJson(base());
      expect(manifest.isTree, isTrue);
      expect(manifest.links, {'lib/libx.so': 'libx.so.1'});
      expect(manifest.newTree!.files['lib/libx.so.1']!.mode, _exec);
    });

    test('סכמת עץ ל-Windows, או סכמה 1 ל-Linux, נדחות', () {
      expect(
        () => UpdatePackageManifest.fromJson(base()..['platform'] = 'windows'),
        invalid(),
      );
      expect(
        () => UpdatePackageManifest.fromJson(base()..['schemaVersion'] = 1),
        invalid(),
      );
      expect(
        () => UpdatePackageManifest.fromJson(base()..['schemaVersion'] = 3),
        invalid(),
      );
    });

    test('symlink שמפנה מחוץ לעץ או לנתיב מוחלט נדחה', () {
      for (final target in ['../../etc/passwd', '/usr/lib/x', r'a\b']) {
        final manifest = base();
        (manifest['newTree'] as Map)['links'] = [
          {'path': 'lib/libx.so', 'target': target},
        ];
        manifest['links'] = [
          {'path': 'lib/libx.so', 'target': target},
        ];
        expect(
          () => UpdatePackageManifest.fromJson(manifest),
          invalid(),
          reason: target,
        );
      }
    });

    test('קובץ שנתיבו עובר דרך symlink נדחה', () {
      final manifest = base();
      ((manifest['newTree'] as Map)['files'] as List).add({
        'path': 'lib/libx.so/inner',
        'size': 1,
        'sha256': 'b' * 64,
        'mode': _plain,
      });
      expect(() => UpdatePackageManifest.fromJson(manifest), invalid());
    });

    test('symlink שאינו תואם את newTree, והסרה של קישור שנשאר — נדחים', () {
      expect(
        () => UpdatePackageManifest.fromJson(
          base()
            ..['links'] = [
              {'path': 'lib/libx.so', 'target': 'other'},
            ],
        ),
        invalid(),
      );
      expect(
        () => UpdatePackageManifest.fromJson(
          base()
            ..['linkRemovals'] = [
              {'path': 'lib/libx.so', 'oldTarget': 'libx.so.0'},
            ],
        ),
        invalid(),
      );
    });

    test('קובץ בלי הרשאות ב-newTree נדחה', () {
      final manifest = base();
      (((manifest['newTree'] as Map)['files'] as List).first as Map).remove(
        'mode',
      );
      expect(() => UpdatePackageManifest.fromJson(manifest), invalid());
    });

    test('הבונה והלקוח מסכימים: חבילה תקינה בבונה עוברת בלקוח', () {
      final manifest = base()..['assetName'] = 'x.zip';
      manifest['patchBenefitThreshold'] = 0.9;
      expect(validateUpdatePackageManifest(manifest), isEmpty);
      expect(
        UpdatePackageManifest.fromJson(jsonDecode(jsonEncode(manifest))).isTree,
        isTrue,
      );
    });
  });

  group('פעולות העץ', () {
    test('הסרה מנקה תיקיות שהתרוקנו, ועוצרת בשורש', () async {
      final root = Directory(p.join(temp.path, 'r'))..createSync();
      File(p.join(root.path, 'a/b/c/file'))
        ..createSync(recursive: true)
        ..writeAsStringSync('x');
      File(p.join(root.path, 'a/keep')).writeAsStringSync('k');
      fs.seedLink(root, 'a/b/link', 'c/file');

      await removeFromTree(
        fs: fs,
        root: root.path,
        linkRemovals: ['a/b/link'],
        fileRemovals: ['a/b/c/file'],
      );

      expect(Directory(p.join(root.path, 'a/b')).existsSync(), isFalse);
      expect(File(p.join(root.path, 'a/keep')).existsSync(), isTrue);
      expect(root.existsSync(), isTrue);
    });

    test('הסרת symlink שבמקומו קובץ רגיל נכשלת', () async {
      final root = Directory(p.join(temp.path, 'r'))..createSync();
      File(p.join(root.path, 'x')).writeAsStringSync('x');
      await expectLater(
        removeFromTree(
          fs: fs,
          root: root.path,
          linkRemovals: ['x'],
          fileRemovals: [],
        ),
        throwsA(isA<TreeUpdateException>()),
      );
    });

    test('ההשוואה היא על ביט ההרצה בלבד — umask של המשתמש אינו כשל', () {
      expect(sameExecutableBit(0x1C0, 0x1ED), isTrue); // 0700 מול 0755
      expect(sameExecutableBit(0x180, 0x1A4), isTrue); // 0600 מול 0644
      expect(sameExecutableBit(0x1A4, 0x1ED), isFalse);
      expect(sameExecutableBit(null, 0x1A4), isFalse);
    });

    test('יעד symlink: יחסי ובתוך העץ בלבד', () {
      expect(linkTargetError('A.framework/A', 'Versions/Current/A'), isNull);
      expect(linkTargetError('a/b/c', '../x'), isNull);
      expect(linkTargetError('a/b', '../../x'), isNotNull);
      expect(linkTargetError('a', '/abs'), isNotNull);
      expect(linkTargetError('a', ''), isNotNull);
      expect(linkTargetError('a/b', '..'), isNotNull);
    });
  });
}
