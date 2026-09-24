import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'differential/swap_plan.dart';
import 'shell_quote.dart';

const String kAtomicTreeSwapHelperName = 'otzaria-atomic-swap';

File atomicTreeSwapHelperFor(String executablePath) =>
    File(p.join(p.dirname(executablePath), kAtomicTreeSwapHelperName));

/// בודק שהכרך של ההתקנה תומך בהחלפה אטומית לפני הורדת חבילת העדכון.
/// [helper] הוא אותו עזר שהסקריפט יריץ: ב-macOS הוא ב-`Contents/MacOS`, לא בשורש ה-bundle.
Future<bool> atomicTreeSwapSupported(Directory installRoot, File helper) async {
  if (!await helper.exists()) return false;
  Directory? first;
  Directory? second;
  try {
    final parent = installRoot.parent.path;
    first = await Directory(parent).createTemp('.otzaria-swap-check-');
    second = await Directory(parent).createTemp('.otzaria-swap-check-');
    final result = await Process.run(helper.path, [first.path, second.path]);
    return result.exitCode == 0;
  } on FileSystemException {
    return false;
  } on ProcessException {
    return false;
  } finally {
    if (first != null && await first.exists()) {
      await first.delete(recursive: true);
    }
    if (second != null && await second.exists()) {
      await second.delete(recursive: true);
    }
  }
}

/// בונה את סקריפט ההחלפה של עדכון עץ (macOS, Linux נייד): ממתין ליציאת
/// אוצריא, ומחליף את תיקיית ההתקנה בעותק המוכן בפעולה אטומית באותו כרך.
/// אוצריא שלא יצאה בזמן — הסקריפט מוותר לפני
/// שנגע בדבר וכותב את [kSwapGaveUpFileName], כמו המעדכן של Windows.
@visibleForTesting
String buildTreeSwapScript({
  required String installedPath,
  required String preparedPath,
  required String workPath,
  required String swapHelperPath,
  required int appPid,
  String? relaunchCommand,
  Duration waitTimeout = const Duration(minutes: 2),
  bool logToWork = false,
}) {
  final polls = waitTimeout.inMilliseconds ~/ 200;
  return '''
#!/bin/sh
# עדכון אוצריא — נוצר אוטומטית על ידי מנגנון העדכון.
INSTALLED=${shellQuote(installedPath)}
PREPARED=${shellQuote(preparedPath)}
WORK=${shellQuote(workPath)}
SWAPPER=${shellQuote(swapHelperPath)}
${logToWork ? 'exec >"\$WORK/swap.log" 2>&1\n' : ''}
relaunch() {
  ${relaunchCommand ?? ':'}
}

echo "ממתין לסגירת אוצריא..."
polls=0
while kill -0 $appPid 2>/dev/null; do
  if [ "\$polls" -ge $polls ]; then
    echo "אוצריא לא נסגרה — העדכון לא הותקן" >&2
    : > "\$WORK/$kSwapGaveUpFileName"
    exit 1
  fi
  sleep 0.2
  polls=\$((polls + 1))
done

if [ ! -d "\$PREPARED" ]; then
  echo "שגיאה: העדכון המוכן חסר" >&2
  exit 1
fi
if ! "\$SWAPPER" "\$INSTALLED" "\$PREPARED"; then
  echo "שגיאה בהתקנה — הגרסה הקודמת נשארה במקומה" >&2
  relaunch
  exit 1
fi
rm -rf "\$PREPARED" "\$WORK"
echo "העדכון הושלם בהצלחה"
relaunch
''';
}

/// פקודת ההפעלה מחדש אחרי ההחלפה. ב-Linux מופעל ה-launcher `otzaria`
/// שמגדיר את סביבת WPE, ולא `otzaria.bin` שהוא קובץ ההרצה בפועל.
@visibleForTesting
String treeRelaunchCommand({
  required bool isMacOS,
  required String installedPath,
  required String executablePath,
}) {
  if (isMacOS) return 'open -n "\$INSTALLED"';
  final relative = p.posix.relative(executablePath, from: installedPath);
  final launcher = relative.endsWith('.bin')
      ? relative.substring(0, relative.length - '.bin'.length)
      : relative;
  return 'nohup "\$INSTALLED"/${shellQuote(launcher)} >/dev/null 2>&1 &';
}

