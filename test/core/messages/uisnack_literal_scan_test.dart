import 'dart:io';

import 'package:test/test.dart';

final _hardcodedUiSnackLiteral = RegExp(r"""UiSnack\.[a-zA-Z]+\(\s*['"]""");

/// כל הודעה ל-UiSnack מגיעה מקטלוג ב-lib/core/messages (issue #1473).
///
/// מחרוזת ישירה באתר הקריאה נשארת מחוץ לכל מנגנון תרגום או איחוד ניסוח.
void main() {
  test('הסריקה מזהה מחרוזת בקריאת UiSnack רב-שורתית', () {
    expect(
      _hardcodedUiSnackLiteral.hasMatch("UiSnack.showError(\n  'הודעה'\n)"),
      isTrue,
    );
  });

  test('אין מחרוזת קשיחה ב-UiSnack (issue #1473)', () {
    final hits = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final match in _hardcodedUiSnackLiteral.allMatches(source)) {
        final line =
            '\n'.allMatches(source.substring(0, match.start)).length + 1;
        hits.add('${entity.path}:$line');
      }
    }

    expect(
      hits,
      isEmpty,
      reason:
          'הודעה ל-UiSnack חייבת לבוא מקטלוג ב-lib/core/messages/:\n'
          '${hits.join('\n')}',
    );
  });
}
