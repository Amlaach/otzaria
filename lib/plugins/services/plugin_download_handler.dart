import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:otzaria/core/messages/plugin_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';

/// מטפל בהורדות WebView2 בלי להציג את חלונית ההורדות המובנית.
abstract final class PluginDownloadHandler {
  static bool get isSupported => Platform.isWindows;

  /// מודיע שההורדה התחילה ומסתיר את חלונית WebView2 בלי לבטל את ההורדה.
  /// במצב קיוסק — מבטל את ההורדה לחלוטין.
  static Future<DownloadStartResponse?> onDownloadStarting(
    InAppWebViewController controller,
    DownloadStartRequest request,
  ) async {
    final response = responseFor(
      isWindows: Platform.isWindows,
      isKiosk: isKioskMode,
    );
    if (response != null) {
      if (isKioskMode) {
        UiSnack.show('הורדת קבצים חסומה במצב קיוסק');
      } else {
        UiSnack.show(PluginMessages.fileDownloadStarted);
      }
    }
    return response;
  }

  /// בונה את תשובת WebView2; בפלטפורמות אחרות אין לשנות את מסלול ההורדה.
  @visibleForTesting
  static DownloadStartResponse? responseFor({
    required bool isWindows,
    bool isKiosk = false,
  }) {
    if (isKiosk) {
      return DownloadStartResponse(
        handled: true,
        action: DownloadStartResponseAction.CANCEL,
      );
    }
    return isWindows ? DownloadStartResponse(handled: true) : null;
  }
}
