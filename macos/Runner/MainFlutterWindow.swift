import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  // חלון ה-splash הנייטיב (סמל צף שקוף) וערוץ הסגירה שלו.
  private var splashWindow: NSWindow?
  private var splashChannel: FlutterMethodChannel?
  private var splashShownAt: Date?
  private var terminationChannel: FlutterMethodChannel?
  private var isDartCloseHandlingEnabled = false
  private var isDartTerminationAllowed = false

  // אטימות הסמל (~70%) וזמן תצוגה מינימלי (מונע הבזק אם החשיפה מוקדמת).
  private let splashAlpha: CGFloat = 0.70
  private let minDisplaySeconds: TimeInterval = 0.8

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // מציגים מיד את ה-splash הנייטיב (סמל צף) — משוב ויזואלי מיידי.
    showSplash()

    // ערוץ "otzaria/splash": Dart קורא "close" בעת חשיפת החלון הראשי → fade-out.
    let channel = FlutterMethodChannel(
      name: "otzaria/splash",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "close" {
        self?.revealMainWindowAndCloseSplash()
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    splashChannel = channel

    let terminationChannel = FlutterMethodChannel(
      name: "otzaria/macos_termination",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    terminationChannel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "enableCloseHandling":
        self?.isDartCloseHandlingEnabled = true
        result(nil)
      case "allowTermination":
        self?.isDartTerminationAllowed = true
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.terminationChannel = terminationChannel

    // משאירים את החלון הראשי **שקוף לגמרי** (alpha 0) עד החשיפה, במקום
    // orderOut (שלא נדבק ב-macOS — המערכת מציגה את החלון מחדש אחרי awakeFromNib,
    // וכך נראה גם אוברליי ה-splash של Flutter במרכזו). שקוף-לגמרי: החלון נשאר
    // על המסך ומצייר את התוכן (ללא ציור-בזמן-הסתרה בעייתי), אך בלתי-נראה, ולכן
    // נראה רק ה-splash הצף. בחשיפה (ערוץ "close") מחזירים alpha=1.
    self.alphaValue = 0

    super.awakeFromNib()
  }

  /// ⌘Q ו-Quit שולחים `NSApplication.terminate`, שעוקף את ה-delegate של
  /// החלון. כל עוד Dart לא סיים את ה-flush, מחזירים אותו ל-`performClose`,
  /// ש-window_manager מתרגם ל-onWindowClose. לאחר ההיתר המפורש מ-Dart
  /// אפשר להשלים את אותה בקשת terminate בלי להציג שוב את האישור.
  func applicationShouldTerminate() -> NSApplication.TerminateReply {
    guard isDartCloseHandlingEnabled else { return .terminateNow }
    if isDartTerminationAllowed { return .terminateNow }
    performClose(nil)
    return .terminateCancel
  }

  private func showSplash() {
    guard splashWindow == nil, let image = loadSplashIcon(),
      let screen = NSScreen.main
    else { return }

    let size: CGFloat = 160
    let visible = screen.visibleFrame
    let rect = NSRect(
      x: visible.midX - size / 2, y: visible.midY - size / 2,
      width: size, height: size)

    let win = NSWindow(
      contentRect: rect, styleMask: .borderless, backing: .buffered,
      defer: false)
    win.isOpaque = false
    win.backgroundColor = .clear
    win.hasShadow = false
    win.level = .floating
    win.ignoresMouseEvents = true
    win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    win.alphaValue = 0  // מתחיל שקוף עבור fade-in

    let imageView = NSImageView(frame: NSRect(origin: .zero, size: rect.size))
    imageView.image = image
    imageView.imageScaling = .scaleProportionallyUpOrDown
    win.contentView = imageView

    win.orderFrontRegardless()
    splashWindow = win
    splashShownAt = Date()

    // fade-in הדרגתי ל-splashAlpha.
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.39
      win.animator().alphaValue = splashAlpha
    }
  }

  // חושף את החלון הראשי וסוגר את ה-splash *בו-זמנית* (crossfade), כך שהסמל אינו
  // "נשאר" אחרי שהחלון עלה. אוכף זמן תצוגה מינימלי: אם הסגירה הגיעה מוקדם
  // (טעינה מהירה), דוחה את כל החשיפה — לא רק את ה-fade — כדי שהחלון לא יקדים.
  private func revealMainWindowAndCloseSplash() {
    let elapsed = splashShownAt.map { Date().timeIntervalSince($0) } ?? 0
    let delay = max(0, minDisplaySeconds - elapsed)
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      guard let self = self else { return }
      let splash = self.splashWindow
      self.splashWindow = nil
      // crossfade: החלון הראשי נכנס (alpha 0→1) והסמל יוצא (→0) יחד, ומסתיימים
      // באותו רגע — אין "שהיית-יתר" של הסמל מעל החלון.
      NSAnimationContext.runAnimationGroup(
        { context in
          context.duration = 0.18
          self.animator().alphaValue = 1
          splash?.animator().alphaValue = 0
        },
        completionHandler: {
          splash?.orderOut(nil)
        })
    }
  }

  // טוען את iconnew.png מתוך flutter_assets (ב-macOS הם ב-App.framework/Resources).
  private func loadSplashIcon() -> NSImage? {
    let assetPath = "flutter_assets/assets/icon/iconnew.png"
    if let frameworksURL = Bundle.main.privateFrameworksURL,
      let appBundle = Bundle(
        url: frameworksURL.appendingPathComponent("App.framework")),
      let resourceURL = appBundle.resourceURL
    {
      let url = resourceURL.appendingPathComponent(assetPath)
      if let image = NSImage(contentsOf: url) { return image }
    }
    // גיבוי: משאבי ה-bundle הראשי.
    if let resourceURL = Bundle.main.resourceURL {
      let url = resourceURL.appendingPathComponent(assetPath)
      if let image = NSImage(contentsOf: url) { return image }
    }
    return nil
  }
}
