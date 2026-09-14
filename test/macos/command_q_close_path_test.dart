import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ⌘Q מגיע ל-NSApplication ולא ל-NSWindow, ולכן אי אפשר לכסות אותו בבדיקת
/// widget. בדיקת החוזה נועלת את הגשר בין ה-runner למסלול הסגירה של Dart.
void main() {
  final appDelegate = File('macos/Runner/AppDelegate.swift').readAsStringSync();
  final mainWindow = File(
    'macos/Runner/MainFlutterWindow.swift',
  ).readAsStringSync();
  final listener = File('lib/core/window_listener.dart').readAsStringSync();
  final bootstrap = File('lib/main.dart').readAsStringSync();

  test('⌘Q מנותב ל-onWindowClose עד ש-Dart מתיר סיום', () {
    expect(appDelegate, contains('applicationShouldTerminate('));
    expect(appDelegate, contains('window.applicationShouldTerminate()'));
    expect(mainWindow, contains('otzaria/macos_termination'));
    expect(mainWindow, contains('case "enableCloseHandling"'));
    expect(mainWindow, contains('case "allowTermination"'));
    expect(mainWindow, contains('performClose(nil)'));
    expect(mainWindow, contains('return .terminateCancel'));
    expect(mainWindow, contains('return .terminateNow'));
    expect(bootstrap, contains('AppWindowListener.enableMacOSCloseHandling()'));

    final allow = listener.indexOf('allowMacOSApplicationTermination();');
    final quit = listener.indexOf('await _window.quitApplication();');
    expect(allow, greaterThanOrEqualTo(0));
    expect(quit, greaterThan(allow));
  });
}
