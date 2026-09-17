# issue #1411 — Cmd+, במק בפריסה עברית לא נתפס על מקש הפסיק הפיזי

**ענף:** `fix/mac-hebrew-symbol-shortcuts-1411` על `upstream/dev` 04b56859d · **worktree:** otzaria-wt6 · **תאריך:** 17.9.2026

## השורש
`ShortcutHelper.matchesShortcut` זיהה מקשי סימנים וספרות לפי `logicalKey` בלבד. ב-Windows המנוע מדווח
למקש כזה עם Ctrl את המקש הווירטואלי (`comma`) בכל פריסה, אבל ב-macOS ה-`logicalKey` הוא התו של הפריסה
הפעילה — `'ת'` על מקש הפסיק (ליד M) בעברית — ולכן `ctrl+comma` נתפס שם רק על המקש שמפיק `','` בעברית
(ליד Return). אותו פער היה בהקלטת קיצור חדש (`logicalKeyToStore`): המקש נשמר כ-`'ת'` ולא היה מזוהה.

## התיקון
השלמת הכלל שכבר חל על אותיות: כשהתו המדווח אינו מקש מוכר ב-`KeyMap` (לא a–z ולא שם מקש), המיקום הפיזי
בפריסת US מכריע — `KeyMap.nameToPhysicalKey` / `physicalKeyFor` / `keyForPhysical`, ו-`ShortcutHelper.isLayoutSpecificKey`.
תו שהוא בעצמו מקש מוכר (פריסה לטינית שמזיזה סימנים, כמו גרמנית שבה המקש הפיזי של `/` מפיק `-`) ממשיך להיות
מזוהה לפי התו בלבד — אין שינוי לפריסות אלה.

## בדיקות — `test/shortcuts/hebrew_layout_symbol_shortcut_test.dart`

| בדיקה (issue #1411) | לפני | אחרי |
|---|---|---|
| macOS: Cmd + מקש הפסיק הפיזי (מדווח "ת") פותח את ctrl+comma | ❌ `Expected: true / Actual: false` | ✅ |
| macOS: מקש הפסיק העברי (ליד Return, מדווח comma) ממשיך לעבוד | ✅ | ✅ |
| כל פלטפורמה: Ctrl + מקש הנקודה הפיזי (מדווח "ץ") תואם ctrl+period ולא ctrl+comma | ❌ | ✅ |
| פריסה לטינית שמזיזה סימנים מזוהה לפי התו (גרמנית: `/` פיזי → `-`) | ✅ | ✅ |
| הקלטת קיצור: מקש הפסיק הפיזי בעברית נשמר כ-comma | ❌ `Actual: Key ת` | ✅ |
| הקלטת קיצור: תו מוכר על מקש פיזי אחר נשמר כמו שהוא | ✅ | ✅ |

בדיקות ממוקדות: `test/shortcuts/` כולו + `core/windowing` + מסכי הספר — 408 עברו. `flutter analyze` — No issues found. `dart format` — ללא שינוי.

## סוויטה מלאה (otzaria-wt6)
12 כשלים, כולם בבסיס הסביבתי המוכר שנכשל גם על dev נקי: `installer/release_packaging_test` ×2,
`migration/sync/file_sync_service_compaction_test` ×3, `data_providers/database_library_provider_test`,
`tools/calendar/helpers/calendar_print_pdf_test` ×4 (`opentype_shaper.dll` חסר), `settings/dialogs/change_location_dialog_test`,
`shamor_zachor/shamor_zachor_data_provider_test`. אין כשל חדש.

## אימות התנהגות
התיקון הוא בלוגיקת התאמת מקשים ואין לו ביטוי חזותי; ההתנהגות מאומתת בבדיקות היחידה שמדמות בדיוק את
אירוע המקלדת של macOS בפריסה עברית (`physicalKey: comma`, `logicalKey: U+05EA`, Meta לחוץ).
אין לי מחשב Mac לשחזור חי — המדווח מוזמן לאשר בגרסה הבאה.
