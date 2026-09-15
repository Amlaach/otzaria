#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>

#include <functional>
#include <memory>
#include <string>

// בקשה לסגור את החלון.
//
// ⚠️ **החלון מוסתר, לא נהרס** — וזו החלטה שנכפתה על ידי מדידה.
//
// `DestroyWindow` הורס את מנוע ה-Flutter של החלון. כשכל המנועים חולקים
// את ה-thread הראשי, הריסת אחד מהם בזמן שאחר חי מפילה את התהליך —
// נמדד: **כל** סגירת חלון גרמה ל-segfault, בין אם הראשון ובין אם משני,
// וגם כשההריסה נדחתה לאיטרציה הבאה של לולאת ההודעות. כלומר זו אינה
// ריאנטרנטיות אלא אי-בטיחות של ההריסה עצמה בתצורה הזו.
//
// בספייק, כשלכל מנוע היה thread ייעודי, הריסה **כן** עבדה נקי
// (ראו docs/multi-window.md). אבל יצירת מנוע על thread ייעודי מפילה
// את התהליך כשחלון אחר כבר רץ. שתי הדרישות סותרות, ולכן: יוצרים על
// ה-thread הראשי, ולא הורסים עד ליציאת התהליך.
//
// **המחיר, במפורש:** המנוע של חלון סגור נשאר בזיכרון עד סגירת התוכנה.
// עם תקרה של ארבעה חלונות זה חסום, אבל זהו חוב פתוח — הפתרון הנכון הוא
// thread לכל מנוע, והוא חסום ביצירה.
constexpr UINT kMsgDeferredDestroy = WM_APP + 0x102;

// סגנון שמונע מחלון להיות מופעל, עד שהוא נחשף.
//
// ⚠️ **זהו התיקון ל"מריבת הפוקוסים".** חלון אוצריא נוצר מוסתר ונחשף רק
// בפריים הראשון, אבל מנוע Flutter קורא `SetFocus` על ה-view שלו בזמן
// היצירה — ו-`SetFocus` על ילד מפעיל את החלון העליון. כלומר חלון בלתי-נראה
// חטף את ההפעלה, Windows החזיר אותה לחלון הקודם, החשיפה חטפה שוב, וחוזר
// חלילה: נמדדה תנודה של ארבע החלפות תוך 200ms בין החלון החדש לחלון הראשי.
//
// `WS_EX_NOACTIVATE` פשוט מוציא את החלון מהמשחק עד שיש מה להראות. הוא
// מוסר ב-[Win32Window::AllowActivation] רגע לפני ההצגה.
constexpr DWORD kNoActivateUntilRevealed = WS_EX_NOACTIVATE;

// A class abstraction for a high DPI-aware Win32 Window. Intended to be
// inherited from by classes that wish to specialize with custom
// rendering and input handling
class Win32Window {
 public:
  struct Point {
    unsigned int x;
    unsigned int y;
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
  };

  struct Size {
    unsigned int width;
    unsigned int height;
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };

  Win32Window();
  virtual ~Win32Window();

  // Creates a win32 window with |title| that is positioned and sized using
  // |origin| and |size|. New windows are created on the default monitor. Window
  // sizes are specified to the OS in physical pixels, hence to ensure a
  // consistent size this function will scale the inputted width and height as
  // as appropriate for the default monitor. The window is invisible until
  // |Show| is called. Returns true if the window was created successfully.
  // [extended_style] נוסף לסגנונות המורחבים של החלון. ראו
  // [kNoActivateUntilRevealed].
  bool Create(const std::wstring& title, const Point& origin, const Size& size,
              DWORD extended_style = 0);

  // מסיר את [WS_EX_NOACTIVATE], כדי שהחלון יוכל להיות מופעל.
  //
  // ⚠️ חייב לקרות **לפני** שמציגים אותו, אחרת ההצגה לא תפעיל אותו.
  //
  // סטטי ומקבל `HWND`, כי מסלול החשיפה רץ בקולבק שמחזיק את ה-handle בלבד
  // (מצביע לחלון עלול להיות תלוי עד שהפריים הראשון מגיע).
  static void AllowActivation(HWND window);

  // רושם שהמשתמש בחר את [window] בלחיצה.
  static void NoteUserActivation(HWND window);

  // החלון האחרון שהופעל (עכבר או מקלדת), או nullptr אם אין כזה חי.
  //
  // ⚠️ מקור האמת לניתוב `otzaria://`: `LastActiveWindow` בצד Dart הוא
  // static פר-isolate, ולכן כל חלון רואה רק את עצמו.
  static HWND LastActivatedWindow();

