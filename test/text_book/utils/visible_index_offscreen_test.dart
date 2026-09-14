import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/utils/visible_index.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// issue #1358 — Alt+חץ למעלה קפץ לתחילת הספר ונתקע: ScrollablePositionedList
/// מדווח גם פריטים שנגללו מעל החלון (itemTrailingEdge <= 0, מתוך ה-cache),
/// ו-topmostVisibleIndex בחר את האינדקס הנמוך שבהם במקום את הפריט הנראה.
ItemPosition _pos(int index, double leading, double trailing) => ItemPosition(
  index: index,
  itemLeadingEdge: leading,
  itemTrailingEdge: trailing,
);

void main() {
  group('topmostVisibleIndex מתעלם מפריטים מעל החלון (issue #1358)', () {
    test('פריט 0 שנגלל כולו למעלה אינו "העליון הנראה"', () {
      final positions = [
        _pos(0, -2.0, -1.2), // כותרת שנגללה למעלה ועדיין ב-cache
        _pos(37, -0.1, 0.4), // חלקו העליון מעל הקצה — הנראה העליון
        _pos(38, 0.4, 0.9),
      ];
      expect(topmostVisibleIndex(positions), 37);
    });

    test('כשאף פריט אינו נראה — נופלים לאינדקס המינימלי', () {
      final positions = [_pos(5, -1.0, -0.5), _pos(6, -0.5, -0.1)];
      expect(topmostVisibleIndex(positions), 5);
    });
  });
}
