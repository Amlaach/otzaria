# מסדים מצורפים — הערות ארכיטקטורה למפתחים

תיעוד המשתמש ובוני המסדים: [personal_databases.md](personal_databases.md).
כאן: איך הפיצ'ר בנוי ואיפה נוגעים כשמרחיבים אותו.

## זהות ומפתחות

| שכבה | ערכים |
|---|---|
| `BookSource` | `official` / `user` / `attached(slug)` |
| מפתח wire | `o` / `u` / `d:<slug>` |
| `BookCompositeKey` | סיומת מקור על מפתח הספר |
| מפתח אינדקס החיפוש | `id:` / `uid:` / `ext:` / `db:<slug>:<id>` |
| הערות אישיות | `"<title>|db:<slug>"` |
| `bookUid` לתוספים | `db:<slug>:<id>`, `source: "attached"` |

- slug: `schema_meta.library_id`, אחרת שם הקובץ אחרי ניקוי; אותיות (כולל עברית), ספרות,
  `._-`, עד 64 תווים. התנגשות slug ← הקובץ השני נדחה.
- ספרים מצורפים נוספים **בסוף** סדר הקטלוג של האינדקס, כך שצירוף מסד לא מזיז מפתחות של
  ספרים אחרים ולא גורם לאינדוקס מחדש שלהם. החלפת קובץ באותו slug ← אינדוקס מחדש רק שלו.

## מבנה הקוד

```
lib/attached_libraries/
├── bloc/          # מצב המסדים בהגדרות (צירוף, הסרה, עדיפות, מיקום, הסתרה)
├── models/
└── repository/
    ├── registry            # פתיחה עצלה ומוקשחת, סגירה בזמן סרק, closeAll
    ├── probe (isolate)     # בדיקת קובץ לפני צירוף: slug, WAL/journal, טבלאות
    ├── store               # שמירת רשימת המסדים והגדרותיהם
    └── external_link_core / external_link_repository
lib/migration/database/
├── db_capabilities.dart    # מקור אמת יחיד לקיום טבלאות/עמודות
└── untrusted_database.dart # openUntrustedReadOnlyDatabase, ReadOnlyDbTarget
```

- **`DbCapabilities`** — רשימת היתר של טבלאות, getter יכולת לכל טבלה/זוג. נשמר במטמון
  לפי נתיב + `PRAGMA schema_version`. שם מוכר שהוא VIEW/וירטואלי נחשב חסר.
- **`openUntrustedReadOnlyDatabase`** — read-only, `query_only`, `trusted_schema=OFF`,
  defensive, ללא הרחבות, mmap כבוי. `ReadOnlyDbTarget` מעביר את אותה פתיחה ל-isolates.
- **קטלוג המסדים** נקרא ב-isolate עם timeout לכל מסד; מסד שלא עונה מסומן לא זמין
  והעץ ממשיך.
- **איתור מקורות** במסדים מצורפים רץ ב-isolate עובד ברקע.
- **`external_link`** — אינדקס צד של קישורים הפוכים ב-`cache.db`, נבנה מחדש כשהקובץ או
  גרסת הספרייה הרשמית משתנים. מגבלה: 5,000,000 שורות למסד (נבנה בזרם, במנות), חיתוך כותרת/הפניה ב-512.

## עלייה

`_runDeferredAttachedLibraries` ב-`main.dart` רץ אחרי חשיפת החלון (שער reveal עם
timeout), מוגן ב-`WindowRole.isSecondary` לעבודה ברמת מחשב, ונכשל ללא הפלה
(`_logNonFatalInitializationError`). שום דבר מהפיצ'ר לא נוסף למסלול לפני הפריים הראשון.

## כלל היתומים באינדקס

מפתחות `db:` נמחקים מהאינדקס **רק** כש:
1. המסד הוסר מהרשימה, או
2. הספר נעלם ממסד שנטען, גלוי ונגיש.

מסד לא זמין או מוסתר לעולם לא גורם למחיקה — אחרת ניתוק כונן היה מוחק את האינדקס,
הסימניות וההערות.

## הוספת טבלה חדשה לתמיכה

