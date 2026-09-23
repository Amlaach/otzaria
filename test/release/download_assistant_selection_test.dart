import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/download_assistant/fixtures/generate_fixtures.dart';
import '../../tool/release/download_assistant_selection.dart';
import '../../tool/release/generate_release_manifest.dart';

void main() {
  group('קובצי הייחוס של החוזה', () {
    // שלושת המסייעים נבדקים מול הקבצים האלה; קובץ מיושן היה מאשר מימוש שגוי.
    test('release-manifest.json תואם לגנרטור', () {
      final onDisk = File(
        '$kFixtureDir/release-manifest.json',
      ).readAsStringSync();
      expect(
        onDisk,
        encodeFixture(buildFixtureManifest()),
        reason:
            'run: dart run tool/download_assistant/fixtures/generate_fixtures.dart',
      );
    });

    test('expected-selections.json תואם למימוש הייחוס', () {
      final manifest =
          jsonDecode(
                File('$kFixtureDir/release-manifest.json').readAsStringSync(),
              )
              as Map<String, Object?>;
      expect(validateReleaseManifest(manifest), isEmpty);
      final onDisk = File(
        '$kFixtureDir/expected-selections.json',
      ).readAsStringSync();
      expect(
        onDisk,
        encodeFixture(buildExpectedSelections(manifest)),
        reason:
            'run: dart run tool/download_assistant/fixtures/generate_fixtures.dart',
      );
    });

    test('הווריאנט של FULL בגודל 4 GiB תואם למימוש הייחוס', () {
      final manifest = buildLargeFullFixtureManifest();
      expect(
        File(
          '$kFixtureDir/release-manifest-large-full.json',
        ).readAsStringSync(),
        encodeFixture(manifest),
        reason:
            'run: dart run tool/download_assistant/fixtures/generate_fixtures.dart',
      );
      expect(
        File(
          '$kFixtureDir/expected-selections-large-full.json',
        ).readAsStringSync(),
        encodeFixture(
          buildExpectedSelections(manifest, targets: kLargeFullTargets),
        ),
        reason:
            'run: dart run tool/download_assistant/fixtures/generate_fixtures.dart',
      );
    });
  });

  group('כל הצעה ניתנת להתקנה', () {
    List<AssistantTarget> allTargets(Map<String, Object?> manifest) => [
      for (final platform in platformChoices(manifest))
        for (final arch in [
          ...architectureChoices(manifest, platform),
          if (architectureChoices(manifest, platform).isEmpty) '',
        ])
          for (final format in [
            ...packageFormatChoices(manifest, platform, arch),
            if (packageFormatChoices(manifest, platform, arch).isEmpty) '',
          ])
            AssistantTarget(
              platform: platform,
              architecture: arch,
              packageFormat: format,
            ),
    ];

    // חוזה: כל רכיב שמותקן על ידי אחר מגיע עם מי שמתקין אותו, אין בהצעה
    // exe שאי אפשר להריץ, ו"מלאה" מביאה ספרייה (בחבילה או לצד התוכנה).
    for (final entry in {
      'release-manifest.json': buildFixtureManifest,
      'release-manifest-large-full.json': buildLargeFullFixtureManifest,
    }.entries) {
      test(entry.key, () {
        final manifest = entry.value();
        final byId = {
          for (final c
              in (manifest['components'] as List).cast<Map<String, Object?>>())
            c['id']: c,
        };
        for (final target in allTargets(manifest)) {
          for (final preset in buildPresets(manifest, target)) {
            final label = '${target.toJson()} ${preset.id}';
            for (final id in preset.members) {
              final component = byId[id]!;
              expect(
                componentIsOffered(manifest, component, target),
                isTrue,
                reason: '$label: $id',
              );
              final installers =
                  (component['installedBy'] as List?)?.cast<String>() ??
                  const <String>[];
              expect(
                component['type'] != 'library' || installers.isNotEmpty,
                isTrue,
                reason: '$label: הספרייה $id בלי מתקין',
              );
              if (installers.isEmpty) continue;
              expect(
                preset.members.any(installers.contains),
                isTrue,
                reason: '$label: $id בלי המתקין שלו',
              );
            }
            if (preset.id == 'full') {
              expect(
                preset.members.any(
                  (id) =>
                      byId[id]!['type'] == 'application-bundle' ||
                      byId[id]!['type'] == 'library',
                ),
                isTrue,
                reason: '$label: "מלאה" בלי ספרייה',
              );
            }
          }
        }
      });
    }
  });

  group('componentFitsTarget', () {
    const linuxDebX64 = AssistantTarget(
      platform: 'linux',
      architecture: 'x64',
      packageFormat: 'deb',
    );

    test('שדה חסר או any מתאים לכל יעד', () {
      expect(componentFitsTarget({'id': 'a'}, linuxDebX64), isTrue);
      expect(
        componentFitsTarget({
          'platform': 'any',
          'architecture': 'any',
          'packageFormat': 'any',
        }, linuxDebX64),
        isTrue,
      );
    });

    test('packageFormat any אינו פורמט לבחירה', () {
      final manifest = {
        'components': [
          {'platform': 'linux', 'type': 'application', 'packageFormat': 'deb'},
          {'platform': 'linux', 'type': 'library', 'packageFormat': 'any'},
        ],
      };
      expect(packageFormatChoices(manifest, 'linux', 'x64'), ['deb']);
    });

    test('פלטפורמה, ארכיטקטורה ופורמט חייבים להתאים', () {
      expect(
        componentFitsTarget({'platform': 'windows'}, linuxDebX64),
        isFalse,
      );
      expect(
        componentFitsTarget({
          'platform': 'linux',
          'architecture': 'arm64',
        }, linuxDebX64),
        isFalse,
      );
      expect(
        componentFitsTarget({
          'platform': 'linux',
          'architecture': 'x64',
          'packageFormat': 'rpm',
        }, linuxDebX64),
        isFalse,
      );
    });

    test('portable מסנן כל חבילה של מנהל חבילות', () {
      const portable = AssistantTarget(
        platform: 'linux',
        architecture: 'x64',
        packageFormat: kPortablePackageFormat,
      );
      expect(
        componentFitsTarget({
          'platform': 'linux',
          'packageFormat': 'deb',
        }, portable),
        isFalse,
      );
      expect(componentFitsTarget({'platform': 'linux'}, portable), isTrue);
    });

    test('פלטפורמה עתידית שאינה מוכרת לעולם אינה נכנסת ליעד מוכר', () {
      for (final platform in kAssistantPlatforms) {
        expect(
          componentFitsTarget({
            'platform': 'ios',
          }, AssistantTarget(platform: platform)),
          isFalse,
        );
      }
    });
  });

  group('shouldAssembleSplitAsset', () {
    Map<String, Object?> asset(String name, int size) => {
      'name': name,
      'size': size,
    };

    test('Windows: exe מתחת ל-4 GiB בלבד', () {
      expect(shouldAssembleSplitAsset(asset('a.exe', 100), 'windows'), isTrue);
      expect(
        shouldAssembleSplitAsset(
          asset('a.exe', kMaxSingleOutputFileSize),
          'windows',
        ),
        isFalse,
      );
      // ארכיון הספרייה נצרך כחלקים על ידי מתקין ה-FULL המאונדקס.
      expect(
        shouldAssembleSplitAsset(asset('lib.tar.zst', 100), 'windows'),
        isFalse,
      );
    });

    test('שאר היעדים: כל נכס מתחת ל-4 GiB, כי המשתמש פורס אותו', () {
      for (final platform in const ['linux', 'macos', 'android']) {
        expect(
          shouldAssembleSplitAsset(asset('full.tar.zst', 100), platform),
          isTrue,
        );
        expect(
          shouldAssembleSplitAsset(
            asset('full.tar.zst', kMaxSingleOutputFileSize),
            platform,
          ),
          isFalse,
          reason: 'FAT32 אינו מחזיק קובץ של 4 GiB',
        );
      }
    });
  });

  group('defaultPackageFormat', () {
    const choices = ['deb', 'rpm', 'portable'];

    test('ID קודם ל-ID_LIKE', () {
      expect(
        defaultPackageFormat('ID=fedora\nID_LIKE=debian\n', choices),
        'rpm',
      );
    });

    test('פורמט שאינו בנמצא נופל לבחירה הראשונה', () {
      expect(defaultPackageFormat('ID=arch\n', const ['deb', 'rpm']), 'deb');
      expect(defaultPackageFormat('ID=fedora\n', const ['deb']), 'deb');
    });

    test('בלי אפשרויות — ריק', () {
      expect(defaultPackageFormat(null, const []), '');
    });
  });

  group('buildPresets', () {
    Map<String, Object?> manifest(List<Map<String, Object?>> components) => {
      'components': components,
    };

    Map<String, Object?> component(
      String id,
      String type, {
      String? platform,
      String? architecture,
      bool required = false,
      int size = 1,
      List<String> dependsOn = const [],
      List<String>? installedBy,
      List<Map<String, Object?>> assets = const [],
    }) => {
      'id': id,
      'type': type,
      'required': required,
      'downloadSize': size,
      'dependsOn': dependsOn,
      'installedBy': ?installedBy,
      'platform': ?platform,
      'architecture': ?architecture,
      'assets': assets,
    };

    const x64 = AssistantTarget(platform: 'windows', architecture: 'x64');
    const arm64 = AssistantTarget(platform: 'windows', architecture: 'arm64');

    List<Map<String, Object?>> windowsWithLibrary({int fullSize = 90}) => [
      component(
        'app-arm',
        'application',
        platform: 'windows',
        architecture: 'arm64',
      ),
      component(
        'app-x64',
        'application',
        platform: 'windows',
        architecture: 'x64',
        required: true,
      ),
      component(
        'full',
        'application-bundle',
        platform: 'windows',
        architecture: 'x64',
        size: fullSize,
        assets: [
          {'kind': 'split', 'name': 'full.exe', 'size': fullSize},
        ],
      ),
      component(
        'indexed',
        'application-bundle',
        platform: 'windows',
        architecture: 'x64',
        size: 5,
      ),
      component(
        'lib',
        'library',
        platform: 'any',
        size: 80,
        installedBy: ['indexed'],
      ),
    ];

    test('תלות שאינה מוצעת ביעד מדולגת', () {
      expect(
        withDependencies(
          manifest([
            component(
              'app-arm',
              'application',
              platform: 'windows',
              architecture: 'arm64',
              dependsOn: ['app-x64'],
            ),
            component(
              'app-x64',
              'application',
              platform: 'windows',
              architecture: 'x64',
            ),
          ]),
          ['app-arm'],
          arm64,
        ),
        ['app-arm'],
      );
    });

    // ספרייה שרק מתקין x64 קורא צורפה פעם למתקין ARM64 הרגיל.
    test('ספרייה שאין לה מתקין ביעד אינה מוצעת ואינה ב"מלאה"', () {
      final m = manifest(windowsWithLibrary());
      final library = (m['components'] as List).last as Map<String, Object?>;
      expect(componentIsOffered(m, library, arm64), isFalse);
      final presets = buildPresets(m, arm64);
      expect(presets.map((p) => p.id), ['basic']);
      expect(presets.single.members, ['app-arm']);
    });

    test('בחירה אישית של הספרייה מביאה את המתקין שקורא אותה', () {
      expect(withDependencies(manifest(windowsWithLibrary()), ['lib'], x64), [
        'indexed',
        'lib',
      ]);
    });

    test('exe של 4 GiB אינו מוצע; "מלאה" עוברת למתקין שקורא את הספרייה', () {
      final m = manifest(
        windowsWithLibrary(fullSize: kMaxSingleOutputFileSize),
      );
      final full = (m['components'] as List).cast<Map<String, Object?>>()[2];
      expect(componentIsOffered(m, full, x64), isFalse);
      expect(buildPresets(m, x64).first.members, ['indexed', 'lib']);

      final runnable = manifest(
        windowsWithLibrary(fullSize: kMaxSingleOutputFileSize - 1),
      );
      expect(buildPresets(runnable, x64).first.members, ['full']);
    });

    test('החבילה הגדולה ביותר נבחרת להצעה המלאה', () {
      final presets = buildPresets(
        manifest([
          component('small', 'application-bundle', platform: 'macos', size: 5),
          component('big', 'application-bundle', platform: 'macos', size: 9),
        ]),
        const AssistantTarget(platform: 'macos'),
      );
      expect(presets.single.members, ['big']);
    });

    test('יעד בלי רכיבים — אין הצעות, ורק "בחירה אישית" תוצג', () {
      expect(
        buildPresets(
          manifest([component('w', 'application', platform: 'windows')]),
          const AssistantTarget(platform: 'android'),
        ),
        isEmpty,
      );
    });
  });

  test('שם תת-התיקייה נושא את שם הפלטפורמה', () {
    expect(outputSubfolderName('windows'), 'אוצריא להתקנה ל-Windows');
    expect(outputSubfolderName('linux'), 'אוצריא להתקנה ל-Linux');
    expect(plannedOutputSubfolder(const ['a'], 'linux'), '');
    expect(
      plannedOutputSubfolder(const ['a', 'b'], 'macos'),
      'אוצריא להתקנה ל-macOS',
    );
  });
}
