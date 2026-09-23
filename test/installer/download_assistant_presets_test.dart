import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/release/download_assistant_selection.dart';
import '../../tool/release/generate_release_manifest.dart';

/// ההצעות של מסייע ההורדה נגזרות מ-`type` ומ-`required` של הרכיבים. הכללים
/// מוגדרים ב-[buildPresets] (מימוש הייחוס), ו-`download_assistant.iss` חייב
/// לשקף אותם. כאן נבדק ששני הצדדים מסכימים, ושהכללים מופעלים על טבלת
/// [kKnownComponents] אינם מכניסים צורה חלופית של התוכנה להצעה ברירת מחדל.

const _assistant = 'installer/download_assistant.iss';

String _script() =>
    File(_assistant).readAsStringSync().replaceAll('\r\n', '\n');

String _routine(String script, String signature) {
  final start = script.indexOf(signature);
  expect(start, greaterThanOrEqualTo(0), reason: 'לא נמצאה השגרה $signature');
  return script.substring(start, script.indexOf('\nend;', start));
}

/// מניפסט מינימלי מטבלת הרכיבים — רק השדות שכללי הבחירה קוראים.
Map<String, Object?> _manifest(List<ComponentSpec> specs) => {
  'components': [
    for (final spec in specs)
      {
        'id': spec.id,
        'type': spec.type,
        'required': spec.required,
        'platform': ?spec.platform,
        'architecture': ?spec.architecture,
        'packageFormat': ?spec.packageFormat,
        'dependsOn': spec.dependsOn,
        if (spec.installedBy.isNotEmpty) 'installedBy': spec.installedBy,
        'downloadSize': 1,
        'assets': const <Object>[],
      },
  ],
};

Map<String, List<String>> _presets(
  List<ComponentSpec> specs,
  AssistantTarget target,
) => {
  for (final preset in buildPresets(_manifest(specs), target))
    preset.id: preset.members,
};

const _windowsTargets = [
  AssistantTarget(platform: 'windows', architecture: 'x64'),
  AssistantTarget(platform: 'windows', architecture: 'arm64'),
];

const _portableIds = [
  'otzaria-windows-portable-x64',
  'otzaria-windows-portable-arm64',
];

ComponentSpec _spec(String id) =>
    kKnownComponents.firstWhere((s) => s.id == id);

