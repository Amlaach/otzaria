import 'dart:io';

/// מסתיר מידע אישי בדיווח לפני שהוא יוצא מהמחשב: תיקיית הפרופיל, שם המשתמש
/// במערכת וכתובות מייל. פונקציה טהורה — הסביבה מוזרקת.
class AppReportRedactor {
  AppReportRedactor({required Map<String, String> environment})
    : _profilePatterns = _buildProfilePatterns(environment),
      _userPattern = _buildUserPattern(environment);

  /// לפי משתני הסביבה של התהליך הנוכחי.
  factory AppReportRedactor.fromPlatform() {
    try {
      return AppReportRedactor(environment: Platform.environment);
    } catch (_) {
      return AppReportRedactor(environment: const {});
    }
  }

  static const String profilePlaceholder = '%USERPROFILE%';
  static const String userPlaceholder = '<user>';
  static const String emailPlaceholder = '<email>';
  static const int minUserNameLength = 3;

  static final RegExp _email = RegExp(
    r'[A-Za-z0-9][A-Za-z0-9._%+\-]*@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}',
  );

  final List<RegExp> _profilePatterns;
  final RegExp? _userPattern;

  String redactText(String text) {
    if (text.isEmpty) return text;
    var result = text.replaceAll(_email, emailPlaceholder);
    for (final pattern in _profilePatterns) {
      result = result.replaceAll(pattern, profilePlaceholder);
    }
    final user = _userPattern;
    if (user != null) result = result.replaceAll(user, userPlaceholder);
    return result;
  }

  /// מחיל את ההסתרה על כל מחרוזת במבנה JSON, כולל מפתחות של מפות.
  Object? redactJson(Object? value) {
    if (value is String) return redactText(value);
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          redactText('${entry.key}'): redactJson(entry.value),
      };
    }
    if (value is List) return value.map(redactJson).toList();
    return value;
  }

  /// כל צורות הנתיב: שני סוגי הלוכסנים, וגם `\\` כפי שנכתב בתוך JSON.
  static List<RegExp> _buildProfilePatterns(Map<String, String> env) {
    final variants = <String>{};
    for (final key in const ['USERPROFILE', 'HOME']) {
      var path = env[key]?.trim() ?? '';
      while (path.length > 1 && (path.endsWith('/') || path.endsWith('\\'))) {
        path = path.substring(0, path.length - 1);
      }
      // נתיב קצר מדי (`/`, `C:`) היה מוחק חלקים לא אישיים מכל הדוח.
      if (path.length < 4) continue;
      final segments = path.split(RegExp(r'[\\/]+'));
      variants
        ..add(segments.join('\\'))
        ..add(segments.join('/'))
        ..add(segments.join(r'\\'));
    }
    final sorted = variants.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    return [
      for (final variant in sorted)
        RegExp(
          '${RegExp.escape(variant)}(?![A-Za-z0-9_\\-.])',
          caseSensitive: false,
        ),
    ];
  }

  static RegExp? _buildUserPattern(Map<String, String> env) {
    final names = <String>{
      for (final key in const ['USERNAME', 'USER'])
        if ((env[key]?.trim() ?? '').length >= minUserNameLength)
          env[key]!.trim(),
    };
    if (names.isEmpty) return null;
    final alternatives =
        (names.toList()..sort((a, b) => b.length.compareTo(a.length)))
            .map(RegExp.escape)
            .join('|');
    // `<` / `>`: הסתרה חוזרת לא תהפוך את `<user>` של שם המשתמש User ל-`<<user>>`.
    return RegExp(
      r'(?<![\p{L}\p{N}_<])(?:' + alternatives + r')(?![\p{L}\p{N}_>])',
      caseSensitive: false,
      unicode: true,
    );
  }
}
