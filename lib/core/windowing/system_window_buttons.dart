import 'dart:io';

import 'package:flutter/foundation.dart';

/// האם כפתורי החלון (מזעור/הגדלה/סגירה) מצוירים בידי מערכת ההפעלה.
///
/// במק אלה ה-traffic lights הנייטיביים, שמגיעים עם המראה, ההתנהגות ותפריט
/// ההקשר של המערכת — ולכן שם אין מציירים כפתורים מותאמים במקומם.
bool get useSystemWindowButtons => !kIsWeb && Platform.isMacOS;

/// הרוחב ש-macOS תופסת ל-traffic lights בפינת החלון, והמקום שסרגל הכותרת
/// חייב להשאיר להם פנוי.
const double kSystemWindowButtonsWidth = 78.0;
