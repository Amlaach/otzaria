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

    test('מקש בעל שם מהמפה המרכזית', () {
      final activator = menuShortcutActivator('ctrl+comma');
      expect(activator!.trigger, LogicalKeyboardKey.comma);
      expect(activator.meta, isTrue);
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

    test('כל ברירות המחדל של האפליקציה ניתנות לייצוג או ל-null בלבד', () {
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
        'ctrl+comma',
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
