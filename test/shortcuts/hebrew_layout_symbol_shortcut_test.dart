// issue #1411: ב-macOS בפריסה עברית, Cmd+, נתפס רק על מקש הפסיק העברי (ליד
// Return) ולא על מקש הפסיק הפיזי (ליד M) — כי המקש הזה מדווח 'ת' כ-logicalKey,
// והזיהוי של סימנים הסתמך על ה-logicalKey בלבד. ב-Windows המנוע מדווח את המקש
// הווירטואלי (comma) ולכן שם זה עבד. כמו במקשי האותיות, המיקום הפיזי מכריע.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';

/// 'ת' — התו שמקש הפסיק הפיזי מפיק בפריסה העברית.
const _hebrewTav = LogicalKeyboardKey(0x05ea);

/// '/' בפריסה העברית יושב על מקש `q`; '.' על מקש הנקודה עצמו מפיק 'ץ'.
const _hebrewFinalTsadi = LogicalKeyboardKey(0x05e5);

KeyDownEvent _event(PhysicalKeyboardKey physical, LogicalKeyboardKey logical) =>
    KeyDownEvent(
      physicalKey: physical,
      logicalKey: logical,
      timeStamp: Duration.zero,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    ShortcutHelper.isMacForTesting = null;
    ShortcutHelper.isWindowsForTesting = null;
  });

  group('קיצור על מקש סימן בפריסה עברית (issue #1411)', () {
    test('macOS: Cmd + מקש הפסיק הפיזי (מדווח "ת") פותח את ctrl+comma', () {
      ShortcutHelper.isMacForTesting = true;
      final event = _event(PhysicalKeyboardKey.comma, _hebrewTav);

      expect(
        ShortcutHelper.matchesShortcut(
          event,
          'ctrl+comma',
          isControlPressed: false,
          isMetaPressed: true,
        ),
        isTrue,
      );
    });

    test('macOS: מקש הפסיק העברי (ליד Return, מדווח comma) ממשיך לעבוד', () {
      ShortcutHelper.isMacForTesting = true;
      final event = _event(PhysicalKeyboardKey.quote, LogicalKeyboardKey.comma);

      expect(
        ShortcutHelper.matchesShortcut(
          event,
          'ctrl+comma',
          isControlPressed: false,
          isMetaPressed: true,
        ),
        isTrue,
      );
    });

    test('תו מקומי לא־מוכר אינו מפעיל התאמה פיזית מחוץ ל-macOS', () {
      ShortcutHelper.isMacForTesting = false;

      expect(
        ShortcutHelper.matchesShortcut(
          _event(PhysicalKeyboardKey.comma, _hebrewTav),
          'ctrl+comma',
          isControlPressed: true,
        ),
        isFalse,
      );
    });

    test('macOS: Cmd + מקש הנקודה הפיזי (מדווח "ץ") תואם ctrl+period', () {
      ShortcutHelper.isMacForTesting = true;
      final event = _event(PhysicalKeyboardKey.period, _hebrewFinalTsadi);

      expect(
        ShortcutHelper.matchesShortcut(
          event,
          'ctrl+period',
          isControlPressed: false,
          isMetaPressed: true,
        ),
        isTrue,
      );
      expect(
        ShortcutHelper.matchesShortcut(
          event,
          'ctrl+comma',
          isControlPressed: false,
          isMetaPressed: true,
        ),
        isFalse,
        reason: 'המיקום הפיזי מכריע — מקש אחר לא נתפס',
      );
    });

    test('פריסה לטינית שמזיזה סימנים נשארת מזוהה לפי התו, לא לפי המיקום', () {
      // גרמנית: המקש הפיזי של '/' מפיק '-'. התו מוכר, ולכן הוא הקובע.
      ShortcutHelper.isMacForTesting = false;
      final event = _event(PhysicalKeyboardKey.slash, LogicalKeyboardKey.minus);

      expect(
        ShortcutHelper.matchesShortcut(
          event,
          'ctrl+minus',
          isControlPressed: true,
        ),
        isTrue,
      );
      expect(
        ShortcutHelper.matchesShortcut(
          event,
          'ctrl+slash',
          isControlPressed: true,
        ),
        isFalse,
      );
    });

    test('הקלטת קיצור: מקש הפסיק הפיזי בפריסה עברית נשמר כ-comma', () {
      ShortcutHelper.isMacForTesting = true;
      final stored = ShortcutHelper.logicalKeyToStore(
        _event(PhysicalKeyboardKey.comma, _hebrewTav),
      );
      expect(stored, LogicalKeyboardKey.comma);
      expect(ShortcutHelper.getKeyLabel(stored), 'comma');
      expect(ShortcutHelper.isRecognized('ctrl+comma'), isTrue);
    });

    test('הקלטת קיצור: תו מוכר על מקש פיזי אחר נשמר כמו שהוא', () {
      expect(
        ShortcutHelper.logicalKeyToStore(
          _event(PhysicalKeyboardKey.slash, LogicalKeyboardKey.minus),
        ),
        LogicalKeyboardKey.minus,
      );
    });
  });
}
