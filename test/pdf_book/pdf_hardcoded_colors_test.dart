import 'dart:io';

import 'package:test/test.dart';

/// צבעי הזהות במסך ה-PDF נגזרים מערכת הצבעים (issue #1469). white/black
/// אינם ברשימה — הם אופרנד של BlendMode.difference ושל צל העמוד.
void main() {
  const screen = 'lib/pdf_book/view/pdf_book_screen.dart';

  test('אין צבעים קשיחים במסך ה-PDF (issue #1469)', () {
    final source = File(screen).readAsStringSync();
    final hits = <String>[];
    final pattern = RegExp(
      r'Colors\.(red|blue|green|orange|purple|yellow|pink|teal|cyan|indigo|amber|grey|brown)[A-Za-z]*\b',
    );
    for (final (i, line) in source.split('\n').indexed) {
      if (pattern.hasMatch(line)) hits.add('$screen:${i + 1}: ${line.trim()}');
    }

    expect(
      hits,
      isEmpty,
      reason:
          'צבע קשיח בקובץ פיצ׳ר — יש לגזור מ-colorScheme או מטוקן '
          'ב-lib/theme/app_surfaces.dart:\n${hits.join('\n')}',
    );
  });
}
