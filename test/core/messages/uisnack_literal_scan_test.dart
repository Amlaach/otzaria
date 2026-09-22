import 'dart:io';

import 'package:test/test.dart';

/// כל הודעה ל-UiSnack מגיעה מקטלוג ב-lib/core/messages (issue #1473).
///
/// מחרוזת ישירה באתר הקריאה נשארת מחוץ לכל מנגנון תרגום או איחוד ניסוח.
void main() {
  test('אין מחרוזת קשיחה ב-UiSnack (issue #1473)', () {
    final hits = <String>[];
    final pattern = RegExp(r"""UiSnack\.[a-zA-Z]+\(\s*['"]""");
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      for (final (i, line) in entity.readAsStringSync().split('\n').indexed) {
        if (pattern.hasMatch(line)) {
          hits.add('${entity.path}:${i + 1}: ${line.trim()}');
        }
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
