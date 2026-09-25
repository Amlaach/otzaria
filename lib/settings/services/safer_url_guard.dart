import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:otzaria/core/ui_snack.dart' show navigatorKey;
import 'package:otzaria/settings/services/safer_mode_guard.dart';


/// מחליף את `launchUrl` — חוסם URL חיצוני במצב סייפר.
///
/// במצב קיוסק מנוהל (`--kiosk` / `--safer`) — פתיחת דפדפן או דוא"ל חסומה לחלוטין.
/// במצב סייפר רגיל — נדרש אימות סיסמה דרך [verifySaferModePassword].
/// אם [context] הוא null (למשל מתוך שירות רקע) — נעשה שימוש ב-[navigatorKey.currentContext].
Future<bool> saferLaunchUrl(
  BuildContext? context,
  Uri uri, {
  LaunchMode mode = LaunchMode.platformDefault,
}) async {
  if (isKioskMode) {
    // במצב קיוסק פתיחת דפדפן, דוא"ל או כל תוכנה/קישור חיצוני חסומה תמיד למניעת בריחה (Kiosk Breakout)
    return false;
  }

  final effectiveContext = context ?? navigatorKey.currentContext;
  if (effectiveContext != null) {
    if (shouldRequireSaferModePassword(effectiveContext)) {
      if (!effectiveContext.mounted || !await verifySaferModePassword(effectiveContext)) {
        return false;
      }
    }
  } else {
    // Fail-closed: אם אין context זמין לאימות סיסמה בסייפר, חוסמים קישורים חיצוניים
    return false;
  }

  return launchUrl(uri, mode: mode);
}

/// גרסת String — מנתח את ה-URL ומעביר ל-[saferLaunchUrl].
Future<bool> saferLaunchUrlString(
  BuildContext? context,
  String url, {
  LaunchMode mode = LaunchMode.platformDefault,
}) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  return saferLaunchUrl(context, uri, mode: mode);
}
