import 'dart:io';

import 'package:path/path.dart' as p;

/// תקרת הרשומות שמוחזרות מ-`fs.listUserFolder` בקריאה אחת. תיקייה גדולה
/// ממנה מוחזרת חתוכה עם `truncated: true` — העץ בתוסף טוען רמה אחת בכל פעם,
/// ואלפי שורות ברמה אחת אינן ניתנות לעיון ממילא.
const int kUserFolderMaxEntries = 2000;

/// סיומת קובצי ה-staging של הכתיבה האטומית באדפטר. קובץ כזה הוא שארית של
/// שמירה שלא הסתיימה, ואינו מסמך של המשתמש.
const String kUserFolderStagingExtension = '.otztmp';

/// רשומה אחת בתיקייה, לפני ה-stat.
typedef _Candidate = ({String name, String target, bool isDir});

/// תוצאת מנייה של תיקייה מאושרת.
typedef UserFolderListing = ({
  List<Map<String, dynamic>> entries,
  bool truncated,
});

/// שמות שאינם מוצגים לתוסף: קבצים נסתרים בסגנון Unix (`.git`, `.DS_Store`),
/// קובצי הנעילה של Office (`~$מסמך.docx`) ושאריות ה-staging של האדפטר.
bool isHiddenUserFolderEntry(String name) =>
    name.startsWith('.') ||
    name.startsWith(r'~$') ||
    name.toLowerCase().endsWith(kUserFolderStagingExtension);

/// מנרמל רשימת סיומות מהתוסף: אותיות קטנות, בלי נקודה מובילה, בלי ריקות.
/// `null` כשאין סינון.
Set<String>? normalizeUserFolderExtensions(List<String>? raw) {
  if (raw == null) return null;
  return {
    for (final ext in raw)
      if (ext.trim().replaceFirst(RegExp(r'^\.+'), '') case final e
          when e.isNotEmpty)
        e.toLowerCase(),
  };
}

bool _matchesExtension(String name, Set<String> extensions) {
  final lower = name.toLowerCase();
  // `endsWith` ולא `p.extension`: כך גם סיומת כפולה (`tar.gz`) מסוננת נכון.
  return extensions.any((ext) => lower.endsWith('.$ext'));
}

