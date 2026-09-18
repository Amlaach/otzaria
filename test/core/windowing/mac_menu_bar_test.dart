import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/mac_menu_bar.dart';

void main() {
  group('menuShortcutActivator', () {
    test('ctrl בהגדרות הוא Command בתפריט של מק', () {
      final activator = menuShortcutActivator('ctrl+l');
      expect(activator, isNotNull);
      expect(activator!.trigger, LogicalKeyboardKey.keyL);
      expect(activator.meta, isTrue);
      expect(activator.shift, isFalse);
      expect(activator.alt, isFalse);
    });

    test('מקש בעל שם מהמפה המרכזית שאינו סימן תלוי־פריסה', () {
      final activator = menuShortcutActivator('ctrl+f11');
      expect(activator!.trigger, LogicalKeyboardKey.f11);
      expect(activator.meta, isTrue);
    });

    test('סימן תלוי־פריסה נשאר לטיפול Flutter לפי מיקום פיזי', () {
      expect(menuShortcutActivator('ctrl+comma'), isNull);
      expect(menuShortcutActivator('ctrl+period'), isNull);
    });

    test('צירוף עם shift', () {
      final activator = menuShortcutActivator('ctrl+shift+f');
      expect(activator!.trigger, LogicalKeyboardKey.keyF);
      expect(activator.meta, isTrue);
      expect(activator.shift, isTrue);
    });

    test('meta נחשב כמו ctrl', () {
      expect(menuShortcutActivator('meta+b')!.meta, isTrue);
    });

    test('alt נשמר', () {
      expect(menuShortcutActivator('alt+b')!.alt, isTrue);
    });

    test('ריק או null מחזיר null', () {
      expect(menuShortcutActivator(null), isNull);
      expect(menuShortcutActivator(''), isNull);
    });

    test('מקש שאינו ניתן לייצוג מחזיר null במקום קיצור שגוי', () {
      expect(menuShortcutActivator('ctrl+שין'), isNull);
      expect(menuShortcutActivator('ctrl'), isNull);
    });

    test('כל ברירות המחדל שאינן סימנים תלויי־פריסה ניתנות להצהרה בתפריט', () {
      // הצהרה שגויה בתפריט הייתה חוטפת את המקש מ-KeyboardShortcuts.
      for (final shortcut in const [
        'ctrl+l',
        'ctrl+f',
        'ctrl+o',
        'ctrl+w',
        'ctrl+shift+w',
        'ctrl+shift+t',
        'ctrl+shift+a',
        'ctrl+r',
        'ctrl+shift+f',
        'ctrl+m',
        'ctrl+shift+b',
        'ctrl+y',
        'ctrl+b',
        'ctrl+k',
      ]) {
        expect(
          menuShortcutActivator(shortcut),
          isNotNull,
          reason: 'הקיצור $shortcut צריך להיות ניתן להצהרה בתפריט',
        );
      }
    });
  });
}
