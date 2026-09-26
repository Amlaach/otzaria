import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_asset_scheme.dart';
import 'package:otzaria/plugins/view/webview_environment_holder.dart';

import 'package:otzaria/settings/services/safer_mode_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    WebViewEnvironmentHolder.debugOverrideRuntimeAvailable(null);
    isKioskMode = false;
  });

  group('WebViewEnvironmentHolder.isRuntimeAvailable', () {
    test('override true → מחזיר true', () async {
      WebViewEnvironmentHolder.debugOverrideRuntimeAvailable(true);
      expect(await WebViewEnvironmentHolder.isRuntimeAvailable(), isTrue);
    });

    test('override false → מחזיר false', () async {
      WebViewEnvironmentHolder.debugOverrideRuntimeAvailable(false);
      expect(await WebViewEnvironmentHolder.isRuntimeAvailable(), isFalse);
    });

    test('איפוס override מחזיר את הבדיקה להתנהגות הרגילה', () async {
      WebViewEnvironmentHolder.debugOverrideRuntimeAvailable(false);
      WebViewEnvironmentHolder.debugOverrideRuntimeAvailable(null);
      // ללא override, על פלטפורמה שאינה Windows התוצאה היא true; ב-Windows
      // ללא platform channel הקריאה נכשלת ומוחזר false. בשני המקרים אסור
      // שהקריאה תזרוק חריגה.
      await expectLater(
        WebViewEnvironmentHolder.isRuntimeAvailable(),
        completes,
      );
    });
  });

  group('WebViewEnvironmentHolder environment settings', () {
    test('uses the requested user data folder', () {
      final settings = WebViewEnvironmentHolder.debugEnvironmentSettings(
        r'C:\app-data\webview2',
      );

      expect(settings.userDataFolder, r'C:\app-data\webview2');
    });

    test('requires exclusive access to the user data folder', () {
      final settings = WebViewEnvironmentHolder.debugEnvironmentSettings(
        r'C:\app-data\webview2',
      );

      expect(settings.exclusiveUserDataFolderAccess, isTrue);
    });

    test('registers the plugin asset scheme as a secure origin', () {
      final settings = WebViewEnvironmentHolder.debugEnvironmentSettings(
        r'C:\app-data\webview2',
      );

      final registration = settings.customSchemeRegistrations!.single;
      expect(registration.scheme, pluginAssetScheme);
      expect(registration.treatAsSecure, isTrue);
      expect(registration.hasAuthorityComponent, isTrue);
    });

    test('omits additional browser arguments by default', () {
      isKioskMode = false;
      final settings = WebViewEnvironmentHolder.debugEnvironmentSettings(
        r'C:\app-data\webview2',
      );
      expect(settings.additionalBrowserArguments, isNull);
    });

    test('disables devtools, PDF toolbar, and print preview in kiosk mode', () {
      isKioskMode = true;
      final settings = WebViewEnvironmentHolder.debugEnvironmentSettings(
        r'C:\app-data\webview2',
      );
      expect(
        settings.additionalBrowserArguments,
        '--disable-features=msEdgeDevTools,PdfOopif --disable-print-preview',
      );
    });
  });
}
