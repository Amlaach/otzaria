# issue #1313 — מסך "הערות אישיות" הציג את הערות ספר אחד תחת ספר אחר

תאריך: 2026-09-15 | ענף: `fix/personal-notes-stale-on-error-1313` | בסיס: `upstream/dev` (588721404) | קומיט אימות: `03205d15d`

## הבאג שאומת

`PersonalNotesBloc` משותף לכל הספרים. בטעינת ספר חדש, מצב הטעינה — וגם מצב השגיאה כשתוכן הספר אינו זמין —
נשאו את `locatedNotes` / `missingNotes` (והרשימות המסוננות) של הספר הקודם. מסך ההערות שומר כל מצב לא-טוען לפי
`bookId`, ולכן ספר שטעינתו נכשלה "קיבל" את הערות הספר הקודם, ולחיצה עליהן פתחה את הספר המקושר להערה.
שוחזר ברינדור המסך (בדיקת widget): "ספר שבור" הציג את ההערה של "ספר תקין".

## התיקון

`_onLoadNotes`: בטעינת ספר אחר מצב הטעינה יוצא עם רשימות ריקות (`isSameBook ? null : const []`), ומצב השגיאה
מגיע תמיד עם ארבע הרשימות ריקות.

## בדיקות

| קובץ | מה נבדק |
|---|---|
| `test/personal_notes/bloc/personal_notes_error_clears_notes_test.dart` | חדש, "(issue #1313)": טעינת ספר א' מצליחה, טעינת ספר ב' נכשלת — מצב השגיאה אינו נושא את הערות ספר א' (located/missing/filtered ריקות). על הבסיס נכשל. |

`flutter test test/personal_notes/`: עברו (כולל `personal_notes_screen_test`). `flutter analyze` נקי, `dart format` ללא שינויים.

## אימות ויזואלי

רינדור `PersonalNotesManagerScreen` מבדיקת widget עם מאגר מזויף (ספר עם הערה + ספר שטעינתו נכשלת), על הבסיס ועל
הענף — הצילומים בענף `pr-screenshots` (תיקייה `1313`): לפני — "ספר שבור" עם ההערה של "ספר תקין"; אחרי — רק "ספר תקין".

## סוויטה מלאה

`flutter test` על הענף (במקביל לסוויטה נוספת ולבניית APK): **12,832 עברו, 25 דולגו, 20 נכשלו**.
- כשלי הבסיס המוכרים (10): release_packaging ×2, compaction ×3, personal_notes_file_backed_book,
  search_scope_menu (flaky), change_location_dialog, shamor_zachor, database_library_provider.
- חדש בבסיס ולא קשור לענף (4): `calendar_print_pdf_test` — `opentype_shaper.dll` חסר במחשב הבדיקה; נכשל זהה על
  `upstream/dev` נקי.
- רעידות עומס (6): text_book_bloc ×5, raised_markers_perf — בריצה חוזרת במכונה שקטה **54 עברו, 0 נכשלו**.
