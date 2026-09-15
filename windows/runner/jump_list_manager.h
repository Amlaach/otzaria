#ifndef RUNNER_JUMP_LIST_MANAGER_H_
#define RUNNER_JUMP_LIST_MANAGER_H_

#include <windows.h>

namespace jump_list {

// רושם את קטגוריית "משימות" ב-Jump List של שורת המשימות: פריט "חלון חדש"
// שמריץ את אוצריא עם `otzaria://window/new`.
//
// חובה לקרוא מ-thread שאיתחל COM. מחזיר true בהצלחה.
bool AddUserTasks();

// כמו [AddUserTasks], אך על thread עובד עם STA משלו, וחוזר מיד.
//
// ⚠️ אסור להריץ את הרישום על ה-UI thread: CommitList של ה-Shell נמשך
// במחשבים מסוימים 30–180 שניות, ומאחר שה-isolate של Dart רץ על אותו thread,
// החלון הראשי לא היה מופיע כל אותו זמן (issue #1192).
void AddUserTasksAsync();

// ממתין עד [timeout_ms] לסיום הרישום שרץ ברקע; לקריאה לפני היציאה מהתהליך.
void WaitForPendingTasks(DWORD timeout_ms);

}  // namespace jump_list

#endif  // RUNNER_JUMP_LIST_MANAGER_H_
