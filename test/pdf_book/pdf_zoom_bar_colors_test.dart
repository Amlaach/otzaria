import 'dart:io';

import 'package:test/test.dart';

/// סרגל הזום של ה-PDF נגזר מערכת הצבעים (issue #1472).
///
/// הסרגל היה מודע למצב כהה אך לא ל-seed שהמשתמש בחר.
void main() {
  const bar = 'lib/pdf_book/view/pdf_zoom_bar.dart';

  test('אין צבעים קשיחים בסרגל הזום (issue #1472)', () {
    final hits = <String>[];
    final pattern = RegExp(
      r'Colors\.(red|blue|green|orange|purple|yellow|pink|teal|cyan|indigo'
      r'|amber|grey|brown|white|black)[A-Za-z0-9]*\b',
    );
    for (final (i, line) in File(bar).readAsStringSync().split('\n').indexed) {
      if (pattern.hasMatch(line)) hits.add('$bar:${i + 1}: ${line.trim()}');
    }

    expect(
      hits,
      isEmpty,
      reason:
          'צבע קשיח בסרגל הזום — יש לגזור מ-colorScheme או מטוקן '
          'ב-lib/theme/app_surfaces.dart:\n${hits.join('\n')}',
    );
  });
}
