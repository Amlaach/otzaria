import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/plugin_messages.dart';
import 'package:otzaria/plugins/services/plugin_download_handler.dart';

void main() {
  test('Windows מסתיר את חלונית WebView2 בלי לבטל את ההורדה', () {
    final response = PluginDownloadHandler.responseFor(isWindows: true);

    expect(response, isNotNull);
    expect(response!.handled, isTrue);
    expect(response.action, isNull);
  });

  test('פלטפורמה שאינה Windows אינה משנה את מסלול ההורדה', () {
    expect(
      PluginDownloadHandler.responseFor(isWindows: false),
      isNull,
    );
  });

  test('ההודעה מתארת התחלה ולא הצלחה שטרם התרחשה', () {
    expect(PluginMessages.fileDownloadStarted, contains('החלה'));
    expect(PluginMessages.fileDownloadStarted, isNot(contains('נשמר')));
  });
}
