import 'dart:io';

import 'package:test/test.dart';

/// שדות הקלט ב-lib עוברים דרך RtlTextField בלבד (issue #1470).
///
/// `TextField` גולמי שובר את ניווט החיצים והבחירה בעברית ב-Desktop.
void main() {
  /// העטיפה עצמה בונה בתוכה `TextField` — זו כל מטרתה.
  const wrapper = 'lib/widgets/text/rtl_text_field.dart';

  test('אין TextField גולמי ב-lib (issue #1470)', () {
    final hits = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path == wrapper) continue;
      for (final (i, line) in entity.readAsStringSync().split('\n').indexed) {
        if (!line.contains('TextField(')) continue;
        if (line.contains('RtlTextField(')) continue;
        hits.add('${entity.path}:${i + 1}: ${line.trim()}');
      }
    }

    expect(
      hits,
      isEmpty,
      reason:
          'TextField גולמי שובר RTL — יש להשתמש ב-RtlTextField:\n'
          '${hits.join('\n')}',
    );
  });
}
