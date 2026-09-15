import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';

void main() {
  // issue #1362: גובה שורה 1.0 קיצר את הסמן ואת הבחירה לגובה הגופן בלבד.
  testWidgets('הסמן בשדה החיפוש בגובה השורה הטבעי של הגופן', (tester) async {
    final controller = TextEditingController(text: 'שוע א');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: OtzariaSearchField(
                controller: controller,
                hintText: 'חיפוש',
              ),
            ),
          ),
        ),
      ),
    );

    final editable = tester.widget<EditableText>(find.byType(EditableText));
    final render = tester.renderObject<RenderEditable>(
      find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Editable'),
    );
    expect(
      render.preferredLineHeight,
      greaterThan(editable.style.fontSize! * 1.2),
    );
  });
}
