# issue #1189 — "ספריה" לעומת "ספרייה": כתיב לא אחיד במחרוזות הממשק

תאריך: 2026-09-15 | ענף: `fix/library-spelling-1189` | בסיס: `upstream/dev` (588721404) | קומיט אימות: `27dd13c8e`

## הבאג שאומת

התפריט הראשי כתב "ספרייה" (הכתיב התקני), ופס הכותרת, לשונית ההגדרות, כפתור "הגדרת ספריה",
מסך הספרייה הריקה ("בחר מיקום או הורד ספריה") ותת-כותרת הספריות החיצוניות כתבו "ספריה".

## התיקון

- כל מחרוזות הממשק עברו ל"ספרייה": `empty_library_screen.dart`, `custom_title_bar.dart`
  (`settingsText('ספרייה', context: 'titleBar')`), `library_settings_panel.dart`,
  `settings_search_results_view.dart`, `library_settings_tab.dart` ("הגדרת ספרייה"), `settings_screen.dart`.
- `settings_en.arb`: המפתחות עודכנו (הכפילות "ספריה"/"ספרייה" אוחדה ל-"Library"; ההקשר `titleBar` נשמר);
  הקטלוג נוצר מחדש. מילות החיפוש של ההגדרות כוללות את שני הכתיבים.
- ציפיות בבדיקות קיימות עודכנו לכתיב החדש (`empty_library_screen_test`, `settings_variable_labels_test`,
  `short_window_state_screens_test`).

## בדיקות

| קובץ | מה נבדק |
|---|---|
| `test/settings/l10n/library_spelling_consistency_test.dart` | חדש, "(issue #1189)": אף מפתח ARB / מחרוזת ממשק אינו מכיל את הכתיב החסר "ספריה". על הבסיס נכשל. |

`flutter test test/settings/l10n/`: **145 עברו**. `flutter analyze` נקי, `dart format` ללא שינויים.

## אימות ויזואלי

התוכנה עצמה (בניית debug של הבסיס ושל הענף ב-Windows): פס הכותרת של מסך הספרייה ורשימת לשוניות ההגדרות —
לפני "ספריה", אחרי "ספרייה". הצילומים בענף `pr-screenshots` (תיקייה `1189`).

## סוויטה מלאה

`flutter test` על הענף (במקביל לשתי סוויטות נוספות ולבניית Windows): **12,822 עברו, 25 דולגו, 30 נכשלו**.
- כשלי הבסיס המוכרים (10): release_packaging ×2, compaction ×3, personal_notes_file_backed_book,
  search_scope_menu (flaky), change_location_dialog, shamor_zachor, database_library_provider.
- חדש בבסיס ולא קשור לענף (4): `calendar_print_pdf_test` — `opentype_shaper.dll` חסר במחשב הבדיקה
  (נוסף ב-dev ב-afa4de491); נכשל זהה על `upstream/dev` נקי.
- קשור לתיקון (3): `short_window_state_screens_test` חיפש את הכתיב הישן "הורד ספריה" — הציפייה עודכנה
  (קומיט `d077fd956`), ובריצה חוזרת עובר.
- רעידות עומס (13): text_book_bloc ×9, raised_markers_perf, commentary_links_no_not_found_flash,
  plugin_background_host, hebrew_book_download — בריצה חוזרת בבידוד עברו; text_book_bloc (timeouts
  "TextBookLoaded not met within 5s" בזמן שסוויטות אחרות רצו) בריצה חוזרת במכונה שקטה — **73 עברו, 0 נכשלו**.
