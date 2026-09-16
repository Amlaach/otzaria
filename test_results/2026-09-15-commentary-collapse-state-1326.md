# issue #1326 — כיווץ המפרשים אבד במעבר ללשונית קישורים/הערות וחזרה

תאריך: 2026-09-15 | ענף: `fix/commentary-collapse-state-1326` | בסיס: `upstream/dev` (588721404) | קומיט אימות: `9ad53aac5`

## הבאג שאומת

בחלונית המפרשים עם הלשוניות (`TabbedCommentaryPanel`): "כווץ הכל" או כיווץ קבוצה, מעבר ל"קישורים" או
"הערות" וחזרה — כל המפרשים נפתחו מחדש. `TabBarView` משמיד את ה-State של לשונית לא-פעילה, ומצב הכיווץ
(`_expansionStates`, `_allExpanded`) חי ב-`CommentaryListBaseState`.

## התיקון

`CommentaryListBaseState` עם `AutomaticKeepAliveClientMixin` (`wantKeepAlive => true`, `super.build`
בתחילת `build`) — הכיווץ, החיפוש הפנימי ומיקום הגלילה נשמרים במעבר בין הלשוניות.

## בדיקות

| קובץ | מה נבדק |
|---|---|
| `test/text_book/view/commentary_collapse_survives_tab_switch_test.dart` | חדש, "(issue #1326)": `CommentaryListBase` בתוך `TabBarView`, כיווץ קבוצה, מעבר ללשונית אחרת וחזרה — הקבוצה נשארת מכווצת. על הבסיס נכשל (הקבוצה נפתחת). |

`flutter test test/text_book/view/`: עברו. `flutter analyze` נקי, `dart format` ללא שינויים.

## אימות ויזואלי

רינדור מבדיקת widget של `CommentaryListBase` בתוך `TabBarView` (גופנים אמיתיים), על הבסיס ועל הענף: "כווץ הכל",
מעבר ללשונית השנייה וחזרה — לפני: המפרש נפתח מחדש; אחרי: הכיווץ נשמר. הצילומים בענף `pr-screenshots` (תיקייה `1326`).

## סוויטה מלאה

`flutter test` על הענף (במקביל לשתי סוויטות נוספות ולבניית Windows): **12,821 עברו, 25 דולגו, 31 נכשלו**.
- כשלי הבסיס המוכרים (10): release_packaging ×2, compaction ×3, personal_notes_file_backed_book,
  search_scope_menu (flaky), change_location_dialog, shamor_zachor, database_library_provider.
- חדש בבסיס ולא קשור לענף (4): `calendar_print_pdf_test` — `opentype_shaper.dll` חסר במחשב הבדיקה
  (נוסף ב-dev ב-afa4de491); נכשל זהה על `upstream/dev` נקי.
- רעידות עומס (17): text_book_bloc ×9, visible_indices ×3, update_links_sequential, settings_bloc,
  nikud_search (performance), raised_markers_perf, hebrew_book_download — בריצה חוזרת בבידוד עברו
  visible_indices ×3, update_links_sequential, nikud_search, hebrew_book_download; text_book_bloc,
  settings_bloc ו-raised_markers_perf בריצה חוזרת במכונה שקטה — **עברו כולם** (84 + 31).
