import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/utils/pdf_color_filter.dart';
import 'package:otzaria/theme/app_surfaces.dart';

void main() {
  const paper = Color(0xFFF4EEDF);

  Future<Color> renderedPixel(
    WidgetTester tester, {
    required Color background,
    required Color overlay,
    required Brightness brightness,
  }) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox.square(
            dimension: 24,
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.white,
                brightness == Brightness.dark
                    ? BlendMode.difference
                    : BlendMode.dst,
              ),
              child: Stack(
                alignment: Alignment.topLeft,
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: pdfColorBeforeFilter(background, brightness),
                  ),
                  ColoredBox(
                    color: pdfColorBeforeFilter(overlay, brightness),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    return (await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final offset = (12 * image.width + 12) * 4;
      final color = Color.fromARGB(
        bytes.getUint8(offset + 3),
        bytes.getUint8(offset),
        bytes.getUint8(offset + 1),
        bytes.getUint8(offset + 2),
      );
      image.dispose();
      return color;
    }))!;
  }

  void expectClose(Color actual, Color expected) {
    expect(actual.a, closeTo(expected.a, 0.01));
    expect(actual.r, closeTo(expected.r, 0.01));
    expect(actual.g, closeTo(expected.g, 0.01));
    expect(actual.b, closeTo(expected.b, 0.01));
  }

  test('מצב בהיר משאיר צבע ושקיפות ללא שינוי', () {
    const translucent = Color(0x336B4F2A);
    expect(pdfColorBeforeFilter(translucent, Brightness.light), translucent);
    expect(pdfColorBeforeFilter(paper, Brightness.light), paper);
  });

  test('מצב כהה הופך ערוצים ושומר על שקיפות ההדגשה', () {
    const translucent = Color(0x336B4F2A);
    final inverted = pdfColorBeforeFilter(translucent, Brightness.dark);
    expect(inverted.a, closeTo(translucent.a, 0.001));
    expect(inverted.r, closeTo(1 - translucent.r, 0.001));
    expect(inverted.g, closeTo(1 - translucent.g, 0.001));
    expect(inverted.b, closeTo(1 - translucent.b, 0.001));
  });

  testWidgets('הדגשת קישור נצבעת בפועל לפי ה-seed בשני מצבי התמה', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      for (final seed in [const Color(0xFF6B4F2A), const Color(0xFF2E7D32)]) {
        final scheme = ColorScheme.fromSeed(
          seedColor: seed,
          brightness: brightness,
        );
        final hover = AppSurfaces.pdfLinkHover(scheme);
        final actual = await renderedPixel(
          tester,
          background: paper,
          overlay: hover,
          brightness: brightness,
        );
        expectClose(actual, Color.alphaBlend(hover, paper));
      }
    }
  });

  testWidgets('מסלול מד הטעינה נשאר אטום ובצבע התמה בשני המצבים', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      final scheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFF6B4F2A),
        brightness: brightness,
      );
      final track = scheme.surfaceContainerHighest;
      final actual = await renderedPixel(
        tester,
        background: paper,
        overlay: track,
        brightness: brightness,
      );
      expectClose(actual, track);
    }
  });
}
