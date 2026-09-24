# דוח בדיקה מקיף: מצב סייפר ומנגנוני הנעילה באוצריא

**תאריך עריכה:** 23 בספטמבר 2026  
**גרסת קוד נבדקת:** `dev` (קומיט `9eeb092dd`)  
**מערכת יעד:** אוצריא (Otzaria) הפועלת תחת מערכת עמדות מחשב ציבוריות "סייפר" (Safer / Safera)

---

## 1. תקציר מנהלים

תוכנת אוצריא כוללת מצב נעילה פנימי המכונה בממשק ובקוד **"מצב סייפר"** (`protectedModeEnabled`). מצב זה נועד במקור למנוע ממשתמשי עמדות ציבוריות (כגון בתי כנסת, ספריות וישיבות) לשנות הגדרות, להשחית מידע, או "לברוח" מתוך אוצריא אל שולחן העבודה וסייר הקבצים של מערכת ההפעלה Windows (Kiosk Breakout).

בדיקת הקוד מעלה שתי מסקנות יסוד:
1. **הממשק מול מערכת "סייפר" החיצונית:** אין כיום שום סנכרון תוכנתי (IPC, Named Pipes, Sockets או Windows Messages) בין תוכנת סייפר לבין אוצריא. סייפר מריצה את `otzaria.exe` כתהליך עצמאי רגיל. כל לוגיקת הנעילה היא **פנימית לחלוטין באוצריא**.
2. **מצב הנעילה הפנימי באוצריא:** המערכת מגנה היטב על מסך ההגדרות, איפוס המערכת, הדפסה ישירה (ללא דיאלוג מערכת) וסייר הקבצים. **עם זאת, קיימות פרצות מהותיות המאפשרות פתיחת דפדפן אינטרנט חיצוני, תוכנת דואר, או התקנת תוספים עוקפת**, המהוות פתח לבריחה מקיוסק.

---

## 2. מיפוי מקיף של המצב הפנימי הקיים

המנגנון נשען על שמירת גיבוב סיסמה (SHA-256) ב-Hive (`SettingsRepository`), ונבדק ע"י הפונקציה המרכזית:
```dart
Future<bool> verifySaferModePassword(BuildContext context);
```

### א. מה ננעל ומאובטח כראוי כיום:

| רכיב / מסך | מיקום בקוד | מנגנון ההגנה |
| :--- | :--- | :--- |
| **מסך ההגדרות** | [`lib/settings/services/safer_mode_guard.dart`](../lib/settings/services/safer_mode_guard.dart) | עטוף ב-`SaferModeGuard`. כל יציאה מההגדרות נועלת מחדש. חזרה להגדרות דורשת סיסמה מחדש. |
| **ניהול סיסמה ומצב סייפר** | [`lib/settings/tabs/system_settings_tab.dart`](../lib/settings/tabs/system_settings_tab.dart) | כיבוי מצב סייפר, שינוי סיסמה או מחיקתה מחייבים אימות סיסמה קודם. |
| **איפוס הגדרות** | `system_settings_tab.dart:2965` | איפוס הגדרות יצרן (`clearAllPreferences`) מחייב סיסמה. |
| **הדפסה ומניעת בריחה** | [`lib/printing/safer_print_service.dart`](../lib/printing/safer_print_service.dart), [`safer_printer_filter.dart`](../lib/printing/safer_printer_filter.dart) | עקיפת דיאלוג ההדפסה של Windows (הכולל "Print to PDF" ודיאלוג שמירה של סייר הקבצים). סינון מדפסות וירטואליות (`PORTPROMPT:`, `FILE:`, `nul:`) והדפסה ישירה ב-`directPrintPdf` רק למדפסות פיזיות. |
| **שמירה וייצוא קבצים** | [`lib/utils/file/save_file_with_extension.dart`](../lib/utils/file/save_file_with_extension.dart) | חסימת `FilePicker.saveFile` לכל ייצוא של ספר, הערות (JSON/TXT/Word), או דוחות תקלה offline. |
| **שינוי מיקום ספרייה** | [`lib/empty_library/empty_library_screen.dart`](../lib/empty_library/empty_library_screen.dart), [`lib/settings/tabs/library_settings_tab.dart`](../lib/settings/tabs/library_settings_tab.dart) | בורר תיקיות להגדרת או שינוי נתיב הספרייה מחייב סיסמה. |
| **עריכת תכנים והערות** | `text_section_editor_dialog.dart`, `personal_note_editor_dialog.dart` | עריכת קטע בספר מקומי או הוספת/עריכת הערה אישית מחייבות סיסמה לפני שמירה. |
| **סייר קבצים (Explorer)** | `main_window_screen.dart:3703` | פתיחת קובץ יומן שגיאות ב-Windows Explorer מחייבת סיסמה. |
| **ממשק תוספים (Plugins UI)** | `tools_launcher_panel.dart`, `plugin_side_panel.dart` | התקנת תוסף מתוך התוכנה, טעינת תוסף פיתוח או localhost, וגרירת תוסף דורשות סיסמה. |
| **API של תוספים (Plugin Bridge)** | `plugin_bridge_adapter.dart`, `plugin_tab_page.dart` | קריאות תוסף לבורר קבצים (`pickFile`), בורר תיקיות (`pickFolder`), שמירת קובץ (`pickSaveLocation`), או `<input type="file">` ב-WebView (`onShowFileChooser`) מחייבות סיסמה. |

