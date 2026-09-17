// issue #1399: ל-ActionButton יש tooltip משלו כדי שאפשר יהיה להציבו בתוך עוגן
// overlay אחר (MenuAnchor) — עטיפה חיצונית ב-Tooltip הייתה ממזגת את עוגן הבלון
// לצומת של עוגן התפריט, והבלון היה נשלח למערכת ההפעלה בלי אב.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';

import '../../helpers/semantics_update_recorder.dart';

void main() {
  SemanticsRecordingBinding.ensure();
  final recorder = SemanticsRecordingBinding.recorder;

  Widget host(Widget Function(MenuController controller) anchorChild) =>
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MenuAnchor(
              menuChildren: [
                MenuItemButton(onPressed: () {}, child: const Text('פריט')),
              ],
              builder: (context, controller, _) => anchorChild(controller),
            ),
          ),
        ),
      );

  Future<void> hoverAndOpen(WidgetTester tester, String tooltip) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('פתח')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text(tooltip), findsOneWidget, reason: 'הבלון נפתח');
    await tester.tap(find.text('פתח'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('פריט'), findsOneWidget, reason: 'התפריט נפתח');
  }

  testWidgets(
    'ActionButton עם tooltip בתוך MenuAnchor: הבלון והתפריט נשלחים עם אב '
    '(issue #1399)',
    (tester) async {
      recorder.reset();
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          (controller) => ActionButton.ghost(
            text: 'פתח',
            tooltip: 'הסבר',
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await hoverAndOpen(tester, 'הסבר');

      expect(recorder.violations, isEmpty);
      // ל-tooltip צומת סמנטיקה משלו, נפרד מצומת הכפתור ומצומת עוגן התפריט.
      final tooltipNode = tester.getSemantics(find.byTooltip('הסבר'));
      expect(tooltipNode, isSemantics(tooltip: 'הסבר'));
      expect(
        tooltipNode.traversalParentIdentifier,
        isNotNull,
        reason: 'עוגן הבלון שמור על הצומת של ה-tooltip',
      );
      handle.dispose();
    },
  );

  testWidgets(
    'ActionButton בלי tooltip אינו מוסיף צומת סמנטיקה (issue #1399)',
    (tester) async {
      recorder.reset();
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ActionButton.ghost(text: 'פתח', onPressed: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Tooltip), findsNothing);
      expect(
        tester.getSemantics(find.text('פתח')),
        isSemantics(isButton: true, label: 'פתח'),
      );
      expect(recorder.violations, isEmpty);
      handle.dispose();
    },
  );
}
