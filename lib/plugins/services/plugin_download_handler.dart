import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:otzaria/core/messages/plugin_messages.dart';
import 'package:otzaria/core/ui_snack.dart';

/// מטפל בהורדות WebView2 בלי להציג את חלונית ההורדות המובנית.
abstract final class PluginDownloadHandler {
  static bool get isSupported => Platform.isWindows;

  /// מודיע שההורדה התחילה ומסתיר את חלונית WebView2 בלי לבטל את ההורדה.
  static Future<DownloadStartResponse?> onDownloadStarting(
    InAppWebViewController controller,
    DownloadStartRequest request,
  ) async {
    final response = responseFor(isWindows: Platform.isWindows);
    if (response != null) {
      UiSnack.show(PluginMessages.fileDownloadStarted);
    }
    return response;
  }

  /// בונה את תשובת WebView2; בפלטפורמות אחרות אין לשנות את מסלול ההורדה.
  @visibleForTesting
  static DownloadStartResponse? responseFor({required bool isWindows}) {
    return isWindows ? DownloadStartResponse(handled: true) : null;
  }
}
