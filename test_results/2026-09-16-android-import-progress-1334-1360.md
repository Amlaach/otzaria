# issue #1334 + #1360 — ייבוא ספרייה באנדרואיד: 0% לכל אורך ההעתקה, ובחירת קובץ שנראתה כ"לא עובדת"

תאריך: 2026-09-15 | ענף: `fix/android-import-progress-1334` | בסיס: `upstream/dev` (588721404) | קומיטי אימות: `c8aa32c2d` (#1334), `4c7a174d6` (#1360)

## הבאג שאומת

- **#1334**: ייבוא `seforim.db` לא-דחוס מתיקייה — מסך ההתקדמות נשאר על 0% עד הסוף: `File.copy` אינו מדווח כלום.
- **#1360** (מהפורום: המתנה של 3+ דקות, כפתור שנשאר פעיל): באנדרואיד `file_picker` מעתיק את הקובץ הנבחר אל
  `cache/file_picker/<ts>/` (buffer של 8KB) **לפני** שהקריאה חוזרת ל-Dart — דקות על קובץ של כמה GB — והדיאלוג לא
  הציג כלום. חריגות מהבורר (`unknown_path` כשההעתקה למטמון נכשלת, למשל בלי מקום פנוי; `already_active` בלחיצה
  חוזרת) לא נתפסו. הייבוא העתיק את הקובץ **שוב** מהמטמון אל הספרייה, והעותק במטמון נשאר במכשיר.

## התיקון

- `EmptyLibraryBloc.copyFileWithProgress` — העתקה בזרימה עם דיווח כל 4MB (#1334).
- `isFilePickerCacheFile` / `moveFileWithProgress` — עותק שהבורר יצר במטמון מועבר (rename) אל הספרייה במקום
  להיות מועתק שוב; `clearFilePickerCache` אחרי ייבוא מוצלח (אנדרואיד/iOS).
- `LibrarySetupDialog`: `onFileLoading` → מצב "המערכת מעתיקה את הקובץ שנבחר… זה עלול להימשך כמה דקות" עם השבתת
  כפתורי הבחירה (ספינר) והאישור — גם בבחירת ארכיון; חריגה מהבורר → "העתקת הקובץ שנבחר נכשלה — בדוק שיש די מקום
  פנוי באחסון הפנימי". תרגומים ב-ARB, הקטלוג נוצר מחדש.

## בדיקות

| קובץ | מה נבדק |
|---|---|
| `test/empty_library/import_folder_progress_test.dart` | חדש, "(issue #1334)": ייבוא seforim.db של 24MB מדווח התקדמות ביניים. על הבסיס נכשל (0% ואז 1.0). |
| `test/empty_library/import_picker_cache_move_test.dart` | חדש, "(issue #1360)": זיהוי עותק המטמון, `moveFileWithProgress`, וייבוא מהמטמון שאינו משאיר עותק. |
| `test/settings/dialogs/library_setup_dialog_test.dart` | קבוצה חדשה "(issue #1360)": בזמן ההעתקה למטמון ההודעה מוצגת והכפתורים/האישור מושבתים; כשל בבורר מוצג ומשחרר את הכפתורים. |

`flutter test test/settings/dialogs/library_setup_dialog_test.dart test/empty_library/import_picker_cache_move_test.dart`: **23 עברו**.
`flutter test test/empty_library/`: עברו. `flutter analyze` נקי, `dart format` ללא שינויים.

## אימות ויזואלי (אמולטור Android 14, API 34)

קובץ `seforim.db` של 1.4GB (העתק קטום של הספרייה — כמו הגודל שדווח בפורום) ב-`Download/otzaria_lib`, מסך
"ספרייה ריקה" → "בחירת תיקייה מהמחשב" → "בחר קובץ ספרייה".
- **לפני** (הבנייה המותקנת מ-13.9, אותה זרימה כמו dev): במשך ~22 שניות של העתקה למטמון הדיאלוג שקט לגמרי —
  הכפתורים פעילים ואין חיווי; אחרי אישור — "מייבא את קבצי הספרייה… 0%" לכל אורך ההעתקה (~15 שניות), והעותק
  במטמון (1.3GB) נשאר במכשיר.
- **אחרי**: מרגע הבחירה — "The system is copying the selected file… this may take a few minutes", כפתורי הבחירה
  מושבתים (ספינר) והאישור מושבת; בסיום ההעתקה "Still Missing…" והאישור פעיל; הייבוא הסתיים בפחות משנייה
  (rename — הקובץ ב-`app_flutter/books` נושא את קבוצת `u0_a192_cache` של המטמון), ותיקיית `cache/file_picker` נמחקה.
  (שגיאת "database disk image is malformed" שמופיעה אחר כך צפויה — קובץ הבדיקה קטום.)
הצילומים בענף `pr-screenshots` (תיקייה `1334`).

## סוויטה מלאה

`flutter test` על הענף (במקביל לסוויטה נוספת ולבניית Windows): **12,816 עברו, 25 דולגו, 41 נכשלו**.
- כשלי הבסיס המוכרים (10): release_packaging ×2, compaction ×3, personal_notes_file_backed_book,
  search_scope_menu (flaky), change_location_dialog, shamor_zachor, database_library_provider.
- חדש בבסיס ולא קשור לענף (4): `calendar_print_pdf_test` — `opentype_shaper.dll` חסר במחשב הבדיקה; נכשל זהה על
  `upstream/dev` נקי.
- רעידות עומס (27): text_book_bloc ×13, single_window_regression ×4, shared_hive_store ×2, empty_library_bloc ×2
  (הורדה מהרליס), archive_extractor, visible_indices ×3, settings_bloc, settings_snapshot — בריצה חוזרת בבידוד
  עברו כולם (137 בדיקות) למעט `visible_indices_throttle` (רגיש-זמן); text_book_bloc ו-visible_indices_throttle
  בריצה חוזרת במכונה שקטה — **74 עברו, 0 נכשלו**.
