import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('lastActiveSlot', () {
    setUp(() => MultiWindowService.debugSupportedOverride = true);
    tearDown(() {
      MultiWindowService.debugSupportedOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MultiWindowService.channel, null);
    });

    void mock(Future<Object?> Function(MethodCall call) handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MultiWindowService.channel, handler);
    }

    test('מחזיר את המשבצת שה-runner דיווח עליה', () async {
      mock((call) async => call.method == 'lastActiveSlot' ? 3 : null);
      expect(await const MultiWindowService().lastActiveSlot(), 3);
    });

    test('אין חלון גלוי — null', () async {
      mock((call) async => null);
      expect(await const MultiWindowService().lastActiveSlot(), isNull);
    });

    test('כשל בערוץ אינו זורק ומחזיר null', () async {
      mock((call) async => throw PlatformException(code: 'boom'));
      expect(await const MultiWindowService().lastActiveSlot(), isNull);
    });
  });

  group('payloadHasTab', () {
    test('מזהה מטען עם כרטיסיה בלי לפענח אותה', () {
      // ⚠️ הנקודה: הזיהוי חייב לעבוד גם כש-`Settings` לא מאותחל, כי הוא
      // נקרא בנקודת הכניסה של החלון — לפני `AppBootstrap`. פענוח מלא של
      // `TextBookTab` היה זורק שם, וזה בדיוק הבאג שגרם לכרטיסיה להיעלם.
      final payload = jsonEncode({
        'version': 1,
        'tab': {'type': 'TextBookTab', 'title': 'בראשית'},
        'settings': {'key-library-path': r'C:\books'},
      });
      expect(MultiWindowService.payloadHasTab(payload), isTrue);
    });

    test('מטען בלי כרטיסיה — חלון חדש ריק', () {
      final payload = jsonEncode({
        'version': 1,
        'settings': {'key-library-path': r'C:\books'},
      });
      expect(MultiWindowService.payloadHasTab(payload), isFalse);
    });

    test('null, ריק ופגום מוחזרים כ-false ולא זורקים', () {
      expect(MultiWindowService.payloadHasTab(null), isFalse);
      expect(MultiWindowService.payloadHasTab(''), isFalse);
      expect(MultiWindowService.payloadHasTab('{not json'), isFalse);
      expect(MultiWindowService.payloadHasTab('[]'), isFalse);
    });

    test('שדה tab שאינו אובייקט אינו נחשב כרטיסיה', () {
      expect(
        MultiWindowService.payloadHasTab(jsonEncode({'tab': 'בראשית'})),
        isFalse,
      );
    });
  });

  group('decodePayload', () {
    test('משחזר כרטיסיית כלי', () {
      final payload = jsonEncode({
        'version': 1,
        'tab': ToolTab(toolId: 'acronyms', title: 'ראשי תיבות').toJson(),
      });
      final tab = MultiWindowService.decodePayload(payload);
      expect(tab, isA<ToolTab>());
      expect((tab! as ToolTab).toolId, 'acronyms');
    });

    test('מטען פגום מחזיר null ואינו זורק', () {
      expect(MultiWindowService.decodePayload('{not json'), isNull);
      expect(MultiWindowService.decodePayload(jsonEncode({'tab': 5})), isNull);
      expect(
        MultiWindowService.decodePayload(
          jsonEncode({
            'tab': {'type': 'NoSuchTab'},
          }),
        ),
        isNull,
      );
    });
  });

  group('decodePreferences', () {
    test('מחזיר את ההגדרות שנזרעו', () {
      final payload = jsonEncode({
        'version': 1,
        'settings': {'key-library-path': r'C:\books', 'key-dark-mode': true},
      });
      final prefs = MultiWindowService.decodePreferences(payload);
      expect(prefs['key-library-path'], r'C:\books');
      expect(prefs['key-dark-mode'], true);
    });

    test('מטען בלי הגדרות מחזיר מפה ריקה', () {
      expect(MultiWindowService.decodePreferences(null), isEmpty);
      expect(MultiWindowService.decodePreferences('{not json'), isEmpty);
      expect(MultiWindowService.decodePreferences(jsonEncode({})), isEmpty);
    });
  });

  group('canTransfer', () {
    test('כרטיסיית כלי ניתנת להעברה', () {
      expect(
        MultiWindowService.canTransfer(
          ToolTab(toolId: 'acronyms', title: 'ראשי תיבות'),
        ),
        isTrue,
      );
    });

    test('כרטיסיה שאינה שורדת סריאליזציה נחסמת ואינה זורקת', () {
      // ⚠️ זו ההגנה מפני אובדן: בלעדיה כרטיסיה שלא ניתנת לשחזור הייתה
      // נעלמת מהחלון המקורי ולא נפתחת בחדש.
      expect(MultiWindowService.canTransfer(_UnserializableTab()), isFalse);
    });

    test('טאב מפוצל שאיבד חלונית נחסם — "לא זרק" אינו "נאמן"', () {
      // ⚠️ `decodeCombinedTab` בולע חלונית שנכשלה ומחזיר את השורדת. זו
      // התנהגות נכונה בשחזור מדיסק — עדיף חצי ספר מכלום — ואובדן מידע
      // בהעברה, כי הכרטיסיה כבר נמחקת מהמקור. הבדיקה הקודמת בדקה רק
      // שהסריאליזציה אינה זורקת, ולכן פיצול חצי היה עובר אותה.
      final half = CombinedTab(
        rightTab: ToolTab(toolId: 'acronyms', title: 'ראשי תיבות'),
        leftTab: _UnserializableTab(),
      );
      expect(MultiWindowService.canTransfer(half), isFalse);
    });

    test('טאב מפוצל ששתי חלוניותיו שורדות עובר', () {
      final whole = CombinedTab(
        rightTab: ToolTab(toolId: 'acronyms', title: 'ראשי תיבות'),
        leftTab: ToolTab(toolId: 'gematria', title: 'גימטריה'),
      );
      expect(MultiWindowService.canTransfer(whole), isTrue);
    });
  });

  group('transferTargets', () {
    tearDown(() => MultiWindowService.publishKnownPeers(const []));

    test('חלון מוסתר אינו יעד להעברה', () {
      // ⚠️ חלון שהמשתמש סגר מוסתר ולא נהרס וממשיך לענות על האפיק, ולכן
      // הופיע ב"העבר לחלון קיים", אישר קבלה, והמקור מחק את הכרטיסיה.
      MultiWindowService.publishKnownPeers(const [
        WindowPeer(slot: 2, title: 'פתוח', tabCount: 1),
        WindowPeer(slot: 3, title: 'סגור', tabCount: 4, isVisible: false),
      ]);
      expect(
        MultiWindowService.transferTargets.map((p) => p.slot),
        [2],
      );
    });
  });
}

/// כרטיסיה שה-JSON שלה אינו ניתן לשחזור — `type` שאינו מוכר ל-
/// `OpenedTab.fromJson`.
class _UnserializableTab extends OpenedTab {
  _UnserializableTab() : super('כרטיסיה שבורה');

  @override
  Map<String, dynamic> toJson() => {'type': 'DefinitelyNotATabType'};

  @override
  OpenedTab clone() => _UnserializableTab();
}
