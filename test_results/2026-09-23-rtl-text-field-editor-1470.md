# issue #1470 — TextField גולמי בעורך הצעת תיקון הטקסט

**ענף:** `fix/rtl-text-field-editor-1470` על `upstream/dev` 780ae3f94 · **פלטפורמה:** macOS 27.0 · **Flutter:** 3.47.2 (זהה ל-CI) · **תאריך:** 23.9.2026

## הבאג
`CLAUDE.md` קובע: *"NEVER use regular `TextField` - it breaks RTL support"*. בכל `lib/`
נותר מופע אחד — `text_book/editing/widgets/text_section_editor_dialog.dart:660`, עורך
הצעת תיקון הטקסט.

זה בדיוק המקום שבו הכלל נחוץ: שדה רב-שורות שמקלידים בו עברית, ושם באגי ה-RTL של
Flutter Desktop מורגשים — חיצים שפועלים הפוך, בחירה שקורסת לכיוון הלא נכון, וסמן
שלא נראה בניווט.

## השורש
לא "מישהו שכח". `RtlTextField` פשוט לא ידע לעשות את מה שהעורך צריך: חסרו לו
`scrollController` ו-`expands`. בלעדיהם אי אפשר שדה שממלא את גובה החלונית וגולל
בסנכרון עם התצוגה המקדימה שלצידו, ולכן נכתב שם `TextField` גולמי.

## התיקון
שני הפרמטרים נוספו ל-`RtlTextField` ומועברים לשדה הפנימי, ואתר הקריאה עבר לעטיפה.

הפער שאילץ לעקוף את העטיפה נסגר **בעטיפה עצמה** ולא הועתק לקובץ הפיצ׳ר — כלומר
התיקון מונע גם את המופע הבא. כבונוס, העורך מקבל עכשיו את כל תיקוני ה-RTL של
`RtlTextField`: ניווט חיצים, בחירה ברמת מילה, תפריט הקשר וניהול הבהוב הסמן.

**שמירה על הפונקציונליות:** `expands` ו-`scrollController` מועברים כפי שהם, ושאר
הפרמטרים של אתר הקריאה (`maxLines: null`, `textAlign`, `style`, `decoration`,
`textAlignVertical`, `focusNode`) כבר נתמכו בעטיפה.

## בדיקות

| בדיקה (issue #1470) | לפני | אחרי |
|---|---|---|
| אין `TextField` גולמי ב-`lib` (סריקה סטטית) | ❌ `text_section_editor_dialog.dart:660` | ✅ |
| `expands` ממלא את הגובה הזמין | ❌ הפרמטר לא היה קיים | ✅ |
| `scrollController` מועבר לשדה הפנימי | ❌ אותה סיבה | ✅ |

הסריקה מחריגה את `lib/widgets/text/rtl_text_field.dart` עצמו — העטיפה בונה בתוכה
`TextField`, וזו כל מטרתה.

`flutter analyze` — No issues found.
`flutter test test/widgets/text/` — 52 עברו · `test/text_book/view/text_correction_editor_test.dart` — 24 עברו.

## סוויטה מלאה מול הבסיס
שתיהן על `upstream/dev 780ae3f94`, עם `--file-reporter=json` להשוואה פר-בדיקה.
כל סוויטה רצה **לבדה** — שלוש סוויטות במקביל על מכונה אחת גרמו ללחץ זיכרון שהאט
אותן פי עשרות.

| | עברו | דולגו | נכשלו |
|---|---|---|---|
| `dev` | 13,962 | 282 | 37 |
| הענף | 13,969 | 282 | 33 |

**אפס כשלים ייחודיים לענף.**

ארבעה כשלים הופיעו רק בהרצת הבסיס, כולם ב-`core/windowing/window_bus_test.dart`.
הרצתי את הקובץ לבדו על `dev` נקי: **14 עברו, 0 נכשלו** — flakes, לא רגרסיה.
