# issue #1358 — Alt+חץ למעלה/למטה קפץ לתחילת הספר ונתקע

תאריך: 2026-09-16 | ענף: `fix/segment-nav-visible-only-1358` | בסיס: `upstream/dev` (588721404) | קומיט אימות: `b0b7c5e6f`

## הבאג שאומת

`ScrollablePositionedList` מדווח ב-`itemPositions` גם פריטים שנגללו כולם מעל החלון ועדיין נמצאים ב-cache
(`itemTrailingEdge <= 0`). `topmostVisibleIndex` בחר את האינדקס הנמוך מכולם — בצורת הדף זו כותרת הספר בפריט 0 —
ולכן "הקטע הקודם" (`scrollTo(topmost - 1)`) קפץ לתחילת הספר ונשאר שם, ו"הקטע הבא" חזר לפריט 1.

## התיקון

`topmostVisibleIndex` (`lib/text_book/utils/visible_index.dart`) מעדיף פריטים שנראים בפועל (קצה תחתון מתחת לקצה
העליון של החלון), עם נפילה לאינדקס המינימלי כשאין כאלה.

## בדיקות

| קובץ | מה נבדק |
|---|---|
| `test/text_book/utils/visible_index_offscreen_test.dart` | חדש, קבוצה "(issue #1358)": פריט 0 ב-cache מעל החלון (trailingEdge שלילי) ופריטים 7-9 נראים → 7; רשימה ריקה → 0; כשאין נראים → המינימלי. על הבסיס נכשל (מחזיר 0). |

`flutter test test/text_book/utils/`: **339 עברו**. `flutter analyze` נקי, `dart format` ללא שינויים.

## אימות ויזואלי

התוכנה עצמה ב-Windows (בניית debug של הבסיס ושל הענף), עירובין דף ב בצורת הדף עם מפרש תחתון ("המאור הקטן") —
התנאי שדיווח המדווח. גלילה לאמצע הדף ואז Alt+חץ למעלה.
- **לפני**: קפיצה לתחילת הספר (כותרת "עירובין / דף ב." בראש החלון).
- **אחרי**: הניווט נשאר באזור הקריאה ועובר קטע-קטע — שתי לחיצות Alt+חץ למעלה עולות קטע כל אחת, ו-Alt+חץ למטה
  חוזר קטע אחד. הצילומים בענף `pr-screenshots` (תיקייה `1358`).

## סוויטה מלאה

`flutter test` על הענף (במקביל לסוויטה נוספת): **12,838 עברו, 25 דולגו, 15 נכשלו**.
- כשלי הבסיס המוכרים (10): release_packaging ×2, compaction ×3, personal_notes_file_backed_book,
  search_scope_menu (flaky), change_location_dialog, shamor_zachor, database_library_provider.
- חדש בבסיס ולא קשור לענף (4): `calendar_print_pdf_test` — `opentype_shaper.dll` חסר במחשב הבדיקה; נכשל זהה על
  `upstream/dev` נקי.
- רעידת עומס (1): `tab_context_menu_test` — בריצה חוזרת במכונה שקטה עבר.
