import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/lists/scroll_position_reanchor.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// רשימה שגובה הפריטים בה תלוי ברוחב — מדמה שפיכה מחדש של טקסט שנשבר
/// לשורות נוספות כשהעמודה מצטמצמת.
Widget _buildList({
  required double width,
  required ItemScrollController controller,
  required ItemPositionsListener listener,
  required bool enabled,
}) {
  return MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Center(
        child: SizedBox(
          width: width,
          height: 400,
          child: ScrollPositionReanchor(
            enabled: enabled,
            scrollController: controller,
            positionsListener: listener,
            child: ScrollablePositionedList.builder(
              itemScrollController: controller,
              itemPositionsListener: listener,
              itemCount: 200,
              itemBuilder: (context, index) =>
                  SizedBox(height: 30 * (600 / width), child: Text('$index')),
            ),
          ),
        ),
      ),
    ),
  );
}

int _topIndex(ItemPositionsListener listener) =>
    reanchorTargetPosition(listener.itemPositions.value)!.index;

Future<int> _scrollAndResize(
  WidgetTester tester, {
  required bool enabled,
}) async {
  final controller = ItemScrollController();
  final listener = ItemPositionsListener.create();

  await tester.pumpWidget(
    _buildList(
      width: 600,
      controller: controller,
      listener: listener,
      enabled: enabled,
    ),
  );
  await tester.pumpAndSettle();
  await tester.drag(
    find.byType(ScrollablePositionedList),
    const Offset(0, -1500),
  );
  await tester.pumpAndSettle();
  // הטיימר שממתין לרגיעת הגלילה אינו מתזמן פריימים, ולכן pumpAndSettle לבדו
  // לא מקדם אליו את השעון.
  await tester.pump(ScrollPositionReanchor.idleDelay);
  await tester.pumpAndSettle();

  final before = _topIndex(listener);
  expect(before, greaterThan(20), reason: 'הגלילה לא הזיזה מספיק');

  await tester.pumpWidget(
    _buildList(
      width: 300,
      controller: controller,
      listener: listener,
      enabled: enabled,
    ),
  );
  await tester.pumpAndSettle();

  return _topIndex(listener) - before;
}

void main() {
  group('ScrollPositionReanchor', () {
    testWidgets('המיקום נשמר כשרוחב התצוגה משתנה', (tester) async {
      expect(await _scrollAndResize(tester, enabled: true), 0);
    });

    testWidgets('בלי עיגון מחדש ההיסט בפיקסלים סוחף את המיקום', (tester) async {
      expect(await _scrollAndResize(tester, enabled: false), isNot(0));
    });

    testWidgets('קפיצה לאינדקס אחרי שינוי הרוחב מדויקת', (tester) async {
      final controller = ItemScrollController();
      final listener = ItemPositionsListener.create();
      await tester.pumpWidget(
        _buildList(
          width: 600,
          controller: controller,
          listener: listener,
          enabled: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(ScrollablePositionedList),
        const Offset(0, -1500),
      );
      await tester.pumpAndSettle();
      await tester.pump(ScrollPositionReanchor.idleDelay);
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        _buildList(
          width: 300,
          controller: controller,
          listener: listener,
          enabled: true,
        ),
      );
      await tester.pumpAndSettle();

      controller.jumpTo(index: 120, alignment: 0);
      await tester.pumpAndSettle();

      expect(_topIndex(listener), 120);
    });
  });
}
