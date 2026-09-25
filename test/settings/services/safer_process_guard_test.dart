import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/dialogs/safer_mode_password_dialog.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';
import 'package:otzaria/settings/services/safer_process_guard.dart';

class _MockSettingsRepository extends Mock implements SettingsRepository {}

class _MockSettingsBloc extends Mock implements SettingsBloc {}

void main() {
  late _MockSettingsRepository repository;
  late _MockSettingsBloc settingsBloc;
  late List<({String exe, List<String> args})> executedProcesses;

  setUp(() {
    repository = _MockSettingsRepository();
    settingsBloc = _MockSettingsBloc();
    executedProcesses = [];
    isKioskMode = false;

    SaferProcessGuard.processRunnerOverride = (exe, args) async {
      executedProcesses.add((exe: exe, args: args));
      return ProcessResult(0, 0, '', '');
    };
  });

  tearDown(() {
    SaferProcessGuard.processRunnerOverride = null;
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

  group('SaferProcessGuard.openInFileManager - Kiosk mode (--kiosk / --safer)', () {
    testWidgets('חוסם פתיחת סייר הקבצים לחלוטין ללא דיאלוג סיסמה', (tester) async {
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

      final result = await SaferProcessGuard.openInFileManager(
        testContext,
        r'C:\Users\Public\Documents',
      );

      expect(result, isFalse);
      expect(executedProcesses, isEmpty);
      expect(find.byType(SaferModePasswordDialog), findsNothing);
    });

    testWidgets('נתיב ריק מחזיר false ישירות', (tester) async {
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

      final result = await SaferProcessGuard.openInFileManager(
        testContext,
        '',
      );

      expect(result, isFalse);
      expect(executedProcesses, isEmpty);
    });
  });

  group('SaferProcessGuard.openInFileManager - מצב רגיל (ללא סייפר)', () {
    testWidgets('מאפשר פתיחת סייר קבצים ישירות ללא סיסמה', (tester) async {
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

      const targetPath = r'C:\Otzaria\Library';
      final result = await SaferProcessGuard.openInFileManager(
        testContext,
        targetPath,
      );

      expect(result, isTrue);
      expect(executedProcesses, hasLength(1));
      expect(executedProcesses.first.args, contains(targetPath));
    });
  });

  group('SaferProcessGuard.openInFileManager - מצב סייפר עם סיסמה', () {
    testWidgets('חוסם פתיחה אם דיאלוג הסיסמה בוטל', (tester) async {
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

      final future = SaferProcessGuard.openInFileManager(
        testContext,
        r'C:\Otzaria\Library',
      );
      await tester.pumpAndSettle();

      // וידוא שהדיאלוג נפתח
      expect(find.byType(SaferModePasswordDialog), findsOneWidget);

      // לחיצה על כפתור ביטול
      await tester.tap(find.text('ביטול'));
      await tester.pumpAndSettle();

      final result = await future;
      expect(result, isFalse);
      expect(executedProcesses, isEmpty);
    });

    testWidgets('מאפשר פתיחה לאחר הזנת סיסמה נכונה', (tester) async {
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

      const targetPath = r'C:\Otzaria\Library';
      final future = SaferProcessGuard.openInFileManager(
        testContext,
        targetPath,
      );
      await tester.pumpAndSettle();

      // מזין סיסמה נכונה
      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text('אישור'));
      await tester.pumpAndSettle();

      final result = await future;
      expect(result, isTrue);
      expect(executedProcesses, hasLength(1));
      expect(executedProcesses.first.args, contains(targetPath));
    });

    test('חוסם פתיחה (fail-closed) כאשר context הוא null', () async {
      final result = await SaferProcessGuard.openInFileManager(
        null,
        r'C:\Otzaria\Library',
      );
      expect(result, isFalse);
      expect(executedProcesses, isEmpty);
    });
  });
}
