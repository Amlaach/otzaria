import 'dart:convert';

import 'package:path/path.dart' as p;

/// שם המסמך הווירטואלי שבו רץ תוסף ללא ממשק. אינו קיים בדיסק — ה-WebView
/// מקבל אותו מיירוט הבקשה, כך שמיקומו בשורש התוסף קובע את הבסיס לנתיבים יחסיים.
const String pluginHeadlessShellFileName = '.otzaria-headless.html';

/// נתיב המסמך הווירטואלי בתוך [rootPath].
String pluginHeadlessShellPath(String rootPath) =>
    p.join(rootPath, pluginHeadlessShellFileName);

/// האם [filePath] הוא המסמך הווירטואלי של התוסף שב-[rootPath].
bool isPluginHeadlessShellPath(String filePath, String rootPath) =>
    p.equals(p.normalize(filePath), pluginHeadlessShellPath(rootPath));

/// המעטפת שטוענת את [entrypoint] של תוסף ללא ממשק.
///
/// [module] רק כשהמעטפת מוגשת מ-`otzaria-plugin://`: Chromium חוסם מודולים מ-`file://`.
String pluginHeadlessShellHtml(String entrypoint, {required bool module}) {
  final src = p.posix
      .split(entrypoint.replaceAll('\\', '/'))
      .map(Uri.encodeComponent)
      .join('/');
  return '<!DOCTYPE html><html><head><meta charset="utf-8">'
      '<script${module ? ' type="module"' : ''} '
      'src="${const HtmlEscape(HtmlEscapeMode.attribute).convert(src)}">'
      '</script></head><body></body></html>';
}
