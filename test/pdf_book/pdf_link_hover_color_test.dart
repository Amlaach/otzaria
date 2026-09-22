import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_surfaces.dart';

/// צבעי מסך ה-PDF נגזרים מערכת הצבעים, ולא מצבע קשיח (issue #1469).
void main() {
  ColorScheme schemeOf(Color seed, Brightness brightness) =>
      ColorScheme.fromSeed(seedColor: seed, brightness: brightness);

  test('הדגשת הקישור נגזרת מ-primary ולא מכחול קבוע (issue #1469)', () {
    final brown = schemeOf(const Color(0xFF6B4F2A), Brightness.light);
    final green = schemeOf(const Color(0xFF2E7D32), Brightness.light);

    expect(
      AppSurfaces.pdfLinkHover(brown),
      isNot(AppSurfaces.pdfLinkHover(green)),
      reason: 'שני צבעי seed שונים חייבים לתת הדגשה שונה',
    );
    expect(AppSurfaces.pdfLinkHover(brown).a, closeTo(0.2, 0.001));
  });

  test('ההדגשה עוקבת אחרי primary בשני מצבי התמה (issue #1469)', () {
    for (final brightness in Brightness.values) {
      final cs = schemeOf(const Color(0xFF6B4F2A), brightness);
      final hover = AppSurfaces.pdfLinkHover(cs);
      expect(hover.r, closeTo(cs.primary.r, 0.001));
      expect(hover.g, closeTo(cs.primary.g, 0.001));
      expect(hover.b, closeTo(cs.primary.b, 0.001));
    }
  });
}
