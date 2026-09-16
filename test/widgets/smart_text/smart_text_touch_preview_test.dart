import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/utils/link_preview_utils.dart';
import 'package:otzaria/text_book/view/widgets/continuous_reading_paragraph.dart';
import 'package:otzaria/widgets/misc/inline_link_targets.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

// issue #1320: במגע אין ריחוף, ולכן הקשה על קישור מוטמע פותחת את התצוגה
// המקדימה במקום לנווט. בעכבר הלחיצה ממשיכה לפתוח את הספר.
void main() {
  const url = 'otzaria://inline-link?path=ברכות&index=3';
  const settings = RenderSettings(fontSize: 24);

  /// מקיש במרכז הגליפים של [finder] — מרכז הפסקה עצמה עלול ליפול מחוץ לטקסט.
  Future<void> tapText(
    WidgetTester tester,
    Finder finder,
    PointerDeviceKind kind,
  ) async {
    final paragraph = tester.renderObject<RenderParagraph>(finder);
    final length = paragraph.text.toPlainText().length;
    final box = paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: length),
        )
        .first;
    final gesture = await tester.startGesture(
      paragraph.localToGlobal(box.toRect().center),
      kind: kind,
    );
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 500));
  }

  group('SmartTextWidget', () {
    Future<({List<String> previews, List<Object> opened})> pump(
      WidgetTester tester,
      String href,
    ) async {
      final previews = <String>[];
      final opened = <Object>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: SmartTextWidget(
                  key: const Key('text'),
                  text: '<a href="$href">ברכות ג ברכות ג</a>',
                  settings: settings,
                  onOpenBook: opened.add,
                  onNoteTap: (line) => opened.add(line),
                  onAnchorHover: (_, _) {},
                  onTouchPreview: (url, _) => previews.add(url),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (previews: previews, opened: opened);
    }

    testWidgets('הקשת מגע על קישור מוטמע פותחת תצוגה מקדימה', (tester) async {
      final result = await pump(tester, url);
      await tapText(
        tester,
        find.byType(RichText).first,
        PointerDeviceKind.touch,
      );
      expect(result.previews, [url]);
      expect(result.opened, isEmpty);
    });

    testWidgets('לחיצת עכבר אינה פותחת תצוגה מקדימה', (tester) async {
      final result = await pump(tester, url);
      await tapText(
        tester,
        find.byType(RichText).first,
        PointerDeviceKind.mouse,
      );
      expect(result.previews, isEmpty);
    });

    testWidgets('הערה אישית במגע נשארת בהקשה שלה', (tester) async {
      final result = await pump(tester, 'otzaria://note?line=4');
      await tapText(
        tester,
        find.byType(RichText).first,
        PointerDeviceKind.touch,
      );
      expect(result.previews, isEmpty);
      expect(result.opened, [4]);
    });
  });

  testWidgets('קריאה רציפה: מיקום הקשת המגע זמין ב-onTapUrl', (tester) async {
    final positions = <Offset?>[];
    final spans = buildInlineHtmlSpans(
      '<a href="$url">ברכות ג ברכות ג</a>',
      const TextStyle(fontSize: 24),
      onTapUrl: (_) async {
        positions.add(touchLinkTapPosition());
        return true;
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RichText(
              key: const Key('text'),
              text: TextSpan(children: spans),
            ),
          ),
        ),
      ),
    );
    final finder = find.byKey(const Key('text'));
    await tapText(tester, finder, PointerDeviceKind.touch);
    await tapText(tester, finder, PointerDeviceKind.mouse);
    expect(positions, [isNotNull, isNull]);
  });

  test('isTouchPreviewUrl — רק קישורים שאין להם פעולת הקשה משלהם', () {
    expect(isTouchPreviewUrl(url), isTrue);
    expect(isTouchPreviewUrl('otzaria://book-note?id=1'), isTrue);
    expect(isTouchPreviewUrl('otzaria://note-marker?line=2'), isTrue);
    expect(isTouchPreviewUrl('otzaria://note?line=2'), isFalse);
    expect(isTouchPreviewUrl('otzaria://anchor?ref=3_0'), isFalse);
    expect(isTouchPreviewUrl('book://ברכות'), isFalse);
  });
}
