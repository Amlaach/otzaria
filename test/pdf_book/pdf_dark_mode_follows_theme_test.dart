import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// היפוך הצבעים של ה-PDF חייב להיגזר מבהירות התמה בפועל: הדגל השמור
/// `isDarkMode` נשאר על ערכו הישן במצב "מערכת", וה-PDF נתקע כהה (issue #1426).
void main() {
  final lines = File(
    'lib/pdf_book/view/pdf_book_screen.dart',
  ).readAsLinesSync();
  final code = lines
      .where((line) => !line.trimLeft().startsWith('//'))
      .toList();

  test('אין צרכן של SettingsState.isDarkMode במסך ה-PDF', () {
    expect(code.join('\n'), isNot(contains('.state.isDarkMode')));
  });

  test('כל היפוך צבעים נגזר מ-Theme.of(context).brightness', () {
    const themeBrightness = 'Theme.of(context).brightness == Brightness.dark';
    var sites = 0;
    for (var i = 0; i < code.length; i++) {
      if (!code[i].contains('BlendMode.difference')) continue;
      sites++;
      final window = code.sublist(i - 10 < 0 ? 0 : i - 10, i + 1).join('\n');
      expect(
        window,
        contains(themeBrightness),
        reason: 'ההיפוך בשורה ${i + 1} אינו נגזר מבהירות התמה',
      );
    }
    expect(sites, 2);
  });
}
