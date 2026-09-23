# issue #1473 — תשע הודעות UiSnack עקפו את קטלוג ההודעות

**ענף:** `fix/uisnack-messages-catalog-1473` על `upstream/dev` 780ae3f94 · **פלטפורמה:** macOS 27.0 · **Flutter:** 3.47.2 (זהה ל-CI) · **תאריך:** 23.9.2026

## הבאג
`CLAUDE.md`: *"Never pass a hardcoded string literal to `UiSnack`. Every message lives in
`lib/core/messages/`"*. תשע הודעות עקפו את הכלל — שמונה ב-`calendar_event_dialog.dart`
ואחת ב-`empty_library_screen.dart`.

## מה שהופך את זה מסגנון לבאג ממתין
**שלוש מהתשע הן שכפול מילולי של ערכים שכבר קיימים בקטלוג:**

| המחרוזת באתר הקריאה | הערך הקיים |
|---|---|
| `'יש למלא כותרת לאירוע.'` | `ToolsMessages.eventTitleRequired` |
| `'יש להזין מספר שנים חיובי עבור אירוע חוזר.'` | `ToolsMessages.eventRecurringYearsInvalid` |
| `'שגיאה בטעינת הספרייה. נסה שוב.'` | `LibraryMessages.libraryLoadError` |

כלומר אותו טקסט תוחזק בשני מקומות. עריכת הנוסח באחד מהם — למשל בקטלוג, שהוא
המקום הטבעי לחפש בו — הייתה מפצלת את ההודעה בלי שאיש ישים לב, כי שום בדיקה ושום
`analyze` אינם רואים בזה בעיה.

## התיקון
שלוש ההודעות הכפולות מפנות לערכים הקיימים. שש הנותרות נוספו ל-`ToolsMessages` ליד
שאר הודעות האירועים:

```dart
eventDateUnparsable, eventDateOutOfRange, eventEndTimeBeforeStart,
alertAmountMustBePositive, alertAtMostThreeMonths, alertMustPrecedeEvent
```

**אין הודעה חדשה ואין שינוי נוסח** — כל הטקסטים הועתקו כלשונם, כולל הנקודה בסוף.

## בדיקות

| בדיקה (issue #1473) | לפני | אחרי |
|---|---|---|
| אין מחרוזת קשיחה ב-`UiSnack` (סריקה סטטית על כל `lib`) | ❌ 9 מופעים | ✅ |

הסריקה מכסה את כל `lib` ולא רק את שני הקבצים, כך שהיא תתפוס גם את המופע הבא.

`flutter analyze` — No issues found.
`flutter test test/tools/calendar/ test/empty_library/` — 288 עברו, 5 נכשלו: כולם
ב-`calendar_print_pdf_test.dart`, שנכשל באותן חמש גם בבסיס.

## סוויטה מלאה מול הבסיס
שתיהן על `upstream/dev 780ae3f94`, כל אחת רצה לבדה, עם `--file-reporter=json`.

| | עברו | דולגו | נכשלו |
|---|---|---|---|
| `dev` | 13,962 | 282 | 37 |
| הענף | 13,967 | 282 | 33 |

**אפס כשלים ייחודיים לענף.**

ארבעה כשלים הופיעו רק בהרצת הבסיס, כולם ב-`window_bus_test.dart`. הרצתי את הקובץ
לבדו על `dev` נקי: 14 עברו, 0 נכשלו — flakes.
