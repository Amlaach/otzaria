import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/update/differential/differential_update_service.dart';
import 'package:otzaria/update/differential/swap_plan.dart';
import 'package:otzaria/update/my_update_widget.dart';
import 'package:otzaria/update/tree_swap.dart';
import 'package:path/path.dart' as p;

void main() {
  group('סקריפט ההחלפה של עדכון עץ', () {
    String script({String? relaunch, bool log = false}) => buildTreeSwapScript(
      installedPath: '/Applications/אוצריא.app',
      preparedPath: "/Applications/.אוצריא.app.otzaria-update",
      workPath: "/tmp/it's work",
      swapHelperPath: '/tmp/atomic-swap',
      appPid: 4242,
      relaunchCommand: relaunch,
      logToWork: log,
    );

    test('ממתין ל-pid, ומחליף בתיקיות בפעולה אטומית', () {
      final body = script();
      expect(body, startsWith('#!/bin/sh\n'));
      expect(body, contains('while kill -0 4242'));
      expect(body, contains('"\$SWAPPER" "\$INSTALLED" "\$PREPARED"'));
      expect(body, isNot(contains('mv "\$INSTALLED"')));
    });

    test('מוותר לפני שנגע בדבר, עם הסימן שהממשק מחכה לו', () {
      final body = script();
      final giveUp = body.indexOf(kSwapGaveUpFileName);
      expect(giveUp, greaterThan(-1));
      expect(giveUp, lessThan(body.indexOf('"\$SWAPPER"')));
      // 2 דקות בצעדים של 0.2 שנייה.
      expect(body, contains('-ge 600'));
    });

    test('נתיבים מצוטטים — גם עם גרש בודד', () {
      expect(script(), contains(r"WORK='/tmp/it'\''s work'"));
    });

    test('הפעלה מחדש רק כשהתבקשה, וגם כשההחלפה נכשלה', () {
      expect(script(), contains('relaunch() {\n  :\n}'));
      final body = script(relaunch: 'open -n "\$INSTALLED"');
      expect('relaunch\n'.allMatches(body).length, 2);
    });

    test('יומן לתיקיית העבודה רק כשהתבקש (Linux, בלי טרמינל)', () {
      expect(script(), isNot(contains('swap.log')));
      expect(script(log: true), contains('exec >"\$WORK/swap.log" 2>&1'));
    });

    test('ב-Linux מופעל ה-launcher ולא otzaria.bin', () {
      expect(
        treeRelaunchCommand(
          isMacOS: false,
          installedPath: '/home/u/otzaria-linux-full/app',
          executablePath: '/home/u/otzaria-linux-full/app/otzaria.bin',
        ),
        "nohup \"\$INSTALLED\"/'otzaria' >/dev/null 2>&1 &",
      );
      expect(
        treeRelaunchCommand(
          isMacOS: true,
          installedPath: '/Applications/אוצריא.app',
          executablePath: '/Applications/אוצריא.app/Contents/MacOS/אוצריא',
        ),
        'open -n "\$INSTALLED"',
      );
    });

    // הרצת העזר האמיתי: גם כשל אינו מזיז את ההתקנה הישנה.
    test('ריצה אמיתית ב-sh', () async {
      final temp = Directory.systemTemp.createTempSync('otzaria-tree-swap');
      try {
        final installed = Directory(p.join(temp.path, 'app'))..createSync();
        final swapper = File(p.join(installed.path, kAtomicTreeSwapHelperName));
        final compile = await Process.run('cc', [
          'tool/updater/atomic_tree_swap.c',
          '-o',
          swapper.path,
        ]);
        expect(compile.exitCode, 0, reason: '${compile.stderr}');
        File(p.join(installed.path, 'v')).writeAsStringSync('old');
        expect(await atomicTreeSwapSupported(installed), isTrue);
        final missing = Directory(p.join(temp.path, 'missing'));
        final failed = await Process.run(swapper.path, [
          installed.path,
          missing.path,
        ]);
        expect(failed.exitCode, isNot(0));
        expect(File(p.join(installed.path, 'v')).readAsStringSync(), 'old');
        final prepared = Directory(p.join(temp.path, '.app.otzaria-update'))
          ..createSync();
        File(p.join(prepared.path, 'v')).writeAsStringSync('new');
        swapper.copySync(p.join(prepared.path, kAtomicTreeSwapHelperName));
        final work = Directory(p.join(temp.path, 'work'))..createSync();
        final file = File(p.join(work.path, 'swap.sh'))
          ..writeAsStringSync(
            buildTreeSwapScript(
              installedPath: installed.path,
              preparedPath: prepared.path,
              workPath: work.path,
              swapHelperPath: swapper.path,
              appPid: 999999,
            ),
          );
        final result = await Process.run('sh', [file.path]);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(File(p.join(installed.path, 'v')).readAsStringSync(), 'new');
        expect(prepared.existsSync(), isFalse);
        expect(work.existsSync(), isFalse);

        expect(await atomicTreeSwapSupported(installed), isTrue);
      } finally {
        temp.deleteSync(recursive: true);
      }
    }, skip: Platform.isWindows ? 'רץ ב-POSIX בלבד (ב-Windows — WSL)' : null);

    test('כשל בכלי ההחלפה משאיר את שתי התיקיות במקומן', () async {
      final temp = Directory.systemTemp.createTempSync('otzaria-swap-failure');
      try {
        final installed = Directory(p.join(temp.path, 'app'))..createSync();
        final prepared = Directory(p.join(temp.path, 'prepared'))..createSync();
        final work = Directory(p.join(temp.path, 'work'))..createSync();
        File(p.join(installed.path, 'v')).writeAsStringSync('old');
        File(p.join(prepared.path, 'v')).writeAsStringSync('new');
        final helper = File(p.join(installed.path, kAtomicTreeSwapHelperName))
          ..writeAsStringSync('#!/bin/sh\nexit 1\n');
        final chmod = await Process.run('chmod', ['+x', helper.path]);
        expect(chmod.exitCode, 0);
        expect(await atomicTreeSwapSupported(installed), isFalse);
        final script = File(p.join(work.path, 'swap.sh'))
          ..writeAsStringSync(
            buildTreeSwapScript(
              installedPath: installed.path,
              preparedPath: prepared.path,
              workPath: work.path,
              swapHelperPath: helper.path,
              appPid: 999999,
            ),
          );
        final result = await Process.run('sh', [script.path]);
        expect(result.exitCode, isNot(0));
        expect(File(p.join(installed.path, 'v')).readAsStringSync(), 'old');
        expect(File(p.join(prepared.path, 'v')).readAsStringSync(), 'new');
      } finally {
        temp.deleteSync(recursive: true);
      }
    }, skip: Platform.isWindows ? 'רץ ב-POSIX בלבד (ב-Windows — WSL)' : null);
  });

  group('זמינות עדכון העץ', () {
    test('כל תנאי חסר מבטל את המסלול', () {
      bool supported({
        bool writable = true,
        bool parent = true,
        bool zstd = true,
        bool helper = true,
        bool userData = false,
      }) => treeUpdateSupported(
        installRootWritable: writable,
        parentWritable: parent,
        zstdAvailable: zstd,
        swapHelperAvailable: helper,
        hasUserData: userData,
      );
      expect(supported(), isTrue);
      expect(supported(writable: false), isFalse);
      expect(supported(parent: false), isFalse);
      expect(supported(zstd: false), isFalse);
      expect(supported(helper: false), isFalse);
      expect(supported(userData: true), isFalse);
    });

    test('נתוני משתמש בשורש ההתקנה מזוהים', () {
      final temp = Directory.systemTemp.createTempSync('otzaria-user-data');
      try {
        File(p.join(temp.path, 'otzaria')).writeAsStringSync('');
        expect(installRootHasUserData(temp), isFalse);
        File(p.join(temp.path, 'portable.marker')).writeAsStringSync('');
        expect(installRootHasUserData(temp), isTrue);
        File(p.join(temp.path, 'portable.marker')).deleteSync();
        Directory(p.join(temp.path, 'otzaria_data')).createSync();
        expect(installRootHasUserData(temp), isTrue);
      } finally {
        temp.deleteSync(recursive: true);
      }
    });

    test('העותק מוכן לצד ההתקנה, מוסתר, ואינו נראה כ-.app', () {
      final prepared = preparedTreeDirectoryFor(
        Directory(p.join('Applications', 'אוצריא.app')),
      );
      expect(p.basename(prepared.path), '.אוצריא.app.otzaria-update');
      expect(p.basename(prepared.path).endsWith('.app'), isFalse);
      expect(
        p.equals(
          p.dirname(prepared.path),
          p.absolute(p.normalize('Applications')),
        ),
        isTrue,
      );
    });

    test('Linux: רק עותק עם חותם מחוץ לנתיבי מנהל החבילות הוא נייד', () {
      bool portable(String dir, {bool stamp = true}) => isLinuxPortableInstall(
        executableDirectory: dir,
        hasReleaseStamp: stamp,
      );
      expect(portable('/home/u/otzaria-linux-full/app'), isTrue);
      expect(portable('/home/u/otzaria-linux-full/app', stamp: false), isFalse);
      expect(portable('/opt/otzaria'), isFalse);
      expect(portable('/opt/otzaria/lib'), isFalse);
      expect(portable('/usr/share/otzaria'), isFalse);
      expect(portable('/opt/other/app'), isTrue);
    });

    test('יעד ההתקנה: ה-.app ב-macOS, תיקיית קובץ ההרצה ב-Linux', () {
      final mac = treeInstallTargetFor(
        isMacOS: true,
        executablePath: '/Applications/אוצריא.app/Contents/MacOS/אוצריא',
        isArm64: true,
        macBundlePath: '/Applications/אוצריא.app',
      )!;
      expect(mac.platform, 'macos');
      expect(mac.architecture, 'universal');
      expect(mac.installRoot, '/Applications/אוצריא.app');
      expect(
        p.split(mac.stampDirectory).skip(p.split(mac.installRoot).length),
        ['Contents', 'Resources'],
      );
      expect(
        treeInstallTargetFor(
          isMacOS: true,
          executablePath: '/Volumes/x/אוצריא.app/Contents/MacOS/אוצריא',
          isArm64: false,
          macBundlePath: null,
        ),
        isNull,
      );
      final linux = treeInstallTargetFor(
        isMacOS: false,
        executablePath: p.join('home', 'app', 'otzaria.bin'),
        isArm64: true,
        macBundlePath: null,
      )!;
      expect(linux.platform, 'linux');
      expect(linux.architecture, 'arm64');
      expect(linux.installRoot, p.join('home', 'app'));
      expect(linux.stampDirectory, linux.installRoot);
    });
  });

  group('נכס העדכון ל-Linux', () {
    Map<String, dynamic> asset(String name) => {
      'name': name,
      'browser_download_url': 'https://example.com/$name',
    };
    final assets = [
      asset('otzaria-0.10.1-linux.deb'),
      asset('otzaria-0.10.1-linux.rpm'),
      asset('otzaria-linux-full.tar.zst'),
    ];

    test('התקנה מערכתית מקבלת deb', () {
      expect(
        pickLinuxAssetUrl(assets, isArm64: false),
        'https://example.com/otzaria-0.10.1-linux.deb',
      );
    });

    test('התקנה ניידת לעולם אינה מקבלת deb או rpm', () {
      expect(
        pickLinuxAssetUrl(assets, isArm64: false, isPortableInstall: true),
        isNull,
      );
      expect(
        pickLinuxAssetUrl(
          [asset('otzaria-0.10.1-linux.rpm')],
          isArm64: false,
          isPortableInstall: true,
        ),
        isNull,
      );
    });
  });
}