  // האם יש לחסום הפעלה של [window] כרגע.
  //
  // ## ⚠️ למה נדרש שער כזה בכלל
  //
  // עם שני מנועי Flutter בתהליך אחד, החלון שמחזיק את המיקוד **אוכף אותו
  // בחזרה**: המשתמש לוחץ על החלון השני, הוא מופעל (`WA_CLICKACTIVE`),
  // ותוך ~30ms המנוע של החלון הראשון מפעיל אותו מחדש. נמדד ב-stack:
  // הקריאה מגיעה מ-`flutter_windows.dll` עם קוד Dart מתחתיה — לא מהקוד
  // שלנו, לא מפלאגין, וגם לא ב-`WM_ACTIVATE` שלנו (נבדק בנפרד עם
  // ההצבה מנוטרלת). ההתנהגות סימטרית: מי שמחזיק פוקוס מסרב לוותר.
  //
  // אירוע ה-blur מגיע ל-Dart אסינכרונית, ולכן שחרור מיקוד מצד Flutter
  // מגיע מאוחר מדי. השער כאן הוא המקום היחיד שפועל **סינכרונית**.
  //
  // המדיניות: בחירה מפורשת של המשתמש (לחיצה) מוגנת לחצי שנייה מפני
  // הפעלה תוכניתית של חלון אוצריא **אחר**. הפעלה שהמשתמש יזם, והפעלה של
  // חלונות שאינם שלנו, אינן נוגעות בשער.
  static bool ShouldVetoActivation(HWND window);

  // יוצר חלון במסגרת שנתונה ב**פיקסלים פיזיים**, בלי שום המרת DPI.
  //
  // ⚠️ קיים כי [Create] מכפיל גם את המיקום וגם את הגודל ב-scale factor,
  // כלומר הוא מצפה ליחידות **לוגיות**. מיקומים שמגיעים מגרירה
  // (`GetWindowRect`, `GetCursorPos`, מסגרת שההצמדה נתנה) הם פיזיים,
  // והעברתם ל-[Create] הכפילה אותם שוב: במסך 150% חלון שנגרר ל-x=1000
  // נוצר ב-1500, והצמדה לחצי מסך של 960px נתנה חלון של 1440px. במסך יחיד
  // ב-100% שום דבר מזה אינו נראה.
  bool CreatePhysical(const std::wstring& title, const RECT& frame,
                      DWORD extended_style = 0);

  // Show the current window. Returns true if the window was successfully shown.
  bool Show();

  // Release OS resources associated with window.
  void Destroy();

  // Inserts |content| into the window tree.
  void SetChildContent(HWND content);

  // Returns the backing Window handle to enable clients to set icon and other
  // window properties. Returns nullptr if the window has been destroyed.
  HWND GetHandle();

  // If true, closing this window will quit the application.
  void SetQuitOnClose(bool quit_on_close);

  // Return a RECT representing the bounds of the current client area.
  RECT GetClientArea();

 protected:
  // Processes and route salient window messages for mouse handling,
  // size change and DPI. Delegates handling of these to member overloads that
  // inheriting classes can handle.
  virtual LRESULT MessageHandler(HWND window,
                                 UINT const message,
                                 WPARAM const wparam,
                                 LPARAM const lparam) noexcept;

  // Called when CreateAndShow is called, allowing subclass window-related
  // setup. Subclasses should return false if setup fails.
  virtual bool OnCreate();

  // Called when Destroy is called.
  virtual void OnDestroy();

  // נקרא כשהחלון הוסתר במקום להיהרס. ראו `kMsgDeferredDestroy`.
  virtual void OnWindowHidden();

 private:
  friend class WindowClassRegistrar;

  // OS callback called by message pump. Handles the WM_NCCREATE message which
  // is passed when the non-client area is being created and enables automatic
  // non-client DPI scaling so that the non-client area automatically
  // responds to changes in DPI. All other messages are handled by
  // MessageHandler.
  static LRESULT CALLBACK WndProc(HWND const window,
                                  UINT const message,
                                  WPARAM const wparam,
                                  LPARAM const lparam) noexcept;

  // Retrieves a class instance pointer for |window|
  static Win32Window* GetThisFromHandle(HWND const window) noexcept;

  // Update the window frame's theme to match the system theme.
  static void UpdateTheme(HWND const window);

  bool quit_on_close_ = false;

  // window handle for top level window.
  HWND window_handle_ = nullptr;

  // window handle for hosted content.
  HWND child_content_ = nullptr;
};

#endif  // RUNNER_WIN32_WINDOW_H_
