import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/navigation/otzar_utils.dart';

void main() {
  group('macBookUri', () {
    test('הכתובת בפורמט שמטפל הפרוטוקול של אוצר החכמה מקבל', () {
      expect(
        OtzarUtils.macBookUri(151130, tabId: 42),
        'OtzarBook://book/151130/p/1/t/42/fs/0/start/0/end/0/c',
      );
    });

    test('בלי רווח — כתובת שעוברת ב-LaunchServices', () {
      // הרווח שלפני `/c` במסלול Windows תקין שם כי ה-URI הוא ארגומנט תהליך;
      // בכתובת הוא היה נחתך.
      expect(OtzarUtils.macBookUri(1, tabId: 0), isNot(contains(' ')));
    });

    test('מזהה הכרטיסייה מוגרל כשאינו מועבר', () {
      final first = OtzarUtils.macBookUri(7);
      final second = OtzarUtils.macBookUri(7);
      expect(first, startsWith('OtzarBook://book/7/p/1/t/'));
      expect(second, startsWith('OtzarBook://book/7/p/1/t/'));
      expect(first, endsWith('/fs/0/start/0/end/0/c'));
    });
  });

  group('checkBookExistence', () {
    test('מחוץ ל-Windows ולמק אין סריקה — מחזיר false', () async {
      if (Platform.isWindows || Platform.isMacOS) return;
      expect(await OtzarUtils.checkBookExistence(1), isFalse);
    });

    test('במק ספר שאינו על שום כונן מעוגן מחזיר false', () async {
      if (!Platform.isMacOS) return;
      // מזהה שלא סביר שקיים בכונן כלשהו.
      expect(await OtzarUtils.checkBookExistence(999999999), isFalse);
    });
  });
}
