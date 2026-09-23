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
    }) => {
      'id': id,
      'type': type,
      'required': required,
      'downloadSize': size,
      'dependsOn': dependsOn,
      'platform': ?platform,
      'architecture': ?architecture,
    };

    test('תלות שאינה מתאימה ליעד מדולגת ואינה מפילה את ההצעה', () {
      final presets = buildPresets(
        manifest([
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
          component('lib', 'library', platform: 'any', dependsOn: ['app-x64']),
        ]),
        const AssistantTarget(platform: 'windows', architecture: 'arm64'),
      );
      expect(presets.first.members, ['app-arm', 'lib']);
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
