# issue #1399 — קריסת Windows (flutter_windows.dll) בעקבות עץ נגישות שנשבר: tooltip בתוך עוגן overlay אחר

**ענף:** `fix/windows-a11y-crash-1399` על `upstream/dev` 82d67bc80 · **worktree:** otzaria-wt6 · **תאריך:** 17.9.2026

## השורש

`Tooltip` חיצוני אינו יוצר צומת סמנטיקה משלו — הודעתו ועוגן ה-`OverlayPortal` של הבלון
(`traversalParentIdentifier`) מתמזגים לצומת הסמנטיקה הקרוב מעליו. כשהצומת הזה כבר נושא
עוגן אחר, `SemanticsConfiguration.absorb` שומר עוגן אחד בלבד (`??=`) והשני נשמט בשקט;
`isCompatibleWith` אינו מזהה התנגשות כזו. כשהבלון של העוגן שנשמט נפתח, צומת ה-overlay
נשלח למנוע עם `traversalParent = -1` ואף צומת לא מצהיר עליו כילד —
`ui::AXTree::Unserialize` דוחה את העדכון (`N will not be in the tree and is not the new root`),
עץ הנגישות של Windows קופא, ובמעבר הפוקוס הבא לקוח UIA פונה לצמתים שכבר אינם:
קריסה ב-`flutter_windows.dll+0x1e220` = `ui::AXPlatformNodeBase::GetDelegate()` (getter מקופל ICF,
`mov rax,[rcx+0x10]`), או תקיעה (מסך שחור) בדיבאג.

שלושה מקומות בתוכנה עם שני עוגנים באותו צומת:

| מקום | העוגן החיצוני | העוגן שנשמט |
|---|---|---|
| ה-X של כרטיסיה (`custom_title_bar.dart`) | tooltip כותרת הכרטיסיה (`TabTitleTooltip`) | `Tooltip("CTRL + W")` סביב `IconButton` |
| ה-X של חלונית בלשונית מפוצלת | כנ"ל | `Tooltip("סגור חלונית")` |
| "ברירת מחדל לחיפוש חדש/רגיל" (`advanced_search_controls.dart`, `search_dialog.dart`) | עוגן התפריט של `MenuAnchor` | `Tooltip` סביב `ActionButton.ghost` ב-`builder` |

## התיקון

- ה-X של כרטיסיה/חלונית: `IconButton.tooltip` במקום `Tooltip` עוטף — Material בונה את ה-Tooltip
  *בתוך* מכולת הסמנטיקה של הכפתור (`ButtonStyleButton.build`), ולכן הבלון שייך לצומת הכפתור.
  `preferBelow: false` נשמר דרך `TooltipTheme`.
- `ActionButton` מקבל `tooltip` שבונה `Semantics(container: true)` + `Tooltip`; שני כפתורי
  "ברירת מחדל" בתוך `MenuAnchor.builder` עוברים אליו.
- סריקה של כל `lib` לתבנית "עוגן overlay בתוך עוגן" (Tooltip/MenuAnchor/OverlayPortal/Slider…) —
  אין מקומות נוספים.

## בדיקות

**מקליט עדכוני סמנטיקה** — `test/helpers/semantics_update_recorder.dart`: עוטף את
`SemanticsUpdateBuilder` ובודק על כל עדכון את האינווריאנט של `ui::AXTree`. מאפשר לתפוס את
העדכון הפגום בבדיקת widget רגילה, בלי קורא מסך.

| בדיקה | לפני התיקון | אחרי |
|---|---|---|
| `test/navigation/tab_close_button_tooltip_semantics_test.dart` — ריחוף על ה-X של כרטיסיה עם tooltip כותרת (issue #1399) | ❌ `20 will not be in the tree and is not the new root` | ✅ |
| שם — ה-X של חלונית בלשונית מפוצלת (issue #1399) | ❌ `21 will not be in the tree…` | ✅ |
| `test/search/advanced_search_controls_tooltip_semantics_test.dart` — ריחוף על "ברירת מחדל לחיפוש חדש" בתוך MenuAnchor (issue #1399) | ❌ `31 will not be in the tree…` | ✅ |
| `test/widgets/controls/action_button_tooltip_semantics_test.dart` — 2 בדיקות ל-`ActionButton.tooltip` (issue #1399) | (API חדש) | ✅ |
| `test/navigation/custom_title_bar_test.dart` — הותאם finder אחד (ה-Tooltip הוא צאצא של ה-IconButton) | — | ✅ 84/84 |
| `test/navigation/reading_tab_strip_test.dart` | — | ✅ |

`flutter analyze` על כל הקבצים שנגעו בהם — No issues found. `dart format` — ללא שינויים.

### סוויטה מלאה (otzaria-wt6, 19:22 דק')

`12952` בדיקות, `14` כשלים — כולם קיימים גם על dev נקי 82d67bc80 (אף אחד לא קשור לשינוי):

- בסיס סביבתי מוכר: `installer/release_packaging_test` ×2, `migration/sync/file_sync_service_compaction_test` ×3,
  `personal_notes/personal_notes_file_backed_book_test` (DOCX), `data_providers/database_library_provider_test`,
  `tools/calendar/helpers/calendar_print_pdf_test` ×4 (`opentype_shaper.dll` חסר).
- אומתו בבידוד **גם על 82d67bc80 נקי** ונכשלים שם באותו אופן: `search/search_scope_menu_search_actions_test`
  ("ריחוף חושף 'רק'"), `settings/dialogs/change_location_dialog_test` ("הרשומה עבור ה-uninstaller"),
  `shamor_zachor/shamor_zachor_data_provider_test` ("falls back to sqlite provider").

## אימות חי (Windows, build debug, גשר הנגישות פעיל דרך לקוח MSAA)

| | לפני (dev, otzaria-wt4) | אחרי (הענף, otzaria-wt6) |
|---|---|---|
| ריחוף על ה-X של הכרטיסיה "חיפוש: VI GO KCSS HAFUI" (כותרת נחתכת → tooltip) | 2× `Failed to update ui::AXTree, error: 75 will not be in the tree and is not the new root` | 0 שגיאות |
| הקלדת `VI GO KCSS HAFUI` בשדה + Tab להצעה | העץ קפוא: 12 שגיאות מצטברות | 0 שגיאות, `Responding=True` |

הקריסה עצמה דורשת לקוח UIA שפונה לעץ ברגע מעבר הפוקוס (אצל המדווח — שלוש קריסות ב-Event Viewer באותו
היסט `0x1e220`); כאן מודגם המנגנון שמקדים אותה — דחיית העדכון וקיפאון העץ — ונעלם עם התיקון.

## חוב למעלה (Flutter)

הבאג הבסיסי הוא במסגרת: `SemanticsConfiguration.isCompatibleWith` אינו מפריד שתי קונפיגורציות
עם `traversalParentIdentifier` שונים, ו-`absorb` משמיט אחד מהם בשקט. דיווחים קרובים:
flutter/flutter#182444, flutter/flutter#190357, flutter/flutter#175041.
