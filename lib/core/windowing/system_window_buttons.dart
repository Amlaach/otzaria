import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// האם כפתורי החלון (מזעור/הגדלה/סגירה) מצוירים בידי מערכת ההפעלה.
///
/// במק אלה ה-traffic lights הנייטיביים, שמגיעים עם המראה, ההתנהגות ותפריט
/// ההקשר של המערכת — ולכן שם אין מציירים כפתורים מותאמים במקומם.
bool get useSystemWindowButtons => !kIsWeb && Platform.isMacOS;

/// הרוחב ש-macOS תופסת ל-traffic lights בפינת החלון, והמקום שסרגל הכותרת
/// חייב להשאיר להם פנוי.
const double kSystemWindowButtonsWidth = 78.0;

/// הריפוד שמפנה את פינת הכפתורים בסרגל הכותרת, או `EdgeInsets.zero` מחוץ למק.
///
/// ⚠️ הפינה היא **ימנית**, ולא שמאלית כמו ברוב אפליקציות המק: AppKit משקפת
/// את הכפתורים כש-`NSApp.userInterfaceLayoutDirection` הוא RTL, ו-Info.plist
/// של המק מצהיר `CFBundleLocalizations = [he]` בלבד — כלומר תמיד. הריפוד
/// פיזי (`EdgeInsets`) ולא כיווני, כי הצד נקבע בידי המערכת ולא בידי
/// הכיווניות של ה-widget.
EdgeInsets get systemWindowButtonsPadding => useSystemWindowButtons
    ? const EdgeInsets.only(right: kSystemWindowButtonsWidth)
    : EdgeInsets.zero;