void main() {
  group('הסקריפט משקף את מימוש הייחוס', () {
    test('BuildPresets: אותם סוגים, אותו סדר ואותו כלל חבילה', () {
      final body = _routine(_script(), 'procedure BuildPresets();');

      expect(
        body,
        contains("(CompType[I] = 'application-bundle')"),
        reason: '"מלאה" היא החבילה הגדולה ביותר מסוג application-bundle',
      );
      expect(
        body,
        contains('MembersContain(CompInstalledBy[I], CompId[Bundle])'),
        reason: 'החבילה מגיעה עם מה שהיא מתקינה, כמו ב-buildPresets',
      );
      expect(
        body,
        isNot(contains('ComponentFitsTarget(')),
        reason: 'ההצעות בנויות רק ממה שמוצע ביעד (ComponentIsOffered)',
      );
      expect(
        body,
        contains('(CompDownloadSize[I] > CompDownloadSize[Bundle])'),
        reason: 'החבילה הגדולה ביותר נבחרת, כמו ב-buildPresets',
      );
      final calls = RegExp(
        r"CollectByTypes\('([^']*)',\s*(False|True)\)",
      ).allMatches(body).map((m) => '${m.group(1)}|${m.group(2)}').toList();
      expect(
        calls,
        [
          'application,library,dependency,|False',
          'library,|False',
          'application,|False',
          '|True',
          'application,|False',
        ],
        reason:
            'הרשימות חייבות להתאים ל-buildPresets — מלאה (ורק עם ספרייה), בסיסית, עדכון',
      );
      final ids = RegExp(
        r"AddPreset\('([a-z]+)'",
      ).allMatches(body).map((m) => m.group(1)).toList();
      expect(ids, ['full', 'basic', 'update']);
    });

    test('ComponentFitsTarget בודק את שלושת השדות', () {
      final fits = _routine(_script(), 'function ComponentFitsTarget(');
      for (final pair in const [
        ('CompPlatform', 'TargetPlatform'),
        ('CompArch', 'TargetArchitecture'),
        ('CompFormat', 'TargetFormat'),
      ]) {
        expect(fits, contains('not IsWildcard(${pair.$1}[Index])'));
        expect(fits, contains('(${pair.$1}[Index] <> ${pair.$2})'));
      }
      expect(
        _routine(_script(), 'function IsWildcard('),
        contains("(Value = '') or (Value = 'any')"),
      );
    });

    test('רכיב מוצע: מתאים, ניתן להרצה, ויש מי שמתקין אותו', () {
      final offered = _routine(_script(), 'function ComponentIsOffered(');
      expect(offered, contains('ComponentFitsTarget(Index)'));
      expect(offered, contains('ComponentIsRunnable(Index)'));
      expect(offered, contains('InstallerFor(Index) >= 0'));
      expect(
        _routine(_script(), 'function ComponentIsRunnable('),
        contains('(AssetSize[A] >= MaxSingleOutputFileSize)'),
      );
      for (final routine in const [
        'function CollectByTypes(',
        'procedure RefreshCustomPage();',
      ]) {
        expect(
          _routine(_script(), routine),
          contains('ComponentIsOffered(I)'),
          reason: routine,
        );
      }
    });

    test('בחירה אישית נסגרת כמו ההצעות', () {
      final next = _routine(_script(), 'function NextButtonClick(');
      expect(next, contains('Members := WithDependencies(Members);'));
    });

    test('סגירת התלויות: dependsOn שמוצע, והמתקין של מה שנבחר', () {
      final closure = _routine(_script(), 'function WithDependencies(');
      expect(closure, contains('ComponentIsOffered(Idx)'));
      expect(closure, contains('Idx := InstallerFor(I);'));
      expect(
        _routine(_script(), 'function CanonicalMembers('),
        contains('MembersContain(Members, CompId[I])'),
        reason: 'סדר המניפסט, כמו withDependencies',
      );
    });
  });

  group('הגרסה הניידת אינה רכיב נוסף של אותה התקנה', () {
    test('הסוג שלה נפרד מסוג המתקין', () {
      final installer = _spec('otzaria-windows-x64').type;
      for (final id in _portableIds) {
        expect(
          _spec(id).type,
          isNot(installer),
          reason: 'סוג משותף עם המתקין מחזיר את צירוף שתי הצורות להצעה',
        );
      }
      expect(
        _portableIds.map((id) => _spec(id).type).toSet(),
        {'application-portable'},
        reason: 'שתי הגרסאות הניידות חולקות סוג אחד',
      );
      expect(
        _spec('otzaria-windows-portable-arm64').architecture,
        'arm64',
        reason: 'הניידת של ARM אינה מוצעת למחשב x64',
      );
    });

    test('אינה נכנסת לאף הצעה שאינה "בחירה אישית"', () {
      for (final target in _windowsTargets) {
        _presets(kKnownComponents, target).forEach((name, members) {
          for (final id in _portableIds) {
            expect(
              members,
              isNot(contains(id)),
              reason:
                  'ההצעה "$name" ביעד ${target.architecture} מורידה גם את הגרסה הניידת',
            );
          }
        });
      }
    });
  });

  group('כל הצעה נשארת בעלת תוכן', () {
    test('"מלאה" היא המתקין המלא של אותה ארכיטקטורה', () {
      final x64 = _presets(kKnownComponents, _windowsTargets[0]);
      final arm64 = _presets(kKnownComponents, _windowsTargets[1]);

      expect(x64['full'], hasLength(1));
      expect(x64['basic'], contains('otzaria-windows-x64'));
      expect(arm64['full'], ['otzaria-windows-full-arm64']);
      expect(arm64['basic'], contains('otzaria-windows-arm64'));
    });

    test('בלי מתקין מלא ל-ARM64 — אין "מלאה", ולא מתקין x64', () {
      final arm64 = _presets(
        kKnownComponents
            .where((s) => s.id != 'otzaria-windows-full-arm64')
            .toList(),
        _windowsTargets[1],
      );
      expect(arm64.keys, ['basic']);
      expect(arm64['basic'], ['otzaria-windows-arm64']);
    });

    test('"בסיסית" ו"עדכון" מתלכדות כשאין רכיב required נוסף', () {
      final presets = _presets(kKnownComponents, _windowsTargets[0]);
      expect(
        presets.keys,
        isNot(contains('update')),
        reason: 'איחוד ההצעות הזהות הוא מה שמשאיר שתי שורות בלבד במסך',
      );
    });

    test('כל פלטפורמה ביעד מקבלת לפחות הצעה אחת', () {
      final manifest = _manifest(kKnownComponents);
      for (final platform in platformChoices(manifest)) {
        final archs = architectureChoices(manifest, platform);
        for (final arch in archs.isEmpty ? [''] : archs) {
          final formats = packageFormatChoices(manifest, platform, arch);
          for (final format in formats.isEmpty ? [''] : formats) {
            final target = AssistantTarget(
              platform: platform,
              architecture: arch,
              packageFormat: format,
            );
            expect(
              buildPresets(manifest, target),
              isNotEmpty,
              reason: '$platform/$arch/$format',
            );
          }
        }
      }
    });
  });

  group('רכיב עתידי נוחת במקום סביר בלי שינוי קוד', () {
    const futureRequired = ComponentSpec(
      id: 'future-required',
      name: 'רכיב חדש נדרש',
      description: 'סוג שהסקריפט אינו מכיר.',
      type: 'runtime-blob',
      required: true,
      installOrder: 15,
      platform: 'windows',
      assets: [AssetSpec(pattern: r'^future\.bin$')],
    );
    const futureOptional = ComponentSpec(
      id: 'future-optional',
      name: 'רכיב חדש רשות',
      description: 'סוג שהסקריפט אינו מכיר.',
      type: 'runtime-blob',
      required: false,
      installOrder: 15,
      platform: 'windows',
      assets: [AssetSpec(pattern: r'^future-opt\.bin$')],
    );

    test('סוג לא מוכר עם required נכנס ל"בסיסית"', () {
      final presets = _presets([
        ...kKnownComponents,
        futureRequired,
      ], _windowsTargets[0]);
      expect(presets['basic'], contains('future-required'));
    });

    test('סוג לא מוכר ברשות נשאר ל"בחירה אישית" בלבד', () {
      final presets = _presets([
        ...kKnownComponents,
        futureOptional,
      ], _windowsTargets[0]);
      presets.forEach((name, members) {
        expect(members, isNot(contains('future-optional')), reason: name);
      });
    });
  });
}
