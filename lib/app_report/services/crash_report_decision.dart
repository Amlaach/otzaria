import 'package:otzaria/app_report/services/unclean_exit_detector.dart';

/// מצב הדיווח אחרי קריסה, כפי שהוא שמור בהגדרות.
enum AppCrashReportMode {
  ask('ask'),
  always('always'),
  never('never');

  const AppCrashReportMode(this.wireName);

  final String wireName;

  static AppCrashReportMode parse(Object? raw) =>
      AppCrashReportMode.values.firstWhere(
        (mode) => mode.wireName == raw,
        orElse: () => AppCrashReportMode.ask,
      );
}

/// הפעולה שההפעלה הנוכחית תבצע בעקבות קריסה של ההפעלה הקודמת.
enum CrashReportAction { none, prompt, sendAutomatically }

/// ההכרעה מה לעשות עם קריסה שזוהתה: מצב ההגדרה × המועמד × המגבלה.
abstract class CrashReportDecision {
  static const String fallbackTitle = 'סגירה לא צפויה';

  static CrashReportAction decide({
    required AppCrashReportMode mode,
    required CrashCandidate? candidate,
    required bool throttleAllows,
  }) {
    if (candidate == null || mode == AppCrashReportMode.never) {
      return CrashReportAction.none;
    }
    if (mode == AppCrashReportMode.always) {
      return throttleAllows
          ? CrashReportAction.sendAutomatically
          : CrashReportAction.none;
    }
    return CrashReportAction.prompt;
  }

  /// כותרת הדיווח: סוג החריגה מהחתימה, ואם אין — נוסח כללי.
  static String titleFor(CrashCandidate candidate) {
    final exceptionType = candidate.signature?.exceptionType.trim() ?? '';
    return exceptionType.isEmpty ? fallbackTitle : exceptionType;
  }

  /// מפתח המגבלה. קריסה בלי חתימה מקובצת תחת הכותרת הכללית.
  static String throttleKeyFor(CrashCandidate candidate) {
    final signature = candidate.signature;
    if (signature == null || signature.exceptionType.trim().isEmpty) {
      return fallbackTitle;
    }
    return signature.hash;
  }
}
