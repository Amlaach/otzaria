import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private let externalActivationQueueFileName = "pending_external_activations.jsonl"

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let window = sender.windows.first(where: { $0 is MainFlutterWindow }) as? MainFlutterWindow else {
      return .terminateNow
    }
    return window.applicationShouldTerminate()
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      let scheme = url.scheme?.lowercased()
      if scheme == "otzaria" {
        enqueueExternalActivation(url)
      } else if scheme == "file"
        && url.pathExtension.lowercased() == "otzplugin" {
        if let installUrl = buildLocalPluginInstallUrl(forFileAt: url) {
          enqueueExternalActivation(installUrl)
        }
      }
    }

    super.application(application, open: urls)
  }

  /// בונה URI פנימי `otzaria://plugin/install-local?path=<absolute-path>` שתואם
  /// לפורמט ש-`ExternalUriRouter` ב-Dart מצפה לו עבור התקנת תוסף מקובץ מקומי.
  private func buildLocalPluginInstallUrl(forFileAt fileUrl: URL) -> URL? {
    var components = URLComponents()
    components.scheme = "otzaria"
    components.host = "plugin"
    components.path = "/install-local"
    components.queryItems = [URLQueryItem(name: "path", value: fileUrl.path)]
    return components.url
  }

  private func enqueueExternalActivation(_ url: URL) {
    do {
      let queueFileURL = try externalActivationQueueFileURL()
      try FileManager.default.createDirectory(
        at: queueFileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: nil
      )

      let payload: [String: String] = [
        "uri": url.absoluteString,
        "createdAt": ISO8601DateFormatter().string(from: Date()),
      ]
      let recordData = try JSONSerialization.data(withJSONObject: payload)
      var lineData = recordData
      lineData.append(Data("\n".utf8))

      if FileManager.default.fileExists(atPath: queueFileURL.path) {
        let fileHandle = try FileHandle(forWritingTo: queueFileURL)
        defer {
          try? fileHandle.close()
        }

        fileHandle.seekToEndOfFile()
        fileHandle.write(lineData)
      } else {
        try lineData.write(to: queueFileURL, options: .atomic)
      }
    } catch {
      NSLog("Failed to enqueue external activation: \(error)")
    }
  }

  private func externalActivationQueueFileURL() throws -> URL {
    guard let appSupportDirectory = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
    ).first else {
      throw NSError(
        domain: "OtzariaAppDelegate",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Application Support directory is unavailable"],
      )
    }

    return appSupportDirectory
      .appendingPathComponent("otzaria", isDirectory: true)
      .appendingPathComponent(externalActivationQueueFileName, isDirectory: false)
  }
}
