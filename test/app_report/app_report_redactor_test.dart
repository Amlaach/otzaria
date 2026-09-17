import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/repository/app_report_redactor.dart';

void main() {
  final redactor = AppReportRedactor(
    environment: const {
      'USERPROFILE': r'C:\Users\Moshe',
      'USERNAME': 'Moshe',
    },
  );

  group('AppReportRedactor', () {
    test('מחליף את תיקיית הפרופיל בכל צורות הלוכסן ובלי תלות ברישיות', () {
      expect(
        redactor.redactText(r'C:\Users\Moshe\AppData\Roaming\otzaria'),
        r'%USERPROFILE%\AppData\Roaming\otzaria',
      );
      expect(
        redactor.redactText('file:///c:/users/moshe/x.dart'),
        'file:///%USERPROFILE%/x.dart',
      );
      expect(
        redactor.redactText(r'{"path":"C:\\Users\\Moshe\\books"}'),
        r'{"path":"%USERPROFILE%\\books"}',
      );
    });

    test('אינו נוגע בפרופיל אחר שמתחיל באותן אותיות', () {
      expect(
        redactor.redactText(r'C:\Users\Moshe2\x'),
        r'C:\Users\Moshe2\x',
      );
    });

    test('שם המשתמש מוחלף רק כמילה שלמה', () {
      expect(
        redactor.redactText('owner moshe, MosheBooks, Moshe_1'),
        'owner <user>, MosheBooks, Moshe_1',
      );
    });

    test('הסתרה חוזרת אינה משנה טקסט מוסתר (שם המשתמש User)', () {
      final user = AppReportRedactor(
        environment: const {
          'USERPROFILE': r'C:\Users\User',
          'USERNAME': 'User',
        },
      );
      final once = user.redactText(r'user C:\Users\User\x a@b.com');
      expect(once, r'<user> %USERPROFILE%\x <email>');
      expect(user.redactText(once), once);
    });

    test('שם משתמש קצר משלוש אותיות אינו מוחלף', () {
      final short = AppReportRedactor(environment: const {'USERNAME': 'ab'});
      expect(short.redactText('ab cd'), 'ab cd');
    });

    test('מסתיר כתובות מייל', () {
      expect(
        redactor.redactText('contact a.b+c@mail.example.co.il now'),
        'contact <email> now',
      );
    });

    test('עובד רקורסיבית על JSON, כולל מפתחות', () {
      final result = redactor.redactJson({
        r'C:\Users\Moshe\books': [
          'x@y.com',
          {'n': 5, 'user': 'Moshe'},
        ],
      });
      expect(result, {
        r'%USERPROFILE%\books': [
          '<email>',
          {'n': 5, 'user': '<user>'},
        ],
      });
    });

    test('HOME בלינוקס ונתיב קצר מדי מדולג', () {
      final linux = AppReportRedactor(
        environment: const {'HOME': '/home/dani', 'USER': 'dani'},
      );
      expect(linux.redactText('/home/dani/.local'), '%USERPROFILE%/.local');
      final root = AppReportRedactor(environment: const {'HOME': '/'});
      expect(root.redactText('/usr/lib'), '/usr/lib');
    });
  });
}
