# issue #1353 — יום שנבחר בלוח נשאר "התאריך הנבחר" לתוספים אחרי סגירת הלוח

תאריך: 2026-09-16 | ענף: `fix/calendar-selected-date-reset-1353` | בסיס: `upstream/dev` (588721404) | קומיט אימות: `51d9f0251`

## הבאג שאומת

`CalendarCubit` הוא אפליקטיבי, וה-API לתוספים (`getSelectedDate`, וגם `getJewishDate` / `getDailyTimes` /
`getEvents` ללא תאריך) מחזיר את `selectedGregorianDate`. יום שנבחר לעיון בלוח נשאר שם גם אחרי סגירת הלשונית,
ותוספים כמו שמו"ת ותיקון קוראים נפתחו לפיו במקום לפי היום. שוחזר בבדיקה: בחירת יום +40 ימים, פירוק הווידג'ט —
התאריך הנבחר נשאר (25.10.2026 במקום 15.9.2026).

## התיקון

בסגירת הלוח (`dispose` של `CalendarWidget`) הבחירה חוזרת להיום דרך `CalendarCubit.resetSelectionToTodayIfNeeded`
— אותה סמנטיקה של כפתור "היום" (`jumpToToday`), כולל מעבר היום ההלכתי. כל עוד הלשונית פתוחה הבחירה נשמרת.

## בדיקות

| קובץ | מה נבדק |
|---|---|
| `test/tools/calendar/widgets/calendar_widget_reset_on_close_test.dart` | חדש, קבוצה "(issue #1353)": `CalendarWidget` עם Cubit אמיתי (שירותי התראות/Google מזויפים), `jumpToDate(+40)`, פירוק — התאריך הנבחר שווה להיום של הלוח. על הבסיס נכשל (Expected 15.9 / Actual 25.10). |

`flutter test test/tools/calendar/`: עברו. `flutter analyze` נקי, `dart format` ללא שינויים.

## אימות ויזואלי

רינדור מבדיקת widget (על הבסיס ועל הענף): הלוח על היום שנבחר, ואז — אחרי סגירת הלשונית — לוח "מה תוסף מקבל
מ-getSelectedDate / getJewishDate": לפני — י"ד חשוון (25.10.2026) באדום; אחרי — ד' תשרי (15.9.2026) בירוק.
הצילומים בענף `pr-screenshots` (תיקייה `1353`).

## סוויטה מלאה

`flutter test` על הענף (במקביל לסוויטה נוספת): **12,827 עברו, 25 דולגו, 25 נכשלו**.
- כשלי הבסיס המוכרים (10): release_packaging ×2, compaction ×3, personal_notes_file_backed_book,
  search_scope_menu (flaky), change_location_dialog, shamor_zachor, database_library_provider.
- חדש בבסיס ולא קשור לענף (4): `calendar_print_pdf_test` — `opentype_shaper.dll` חסר במחשב הבדיקה; נכשל זהה על
  `upstream/dev` נקי.
- רעידות עומס (11): text_book_bloc ×9, reader_location_tracker, tab_context_menu — בריצה חוזרת במכונה שקטה **73 עברו, 0 נכשלו**.

הערה: ריצה ראשונה של הסוויטה ב-worktree חדש נתנה 55 כשלים ו-261 דילוגים — ה-worktree לא נבנה ל-Windows ולכן חסר
בו `search_engine.dll` שהבדיקות התלויות במנוע ה-Rust טוענות; אחרי העתקת הספרייה הנייטיבית התוצאה למעלה.