/// מפרק נתיב יחסי שהתוסף שלח (מופרד ב-`/`) לרכיבים. `''` הוא השורש.
///
/// מחזיר `null` לנתיב שאסור לקבל: מוחלט, UNC, רכיב `..`, ובווינדוס גם `:`
/// (נתיב תלוי-כונן `C:x` או זרם נתונים חלופי). הבדיקה הלקסיקלית הזו אינה
/// הגבול כולו — symlink בדרך נבדק ב-[resolveUserFolderPath].
List<String>? parseUserFolderRelativePath(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const [];
  if (trimmed.startsWith('/') || trimmed.startsWith(r'\')) return null;
  if (p.isAbsolute(trimmed)) return null;
  if (Platform.isWindows && trimmed.contains(':')) return null;
  final separators = Platform.isWindows ? RegExp(r'[/\\]') : RegExp('/');
  final segments = <String>[];
  for (final segment in trimmed.split(separators)) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') return null;
    segments.add(segment);
  }
  return segments;
}

/// הנתיב היחסי בצורה שהתוסף מקבל בחזרה — תמיד מופרד ב-`/`.
String joinUserFolderRelativePath(List<String> segments) => segments.join('/');

bool _isInsideOrEqual(String root, String candidate) =>
    p.equals(root, candidate) || p.isWithin(root, candidate);

/// פותר את [segments] בתוך [canonicalRoot] לנתיב קנוני, או `null` כשהנתיב
/// יוצא מהשורש — גם דרך symlink/junction שמצביע החוצה.
///
/// בניגוד למרחב הפרטי, symlink שנשאר בתוך השורש מותר: זו תיקייה של המשתמש,
/// וקישור בתוכה לתת-תיקייה אחרת שלה הוא מבנה לגיטימי.
Future<String?> resolveUserFolderPath(
  String canonicalRoot,
  List<String> segments,
) async {
  if (segments.isEmpty) return canonicalRoot;
  final joined = p.joinAll([canonicalRoot, ...segments]);
  final type = await FileSystemEntity.type(joined, followLinks: false);
  if (type == FileSystemEntityType.notFound) {
    // אין מה לפתור; הנתיב הלקסיקלי כבר בתוך השורש, והקורא יחזיר not_found.
    return joined;
  }
  final String resolved;
  try {
    resolved = await File(joined).resolveSymbolicLinks();
  } on FileSystemException {
    // קישור תלוי (dangling) — אין יעד שאפשר להוכיח שהוא בפנים.
    return null;
  }
  return _isInsideOrEqual(canonicalRoot, resolved) ? resolved : null;
}

int _compareNames(String a, String b) {
  final byFold = a.toLowerCase().compareTo(b.toLowerCase());
  return byFold != 0 ? byFold : a.compareTo(b);
}

/// מונה רמה אחת של [canonicalDir] (שכבר נפתר בתוך [canonicalRoot]).
///
/// הסדר: תיקיות ואחריהן קבצים, כל קבוצה לפי שם. הסינון והמיון נעשים על
/// השמות בלבד, וה-stat רץ רק על הרשומות שנשארו אחרי החיתוך — קובץ שסונן לפי
/// סיומת, נסתר או מעבר לתקרה אינו עולה אף syscall נוסף. כל ה-I/O אסינכרוני,
/// כך שתיקייה גדולה אינה תוקעת את ה-isolate של הממשק.
Future<UserFolderListing> listUserFolderEntries({
  required String canonicalRoot,
  required String canonicalDir,
  required String relativePath,
  Set<String>? extensions,
  int maxEntries = kUserFolderMaxEntries,
}) async {
  final dirs = <_Candidate>[];
  final files = <_Candidate>[];
  FileSystemException? dirError;

  final stream = Directory(canonicalDir).list(followLinks: false).handleError((
    Object e,
  ) {
    // כשל על רשומה בודדת אינו מפיל את המנייה; כשל על התיקייה עצמה נזכר
    // ומדווח אם לא נמנתה אף רשומה.
    dirError ??= e as FileSystemException;
  }, test: (e) => e is FileSystemException);

  await for (final entity in stream) {
    final name = p.basename(entity.path);
    if (isHiddenUserFolderEntry(name)) continue;
    var target = entity.path;
    bool isDir;
    if (entity is Link) {
      final String resolved;
      try {
        resolved = await entity.resolveSymbolicLinks();
      } on FileSystemException {
        continue; // קישור תלוי
      }
      if (!_isInsideOrEqual(canonicalRoot, resolved)) continue;
      final type = await FileSystemEntity.type(resolved);
      if (type == FileSystemEntityType.directory) {
        isDir = true;
      } else if (type == FileSystemEntityType.file) {
        isDir = false;
      } else {
        continue;
      }
      target = resolved;
    } else if (entity is Directory) {
      isDir = true;
    } else {
      isDir = false;
    }
    if (!isDir && extensions != null && !_matchesExtension(name, extensions)) {
      continue;
    }
    (isDir ? dirs : files).add((name: name, target: target, isDir: isDir));
  }

  if (dirs.isEmpty && files.isEmpty && dirError != null) {
    final error = dirError!;
    if (error.path == null || p.equals(error.path!, canonicalDir)) {
      throw error;
    }
  }

  dirs.sort((a, b) => _compareNames(a.name, b.name));
  files.sort((a, b) => _compareNames(a.name, b.name));
  final all = [...dirs, ...files];
  final truncated = all.length > maxEntries;
  final kept = truncated ? all.sublist(0, maxEntries) : all;

  final stats = await Future.wait(kept.map((c) => FileStat.stat(c.target)));
  final prefix = relativePath.isEmpty ? '' : '$relativePath/';
  final entries = <Map<String, dynamic>>[];
  for (var i = 0; i < kept.length; i++) {
    final candidate = kept[i];
    final stat = stats[i];
    // נמחק בין המנייה ל-stat.
    if (stat.type == FileSystemEntityType.notFound) continue;
    entries.add({
      'name': candidate.name,
      'path': '$prefix${candidate.name}',
      'type': candidate.isDir ? 'dir' : 'file',
      'size': candidate.isDir ? 0 : stat.size,
      'modified': stat.modified.millisecondsSinceEpoch <= 0
          ? null
          : stat.modified.toUtc().toIso8601String(),
    });
  }
  return (entries: entries, truncated: truncated);
}
