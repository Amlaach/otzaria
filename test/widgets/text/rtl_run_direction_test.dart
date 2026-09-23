import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/text/rtl_selection_shortcuts.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

/// החיצים מתהפכים רק בקטע שנכתב מימין לשמאל (issue #1470).
void main() {
  group('isRtlRunAt', () {
    test('בתוך מילה עברית — RTL', () {
      expect(isRtlRunAt('שלום עולם', 3), isTrue);
    });

    test('בתוך מילה אנגלית בתוך טקסט עברי — LTR', () {
      expect(isRtlRunAt('שלום hello עולם', 8), isFalse);
    });

    test('בתוך תג HTML — LTR', () {
      expect(isRtlRunAt('בראשית <big>ברא</big>', 11), isFalse);
    });

    test('ספרה בין אותיות עבריות — RTL (ספרה אינה תו חזק)', () {
      expect(isRtlRunAt('פרק 12 פסוק', 5), isTrue);
    });

    test('מחרוזת ריקה או בלי תו חזק — ברירת המחדל RTL', () {
      expect(isRtlRunAt('', 0), isTrue);
      expect(isRtlRunAt('123 ...', 2), isTrue);
    });
  });

  group('תזוזת הסמן בפועל', () {
    late TextEditingController controller;

    Future<void> pump(WidgetTester tester, String text, int offset) async {
      controller = TextEditingController(text: text);
      controller.selection = TextSelection.collapsed(offset: offset);
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
    }

    testWidgets('חץ ימינה בעברית מזיז אחורה לוגית (issue #1470)', (
      tester,
    ) async {
      await pump(tester, 'שלום עולם', 3);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(controller.selection.extentOffset, 2);
    });

    testWidgets('חץ ימינה בתוך תג מזיז קדימה לוגית (issue #1470)', (
      tester,
    ) async {
      await pump(tester, 'בראשית <big>ברא', 10);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(controller.selection.extentOffset, 11);
    });
  });
}
