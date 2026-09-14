import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/l10n/settings_catalogs.g.dart';

/// issue #1189 — "ספרייה" בתפריט הראשי אבל "ספריה" בכותרת החלון ובהגדרות.
/// כל מפתח תרגום (= הטקסט העברי שמוצג) חייב להשתמש בכתיב התקני "ספרייה".
void main() {
  test('אין מחרוזות ממשק עם הכתיב "ספריה" (issue #1189)', () {
    final singleYod = kSettingsCatalogs['en']!.keys
        .where((key) => key.contains('ספריה'))
        .toList();
    expect(singleYod, isEmpty, reason: 'מפתחות בכתיב חסר: $singleYod');
  });
}
