/// ריכוז הודעות המערכת (UiSnack) הכלליות והמשותפות.
abstract class CommonMessages {
  // ── העתקה ללוח ──────────────────────────────────────────────────────────
  static const String textCopied = 'הטקסט הועתק ללוח';
  static const String textCopiedShort = 'הטקסט הועתק';
  static const String formattedTextCopied = 'הטקסט המעוצב הועתק ללוח';
  static const String copyError = 'שגיאה בהעתקה';
  static const String formattedCopyError = 'שגיאה בהעתקה מעוצבת';
  static const String textCopyError = 'שגיאה בהעתקת הטקסט';
  static const String clipboardCopyError = 'שגיאה בהעתקה ללוח';
  static const String clipboardUnavailable = 'לא ניתן לגשת ללוח';
  static const String linkCopied = 'הקישור הועתק';
  static const String pathCopied = 'הנתיב הועתק ללוח';
  static const String noTextSelected = 'אנא בחר טקסט להעתקה';
  static const String noContentToCopy = 'אין תוכן להעתקה';
  static const String paragraphCopied = 'הפסקה הועתקה בהצלחה';
  static const String paragraphCopyError = 'שגיאה בהעתקת הפסקה';

  static String copiedToClipboard(String text) => 'הועתק ללוח: $text';

  static String copyErrorWithDetails(Object error) => 'שגיאה בהעתקה: $error';

  // ── ניווט וקישורים ──────────────────────────────────────────────────────
  static const String sectionNotFound = 'הדף לא נמצא בתוכן העניינים';
  static const String bookNotFound = 'הספר איננו קיים';
  static const String textNotFound = 'הטקסט לא נמצא';

  static String openedRef(String ref) => 'נפתח: $ref';

  static String cannotOpenLink(Object error) =>
      'לא ניתן לפתוח את הקישור: $error';

  static String linkOpenError(Object error) => 'שגיאה בפתיחת הקישור: $error';

  static String navigatedToHeader(String header) => 'נווט ל: $header';

  static String cannotNavigateToHeader(String header) =>
      'לא ניתן לנווט לכותרת: $header';

  static String headerNotFoundOpeningStart(String header, String bookTitle) =>
      'לא נמצאה הכותרת "$header" בספר $bookTitle, פותח את תחילת הספר';

  static String openedBookAtHeader(String bookTitle, String header) =>
      'פתח ספר: $bookTitle - $header';

  static String openedBookAtPartialHeader(
    String bookTitle,
    String reachedHeader,
    String missingHeader,
  ) =>
      'פתח ספר: $bookTitle - $reachedHeader. '
      'הכותרת "$missingHeader" לא נמצאה';

  static String navigatedToPartialHeader(
    String reachedHeader,
    String missingHeader,
  ) => 'נווט ל: $reachedHeader. הכותרת "$missingHeader" לא נמצאה';

  static String cannotOpenBook(String bookTitle) =>
      'לא ניתן לפתוח את הספר: $bookTitle';

  // ── חיפוש ───────────────────────────────────────────────────────────────
  static const String noTextSelectedForSearch = 'לא נבחר טקסט לחיפוש';

  // ── הערות ושמירה ────────────────────────────────────────────────────────
  static const String noteCreated = 'ההערה נוצרה והוצבה בסרגל';
  static const String savedSuccessfully = 'השינויים נשמרו בהצלחה';
  static const String cleanupCompleted = 'ניקוי טיוטות הושלם';

  // ── טלפון ───────────────────────────────────────────────────────────────
  static const String cannotOpenPhoneApp = 'לא ניתן לפתוח את אפליקציית הטלפון';
  static const String phoneAppOpenError = 'שגיאה בפתיחת אפליקציית הטלפון';

  // ── ניווט ───────────────────────────────────────────────────────────────
  static const String pressBackAgainToExit = 'לחץ שוב על חזרה ליציאה';

  // ── קיצורי מקשים ────────────────────────────────────────────────────────
  static const String shortcutRequired = 'יש לבחור קיצור';

  static String shortcutAlreadyInUse(String actionName) =>
      'קיצור זה כבר בשימוש עבור: $actionName';

  // ── אבטחה ומצב קיוסק ────────────────────────────────────────────────────
  static const String kioskFileAttachmentBlocked = 'צירוף קבצים חסום במצב קיוסק';
  static const String kioskExternalLinksBlocked = 'פתיחת קישורים חיצוניים חסומה במצב קיוסק';
  static const String kioskSecondaryWindowBlocked = 'פתיחת חלון נוסף חסומה במצב קיוסק';
  static const String kioskFilePickerBlocked = 'פתיחת בורר קבצים חסומה במצב קיוסק';
  static const String kioskFileDownloadBlocked = 'הורדת קבצים חסומה במצב קיוסק';
  static const String fileDownloadCancelled = 'הורדת הקובץ בוטלה';
  static const String kioskPluginInstallBlocked = 'התקנת תוספים חסומה במצב קיוסק';
  static const String kioskDevPluginBlocked = 'טעינת תוספי פיתוח חסומה במצב קיוסק';
  static const String kioskLocalhostPluginBlocked = 'טעינת תוספי localhost חסומה במצב קיוסק';
  static const String kioskPdfPrintBlocked = 'הדפסת PDF מערכתית חסומה במצב קיוסק';
  static const String kioskFileManagerBlocked = 'פתיחת סייר הקבצים חסומה במצב קיוסק';
  static const String kioskProcessLaunchBlocked = 'פתיחת תהליכים חיצוניים חסומה במצב קיוסק';
  static const String kioskFileSaveBlocked = 'שמירת קבצים למערכת ההפעלה חסומה במצב קיוסק';
  static const String kioskOtzarHachochmaBlocked = 'פתיחת תוכנת אוצר החכמה חסומה במצב קיוסק';
  static const String noPhysicalPrinterConnected = 'אין מדפסת פיזית מחוברת בעמדה זו';
  static const String kioskSoftwareUpdateBlocked = 'עדכון תוכנה חסום במצב קיוסק';
}
