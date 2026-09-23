import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

/// עורך הטקסט צריך שדה שממלא את הגובה וגולל בבקר חיצוני (issue #1470).
void main() {
  Widget host(Widget child) => MaterialApp(
    locale: const Locale('he', 'IL'),
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(body: SizedBox(height: 300, child: child)),
    ),
  );

  testWidgets('expands ממלא את הגובה הזמין (issue #1470)', (tester) async {
    await tester.pumpWidget(
      host(
        const RtlTextField(maxLines: null, expands: true),
      ),
    );

    expect(tester.getSize(find.byType(RtlTextField)).height, 300);
    expect(tester.widget<TextField>(find.byType(TextField)).expands, isTrue);
  });

  testWidgets('scrollController מועבר לשדה הפנימי (issue #1470)', (
    tester,
  ) async {
    final controller = ScrollController();
    final textController = TextEditingController(
      text: List.filled(80, 'שורה').join('\n'),
    );
    addTearDown(controller.dispose);
    addTearDown(textController.dispose);

    await tester.pumpWidget(
      host(
        RtlTextField(
          maxLines: null,
          expands: true,
          scrollController: controller,
          controller: textController,
        ),
      ),
    );

    expect(
      tester.widget<TextField>(find.byType(TextField)).scrollController,
      same(controller),
    );
    expect(controller.hasClients, isTrue);
    expect(controller.position.maxScrollExtent, greaterThan(0));
    final target = controller.position.maxScrollExtent / 2;
    controller.jumpTo(target);
    await tester.pump();
    expect(controller.offset, closeTo(target, 0.01));
  });
}