1. **רשימת היתר ב-`DbCapabilities`** — הוסיפו את שם הטבלה (וגם את בת הזוג אם הן
   חייבות לבוא יחד).
2. **getter יכולת** — `hasX` שבודק קיום (ועמודות נדרשות); לזוג — שתי הטבלאות.
3. **שער בנקודת השאילתה** — כל שאילתה על הטבלה נשמרת ב-getter, והחזרה ריקה כשהיכולת
   חסרה. אין להניח קיום טבלה במסד מצורף.
4. עדכנו את `tool/validate_personal_db.dart` ואת קטלוג הטבלאות ב-
   [personal_databases.md](personal_databases.md).

טבלה שאינה ברשימת ההיתר לעולם לא נקראת — זה חלק ממודל האבטחה, לא מגבלה זמנית.

## אבטחה — עקרונות שאסור לשבור

- המסד לעולם לא נכתב; עותק מנוהל (מובייל) הוא היחיד שה-journal שלו מנורמל.
- שום דבר מהמסד לא מותקן או מורץ (תוספים, סקריפטים, גופנים).
- קישורים בטקסט הספר — ניווט בלבד.
- `book.filePath` — יחסי לתיקיית המסד בלבד; נדחים נתיב מוחלט, אות כונן, UNC, `..`,
  רכיב של נקודות/רווחים בלבד, `:`, NUL.

## עדכונים (שלב U1: מודל, אימות ורשת)

- **נעיצה (TOFU):** `AttachedLibraryProbe` קורא `update_manifest_url`/`update_public_key` עם `library_id` ל-`AttachedLibraryUpdateSource`. `_applyProbe` נועץ אותו ב-`AttachedLibrary.updateSource` בצירוף. בבדיקה חוזרת של אותו slug הנעוץ נשמר, וכל סטייה (גם הסרה) מסמנת `updateSourceMismatch` — בלי רשת. slug אחר הוא מסד אחר ונעוץ מחדש. `updateSourceProbed` גורם למסד שצורף לפני התכונה להיבדק שוב פעם אחת.
- **מניפסט:** `models/attached_update_manifest.dart` — פענוח קפדני אחרי אימות החתימה בלבד. `checkApplicable` דוחה `library_id` שונה ו-`db_version` שאינו גדול מהמותקן (או מותקן שאינו מספר שלם).
- **חתימה:** `repository/update/attached_update_signature.dart` — ed25519 דרך `pinenacl` (Dart טהור, בלי תלויות). נבדקת תמיד מול המפתח הנעוץ, לעולם לא מול מפתח מקובץ שהורד.
- **רשת:** `AttachedUpdateHostPolicy` (https, שם מארח ולא IP, בלי שמות מקומיים, כל כתובות ה-DNS ציבוריות) ו-`AttachedUpdateFetcher`: `connectionFactory` מתחבר לכתובות שהמדיניות אישרה ומקים TLS מול שם המארח (אין תרגום DNS שני), הפניות מטופלות ידנית ונבדקות, `findProxy` = DIRECT, timeouts לחיבור ולכל נתח. תעודות נטפרי מגיעות מה-SecurityContext הגלובלי שנטען בעלייה. dart:io בלבד — אפשר להריץ ב-isolate.
- **הורדה ובנייה:** `downloadParts` משרשר את החלקים לקובץ אחד עם sha256 לכל חלק, ממשיך ב-Range אחרי אימות מה שכבר בדיסק, וחלק פגום נחתך. `AttachedUpdateArtifactBuilder` פורס zstd בזרם דרך `ZstdStreamExtractor` (אותו FFI של עדכון הספרייה) ובודק גודל ו-sha256.
- **delta:** מפוענח בלבד. ה-`PatchApplier` של seforim_library_updater מקבל נתיב מסד, אבל קשור לרשימת הטבלאות ולגיבוב הלוגי של הספרייה הרשמית ולקובצי patch שמיוצרים ב-SeforimLibrary — אין למפרסם אישי דרך לייצר אותם. נדחה ל-v2.
- **לבדיקות:** `AttachedUpdateHostPolicy.allowLoopbackForTesting` מתיר http ל-127.0.0.1 בפורטים שנמסרו בלבד; מדיניות הייצור אינה משתנה.
