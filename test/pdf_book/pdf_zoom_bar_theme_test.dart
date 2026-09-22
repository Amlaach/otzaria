import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/view/pdf_zoom_bar.dart';
import 'package:otzaria/theme/app_surfaces.dart';

/// צבעי סרגל הזום עוקבים אחרי ה-seed ואחרי מצב התמה (issue #1472).
void main() {
  Widget host(Color seed, Brightness brightness) => MaterialApp(
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: brightness,
      ),
    ),
    home: Scaffold(
      body: Center(
        child: PdfZoomBar(
          currentZoom: 1.0,
          onZoomIn: () {},
          onZoomOut: () {},
          onResetZoom: () {},
        ),
      ),
    ),
  );

  Color barColor(WidgetTester tester) => tester
      .widget<Material>(
        find
            .descendant(
              of: find.byType(PdfZoomBar),
              matching: find.byType(Material),
            )
            .first,
      )
      .color!;

  testWidgets('רקע הסרגל נגזר מה-seed ולא מאפור קבוע (issue #1472)', (
    tester,
  ) async {
    await tester.pumpWidget(host(const Color(0xFF6B4F2A), Brightness.dark));
    final brown = barColor(tester);

    // בנייה מאפס: החלפת theme בלבד מחזיקה את אותו Element ואת צבעו הישן.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(host(const Color(0xFF2E7D32), Brightness.dark));
    final green = barColor(tester);

    expect(
      brown,
      isNot(green),
      reason: 'שני צבעי seed שונים חייבים לתת רקע שונה',
    );
  });

  testWidgets('הרקע תואם ל-AppSurfaces.card בשני מצבי התמה (issue #1472)', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(host(const Color(0xFF6B4F2A), brightness));
      final context = tester.element(find.byType(PdfZoomBar));
      expect(barColor(tester), AppSurfaces.card(context));
    }
  });

  testWidgets('המפרידים נגזרים מ-outlineVariant (issue #1472)', (
    tester,
  ) async {
    await tester.pumpWidget(host(const Color(0xFF6B4F2A), Brightness.dark));
    final scheme = Theme.of(
      tester.element(find.byType(PdfZoomBar)),
    ).colorScheme;

    final dividers = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) => c.color != null)
        .map((c) => c.color)
        .toSet();

    expect(dividers, isNotEmpty);
    expect(dividers, everyElement(scheme.outlineVariant));
  });
}
