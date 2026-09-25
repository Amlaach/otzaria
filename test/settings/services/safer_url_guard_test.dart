import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/dialogs/safer_mode_password_dialog.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';
import 'package:otzaria/settings/services/safer_url_guard.dart';

class _MockSettingsRepository extends Mock implements SettingsRepository {}

class _MockSettingsBloc extends Mock implements SettingsBloc {}

class _RecordingUrlLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  final List<String> launched = [];

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }

  @override
  LinkDelegate? get linkDelegate => null;
}

void main() {
  late _RecordingUrlLauncher launcher;
  late UrlLauncherPlatform previousLauncher;
  late _MockSettingsRepository repository;
  late _MockSettingsBloc settingsBloc;

  setUp(() {
    launcher = _RecordingUrlLauncher();
    previousLauncher = UrlLauncherPlatform.instance;
    UrlLauncherPlatform.instance = launcher;

    repository = _MockSettingsRepository();
    settingsBloc = _MockSettingsBloc();
    isKioskMode = false;
  });

  tearDown(() {
    UrlLauncherPlatform.instance = previousLauncher;
    isKioskMode = false;
  });

  Widget createTestWidget({
    required Widget child,
    required bool protectedModeEnabled,
    required bool hasPassword,
  }) {
    when(() => repository.hasProtectedModePassword()).thenReturn(hasPassword);
    when(() => repository.verifyProtectedModePassword(any()))
        .thenAnswer((invocation) {
      final pwd = invocation.positionalArguments[0] as String;
      return pwd == '1234';
    });

    final state = SettingsState.initial().copyWith(
      protectedModeEnabled: protectedModeEnabled,
      protectedModePasswordSet: hasPassword,
    );
    when(() => settingsBloc.state).thenReturn(state);
    when(() => settingsBloc.stream).thenAnswer((_) => const Stream.empty());

    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<SettingsRepository>.value(value: repository),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: Scaffold(body: child),
        ),
      ),
    );
  }

  group('saferLaunchUrl - Kiosk mode (--kiosk / --safer)', () {
    testWidgets('חוסם פתיחת קישור חיצוני (http/https) ללא דיאלוג', (tester) async {
      isKioskMode = true;

      late BuildContext testContext;
      await tester.pumpWidget(
        createTestWidget(
          protectedModeEnabled: true,
          hasPassword: true,
          child: Builder(
            builder: (ctx) {
              testContext = ctx;
              return const SizedBox();
            },
          ),
        ),
      );

      final result = await saferLaunchUrl(
        testContext,
        Uri.parse('https://example.com'),
      );

      expect(result, isFalse);
      expect(launcher.launched, isEmpty);
      // מוודא שלא נפתח דיאלוג סיסמה
      expect(find.byType(SaferModePasswordDialog), findsNothing);
    });

    testWidgets('חוסם קישור mailto במצב קיוסק', (tester) async {
      isKioskMode = true;

      late BuildContext testContext;
      await tester.pumpWidget(
        createTestWidget(
          protectedModeEnabled: true,
          hasPassword: true,
          child: Builder(
            builder: (ctx) {
              testContext = ctx;
              return const SizedBox();
            },
          ),
        ),
      );

      final result = await saferLaunchUrl(
        testContext,
        Uri.parse('mailto:support@example.com'),
      );

      expect(result, isFalse);
      expect(launcher.launched, isEmpty);
    });

    testWidgets('חוסם קישור file ו-ms-settings במצב קיוסק', (tester) async {
      isKioskMode = true;

      late BuildContext testContext;
      await tester.pumpWidget(
        createTestWidget(
          protectedModeEnabled: true,
          hasPassword: true,
          child: Builder(
            builder: (ctx) {
              testContext = ctx;
              return const SizedBox();
            },
          ),
        ),
      );

      final fileResult = await saferLaunchUrl(
        testContext,
        Uri.parse('file:///C:/Windows/explorer.exe'),
      );
      final msResult = await saferLaunchUrl(
        testContext,
        Uri.parse('ms-settings:appsfeatures'),
      );

      expect(fileResult, isFalse);
      expect(msResult, isFalse);
      expect(launcher.launched, isEmpty);
    });
  });

  group('saferLaunchUrl - מצב רגיל (ללא סייפר)', () {
    testWidgets('מאפשר פתיחת קישור חיצוני ישירות', (tester) async {
      late BuildContext testContext;
      await tester.pumpWidget(
        createTestWidget(
          protectedModeEnabled: false,
          hasPassword: false,
          child: Builder(
            builder: (ctx) {
              testContext = ctx;
              return const SizedBox();
            },
          ),
        ),
      );

      final result = await saferLaunchUrl(
        testContext,
        Uri.parse('https://example.com'),
      );

      expect(result, isTrue);
      expect(launcher.launched, ['https://example.com']);
      expect(find.byType(SaferModePasswordDialog), findsNothing);
    });
  });

  group('saferLaunchUrl - מצב סייפר פעיל (דרוש אימות סיסמה)', () {
    testWidgets('מציג דיאלוג סיסמה וחוסם אם המשתמש ביטל', (tester) async {
      late BuildContext testContext;
      await tester.pumpWidget(
        createTestWidget(
          protectedModeEnabled: true,
          hasPassword: true,
          child: Builder(
            builder: (ctx) {
              testContext = ctx;
              return const SizedBox();
            },
          ),
        ),
      );

      final futureResult = saferLaunchUrl(
        testContext,
        Uri.parse('https://example.com'),
      );
      await tester.pumpAndSettle();

      // מוודא שהדיאלוג הוצג
      expect(find.byType(SaferModePasswordDialog), findsOneWidget);

      // ביטול הדיאלוג
      await tester.tap(find.text('ביטול'));
      await tester.pumpAndSettle();

      final result = await futureResult;
      expect(result, isFalse);
      expect(launcher.launched, isEmpty);
    });
  });

  group('saferLaunchUrlString', () {
    testWidgets('מנתח String תקין ומעביר ל-saferLaunchUrl', (tester) async {
      late BuildContext testContext;
      await tester.pumpWidget(
        createTestWidget(
          protectedModeEnabled: false,
          hasPassword: false,
          child: Builder(
            builder: (ctx) {
              testContext = ctx;
              return const SizedBox();
            },
          ),
        ),
      );

      final result = await saferLaunchUrlString(
        testContext,
        'https://example.com/test',
      );

      expect(result, isTrue);
      expect(launcher.launched, ['https://example.com/test']);
    });

    test('מחזיר false ל-URL לא תקין', () async {
      final result = await saferLaunchUrlString(null, ':::invalid-url');
      expect(result, isFalse);
    });

    test('חוסם פתיחה (fail-closed) כאשר context הוא null', () async {
      final result = await saferLaunchUrl(null, Uri.parse('https://example.com'));
      expect(result, isFalse);
    });
  });
}
