import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/text/rtl_selection_shortcuts.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

void main() {
  Future<TextEditingController> focusedField(
    WidgetTester tester,
    String value,
    int offset,
  ) async {
    final controller = TextEditingController(text: value);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: RtlTextField(controller: controller)),
        ),
      ),
    );
    await tester.tap(find.byType(RtlTextField));
    await tester.pump();
    controller.selection = TextSelection.collapsed(offset: offset);
    await tester.pump();
    return controller;
  }

  for (final (name, value, offset, key, expected)
      in <(String, String, int, LogicalKeyboardKey, int)>[
        ('עברית: ימינה', 'שלום עולם', 3, LogicalKeyboardKey.arrowRight, 2),
        ('עברית: שמאלה', 'שלום עולם', 3, LogicalKeyboardKey.arrowLeft, 4),
        (
          'אנגלית: ימינה',
          'שלום hello עולם',
          7,
          LogicalKeyboardKey.arrowRight,
          8,
        ),
        ('תג: ימינה', 'בראשית <big>ברא', 10, LogicalKeyboardKey.arrowRight, 11),
        (
          'תחילת תג: ימינה',
          'בראשית <big>ברא',
          8,
          LogicalKeyboardKey.arrowRight,
          9,
        ),
        ('מספר: ימינה', 'פרק 12 פסוק', 5, LogicalKeyboardKey.arrowRight, 6),
        ('מספר: שמאלה', 'פרק 12 פסוק', 5, LogicalKeyboardKey.arrowLeft, 4),
        (
          'תחילת מספר: ימינה',
          'פרק 12 פסוק',
          4,
          LogicalKeyboardKey.arrowRight,
          5,
        ),
        ('מספר בתחילת השדה', '123 אב', 1, LogicalKeyboardKey.arrowRight, 2),
        (
          'מספר עם פסיק',
          'פרק 12,345 פסוק',
          7,
          LogicalKeyboardKey.arrowRight,
          8,
        ),
        (
          'שעה: אחרי הנקודתיים',
          'פרק 12:34 פסוק',
          7,
          LogicalKeyboardKey.arrowRight,
          8,
        ),
        (
          'קירילית: ימינה',
          'שלום мир עולם',
          6,
          LogicalKeyboardKey.arrowRight,
          7,
        ),
      ]) {
    testWidgets(name, (tester) async {
      final controller = await focusedField(tester, value, offset);
      await tester.sendKeyEvent(key);
      await tester.pump();
      expect(controller.selection.extentOffset, expected);
    });
  }

  testWidgets('Shift+ימינה בתוך מספר מרחיב בחירה לכיוון הנראה', (tester) async {
    final controller = await focusedField(tester, 'פרק 12 פסוק', 5);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(
      controller.selection,
      const TextSelection(baseOffset: 5, extentOffset: 6),
    );
  });

  testWidgets('Shift+שמאלה בתוך מספר מרחיב בחירה לכיוון הנראה', (tester) async {
    final controller = await focusedField(tester, 'פרק 12 פסוק', 5);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(
      controller.selection,
      const TextSelection(baseOffset: 5, extentOffset: 4),
    );
  });

  testWidgets('ניווט מילה בתוך מספר פונה לכיוון הנראה', (tester) async {
    final controller = await focusedField(tester, 'פרק 12 פסוק', 5);
    final modifier = usesAltForWordNavigation()
        ? LogicalKeyboardKey.altLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump();
    expect(controller.selection.extentOffset, greaterThan(5));
  });

  testWidgets('ניווט בתוך רצף ספרות ארוך', (tester) async {
    final controller = await focusedField(
      tester,
      'אב ${'1' * 20000} גד',
      10000,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(controller.selection.extentOffset, 10001);
  });
}