/// כותב את סקריפט ההחלפה ל-[workRoot] ומשגר אותו כתהליך ששורד את סגירת
/// אוצריא: ב-macOS דרך `open` ב-Terminal, כמו העדכון הקיים; ב-Linux
/// כתהליך מנותק שכותב יומן לתיקיית העבודה. זורק אם השיגור נכשל.
Future<void> launchTreeSwap({
  required Directory installRoot,
  required Directory preparedRoot,
  required Directory workRoot,
  required bool relaunchApp,
}) async {
  final isMac = Platform.isMacOS;
  final installed = installRoot.absolute.path;
  final helper = atomicTreeSwapHelperFor(Platform.resolvedExecutable);
  if (!await helper.exists()) {
    throw FileSystemException('atomic swap helper is missing', helper.path);
  }
  final script = File(
    p.join(
      workRoot.path,
      isMac ? 'otzaria-update.command' : 'otzaria-update.sh',
    ),
  );
  await script.parent.create(recursive: true);
  final gaveUp = File(p.join(workRoot.path, kSwapGaveUpFileName));
  if (await gaveUp.exists()) await gaveUp.delete();
  await script.writeAsString(
    buildTreeSwapScript(
      installedPath: installed,
      preparedPath: preparedRoot.absolute.path,
      workPath: workRoot.absolute.path,
      swapHelperPath: helper.absolute.path,
      appPid: pid,
      relaunchCommand: relaunchApp
          ? treeRelaunchCommand(
              isMacOS: isMac,
              installedPath: installed,
              executablePath: Platform.resolvedExecutable,
            )
          : null,
      logToWork: !isMac,
    ),
  );
  final scriptChmod = await Process.run('chmod', ['+x', script.path]);
  if (scriptChmod.exitCode != 0) {
    throw FileSystemException('swap script is not executable', script.path);
  }

  if (isMac) {
    final result = await Process.run('open', [script.path]);
    if (result.exitCode != 0) {
      throw Exception('Failed to launch the update script: ${result.stderr}');
    }
    return;
  }
  await Process.start('/bin/sh', [
    script.path,
  ], mode: ProcessStartMode.detached);
}

/// התקנה שמתעדכנת כעץ: מה מחליפים, איפה החותם, ואיזו חבילה מתאימה לה.
class TreeInstallTarget {
  const TreeInstallTarget({
    required this.installRoot,
    required this.stampDirectory,
    required this.platform,
    required this.architecture,
  });

  final String installRoot;
  final String stampDirectory;
  final String platform;
  final String architecture;
}

/// מזהה את התקנת העץ שרצה כעת. ב-macOS זה ה-`.app` (החותם ב-
/// `Contents/Resources`, שם נתונים נחתמים), וב-Linux תיקיית קובץ ההרצה.
/// `null` כשה-bundle אינו בר-עדכון (Translocation, DMG) — ראה
/// `findInstalledMacAppBundlePath`.
TreeInstallTarget? treeInstallTargetFor({
  required bool isMacOS,
  required String executablePath,
  required bool isArm64,
  required String? macBundlePath,
}) {
  if (isMacOS) {
    if (macBundlePath == null) return null;
    return TreeInstallTarget(
      installRoot: macBundlePath,
      stampDirectory: p.join(macBundlePath, 'Contents', 'Resources'),
      platform: 'macos',
      architecture: 'universal',
    );
  }
  final dir = p.dirname(executablePath);
  return TreeInstallTarget(
    installRoot: dir,
    stampDirectory: dir,
    platform: 'linux',
    architecture: isArm64 ? 'arm64' : 'x64',
  );
}