---

### ב. מה אינו נעול – פרצות בריחה מהקיוסק (Kiosk Breakouts):

בסביבת קיוסק כמו "סייפר", כל פתיחה של יישום חיצוני (במיוחד דפדפן רגיל או תוכנת מייל) שוברת את הנעילה ומאפשרת למשתמש להגיע לשולחן העבודה או לגלוש באינטרנט. בקוד הנוכחי קיימות הפרצות הבאות:

> [!CAUTION]
> **1. כפתור "פתח באתר" בדיאלוג אוצר החכמה**  
> בקובץ [`lib/library/view/otzar_book_dialog.dart`](../lib/library/view/otzar_book_dialog.dart#L181-L196), בלחיצה על כפתור "פתח באתר" נקראת הפונקציה:
> ```dart
> await OtzarUtils.launchOtzarWeb(book.link);
> ```
> **אין שום בדיקת סיסמה!** הפעולה פותחת מיידית את הדפדפן הראשי של מערכת ההפעלה (Edge/Chrome).

> [!CAUTION]
> **2. קישורים חיצוניים בתוך קובצי PDF**  
> בקובץ [`lib/pdf_book/view/pdf_book_screen.dart`](../lib/pdf_book/view/pdf_book_screen.dart#L4841-L4845), לחיצה על היפר-קישור בתוך ספר PDF מציגה דיאלוג אישור פשוט ("האם לעבור לכתובת...?") ולאחר לחיצה על אישור פותחת את הדפדפן באמצעות `launchUrl(url)` ללא שום בדיקת סיסמה.

> [!WARNING]
> **3. קישורי HTML בספרי טקסט**  
> בקובץ [`lib/utils/text/html_link_handler.dart`](../lib/utils/text/html_link_handler.dart#L204-L212), אם בספר טקסט מוטמע קישור חיצוני (`http://` או `https://`), הפונקציה `handleLink` שולחת אותו ישירות ל-`launchUrl` ללא בדיקת מצב סייפר.

> [!WARNING]
> **4. דיווח שגיאות – פתיחת אתר דיקטה ותוכנת דואר**  
> בקובץ [`lib/text_book/view/error_report_dialog.dart`](../lib/text_book/view/error_report_dialog.dart#L901-L921):
> * לחיצה על "ערוך באתר דיקטה" (`launchDictaEditPage`) פותחת דפדפן אינטרנט חיצוני.
> * לחיצה על "שלח דוא\"ל" מפעילה קישור `mailto:` הפותח את תוכנת הדואר המוגדרת ב-Windows (כגון Outlook).
> * הדיאלוג עצמו זמין לכל משתמש קריאה ללא סיסמה.

> [!WARNING]
> **5. התקנת תוספים עוקפת דרך Deep Link (`otzaria://`)**  
> בעוד שהתקנה ידנית דרך מסך הכלים נחסמה בסיסמה, טיפול בקישורי עומק חיצוניים ב-[`lib/navigation/view/main_window_screen.dart`](../lib/navigation/view/main_window_screen.dart#L1385-L1398) (`InstallPluginAction` ו-`InstallLocalPluginAction`) מקבל פקודת התקנה ומתקין תוסף **ללא סיסמה**. לחיצה כפולה על קובץ `.otzplugin` או פקודת שורת פקודה תעקוף את ההגנה.

> [!WARNING]
> **6. תוספים פעילים: `openExternal`**  
> ב-[`lib/plugins/bridge/plugin_bridge_adapter.dart`](../lib/plugins/bridge/plugin_bridge_adapter.dart#L924), תוסף יכול לקרוא ל-`ui.openExternal(url)` וזה פותח דפדפן חיצוני ללא אימות סיסמה.

> [!NOTE]
> **7. נפילה לאחור להרצת שורת פקודה (`cmd`)**  
> ב-[`lib/utils/navigation/otzar_utils.dart`](../lib/utils/navigation/otzar_utils.dart#L166), אם הרצת `otzar.exe` מחזירה קוד שגיאה, מתבצע ניסיון הרצה שני דרך:
> ```dart
> Process.run('cmd', ['/c', 'start', '', exePath, ...arguments]);
> ```
> בסביבות קיוסק מסוימות הרצת `cmd` עלולה להציג הבזק חלון פקודה או לאפשר ניצול במקרה של כשל.

---

## 3. ניתוח המנגנון מול מערכת "סייפר" (Safer)

### כיצד זה עובד טכנית כיום:
* **אין ערוץ תקשורת מובנה:** אוצריא אינה משדרת אותות חיים (Heartbeat), אינה מקשיבה ל-Sockets/Pipes מסייפר, ואינה יודעת האם "סייפר" מותקנת על המחשב.
* **ניהול התהליך:** תוכנת סייפר מפעילה את `otzaria.exe` כמשימה חיצונית. בסיום זמן השימוש בעמדה, סייפר היא זו שממזערת, חוסמת במסך נעילה, או מחסלת (`TerminateProcess`) את חלון אוצריא מבחוץ.
* **הדפסות וחיוב כספי:** סייפר מנהלת חיוב על הדפסות דרך ניטור ה-Windows Print Spooler. מכיוון שאוצריא בחרה להדפיס באמצעות `directPrintPdf` ישירות למדפסת הנבחרת, ההדפסה נקלטת בספולר של Windows בצורה תקינה לחלוטין ומאפשרת לסייפר לחייב לפי כמות עמודים.

---

## 4. המלצות ותוכנית שיפורים בצד של אוצריא

ניתן לחזק את המערכת בצד של אוצריא בצורה ניכרת כדי להתאים בצורה הרמטית לעמדות סייפר וקיוסק:

### שלב 1: שער חסימת דפדפן גלובלי במצב סייפר (`SaferUrlGuard`)
* יצירת פונקציית מעטפת מרכזית עבור `launchUrl` ו-`launchUrlString`.
* במצב שבו `shouldRequireSaferModePassword` מתקיים:
  * חסימה מוחלטת או הצגת דיאלוג סיסמה לפני פתיחת כתובות חיצוניות (HTTP/HTTPS/MAILTO).
  * טיפול בכל המוקדים: דיאלוג אוצר החכמה, קישורי PDF, קישורי HTML, קישורי דיקטה ומייל, ו-`ui.openExternal` בתוספים.

### שלב 2: תמיכה בדגל שורת פקודה (`--kiosk` / `--safer`)
* כיום, הפעלת מצב סייפר דורשת כניסה ידנית להגדרות והזנת סיסמה.
* הוספת דגל CLI: `otzaria.exe --kiosk` או `otzaria.exe --safer`.
* כאשר אוצריא מופעלת עם דגל זה (שסייפר יכולה להעביר בקלות בהגדרות ההפעלה של העמדה):
  * מצב סייפר יופעל אוטומטית כברירת מחדל לכל הסשן.
  * מסך ההגדרות יינעל מיד.

### שלב 3: מדיניות מנהל מערכת גלובלית (Admin Policy)
* תמיכה בקובץ הגדרות מוגן ברמת מערכת (למשל `C:\ProgramData\Otzaria\policies.json`).
* אם הקובץ מכיל הגדרת נעילת קיוסק וסיסמת מנהל, אוצריא תכפה את מצב הסייפר גם אם משתמש מקומי מוחק או מאפס את קובצי ה-AppData שלו.

### שלב 4: נעילת Deep Links והתקנת תוספים
* ב-[`main_window_screen.dart`](../lib/navigation/view/main_window_screen.dart#L1385), הוספת בדיקת `verifySaferModePassword` לפני ביצוע `InstallPluginAction` או `InstallLocalPluginAction`.

---

## 5. סיכום

ההחלטה של מפתחי אוצריא להטמיע "מצב סייפר" הייתה צעד נכון שהניח תשתית מצוינת (במיוחד במנגנון ההדפסה הייעודי ונעילת סייר הקבצים). עם זאת, כדי להבטיח הרמטיות מלאה בעמדות ציבוריות של סייפר, נדרש לאטום את ערוצי היציאה לרשת (דפדפן חיצוני ודוא"ל) ולאפשר לסייפר להפעיל את מצב הנעילה ישירות באמצעות פרמטר הרצה או קובץ מדיניות.
