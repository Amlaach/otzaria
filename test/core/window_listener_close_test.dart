import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/pre_close_registry.dart';
import 'package:otzaria/core/window_listener.dart';

/// רצף הסגירה פוצל לשלושה: מה שקודם ל-flush ומה שאחריו הם פר-תהליך,
/// וה-flush עצמו הוא הצעד הפר-חלוני היחיד. הסכנה בפיצול היא שכשל ה-flush
/// ייבלע בתוך החלק הפר-חלוני ולא יגיע לדיווח — הוא האות היחיד לכך שכתיבות
/// תלויות לא נשמרו.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('flush מוצלח מחזיר null, וכל ה-callbacks רצו', () {
    var ran = 0;
    Future<void> first() async => ran++;
    Future<void> second() async => ran++;

    PreCloseRegistry.register(first);
    PreCloseRegistry.register(second);
    addTearDown(() {
      PreCloseRegistry.unregister(first);
      PreCloseRegistry.unregister(second);
    });

    return AppWindowListener().closeWindowScopedForTest().then((failure) {
      expect(failure, isNull);
      expect(ran, 2);
    });
  });

  test('כשל flush מוחזר לקורא ואינו נבלע', () async {
    Future<void> failing() async => throw StateError('הכתיבה נכשלה');

    PreCloseRegistry.register(failing);
    addTearDown(() => PreCloseRegistry.unregister(failing));

    final failure = await AppWindowListener().closeWindowScopedForTest();

    // בלי ההחזרה, `_shutdownProcessAfterFlush` לא היה מדווח ל-Sentry
    // והכשל היה נעלם בשקט.
    expect(failure, isA<PreCloseFlushFailure>());
    expect((failure as PreCloseFlushFailure).errors, hasLength(1));
    expect(failure.errors.single, contains('הכתיבה נכשלה'));
  });

  test('callback שנכשל אינו מונע מהאחרים לרוץ', () async {
    var lateRan = false;
    Future<void> failing() async => throw StateError('נכשל');
    Future<void> later() async => lateRan = true;

    PreCloseRegistry.register(failing);
    PreCloseRegistry.register(later);
    addTearDown(() {
      PreCloseRegistry.unregister(failing);
      PreCloseRegistry.unregister(later);
    });

    final failure = await AppWindowListener().closeWindowScopedForTest();

    expect(lateRan, isTrue);
    expect(failure, isA<PreCloseFlushFailure>());
  });
}
