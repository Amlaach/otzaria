import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/dialogs/safer_mode_password_dialog.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/services/safer_file_picker.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';

class _MockSettingsRepository extends Mock implements SettingsRepository {}

class _MockSettingsBloc extends Mock implements SettingsBloc {}

void main() {
  late _MockSettingsRepository repository;
  late _MockSettingsBloc settingsBloc;
  bool directoryCalled = false;
  bool fileCalled = false;
  bool filesCalled = false;
  bool saveCalled = false;

  setUp(() {
    repository = _MockSettingsRepository();
    settingsBloc = _MockSettingsBloc();
    directoryCalled = false;
    fileCalled = false;
    filesCalled = false;
    saveCalled = false;
    isKioskMode = false;

    SaferFilePicker.getDirectoryPathOverride = () async {
      directoryCalled = true;
      return '/mock/path';
    };
    SaferFilePicker.pickFileOverride = () async {
      fileCalled = true;
      return PlatformFile(name: 'test.txt', size: 100, path: '/mock/test.txt');
    };
    SaferFilePicker.pickFilesOverride = () async {
      filesCalled = true;
      return [
        PlatformFile(name: 'test.txt', size: 100, path: '/mock/test.txt'),
      ];
    };
    SaferFilePicker.saveFileOverride = () async {
      saveCalled = true;
      return '/mock/saved.txt';
    };
  });

  tearDown(() {
    SaferFilePicker.getDirectoryPathOverride = null;
    SaferFilePicker.pickFileOverride = null;
    SaferFilePicker.pickFilesOverride = null;
    SaferFilePicker.saveFileOverride = null;
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
      child: BlocProvider<SettingsBloc>.value(
        value: settingsBloc,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: Scaffold(body: child),
        ),
      ),
    );
  }

  group('SaferFilePicker in Normal Mode', () {
    testWidgets('allows directory picking without password', (tester) async {
      String? result;
      await tester.pumpWidget(
        createTestWidget(
          protectedModeEnabled: false,
          hasPassword: false,
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await SaferFilePicker.getDirectoryPath(context: context);
              },
              child: const Text('Pick Dir'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Pick Dir'));
      await tester.pumpAndSettle();

      expect(result, '/mock/path');
      expect(directoryCalled, isTrue);
    });

    testWidgets('allows file picking without password', (tester) async {
      PlatformFile? result;
      await tester.pumpWidget(
        createTestWidget(
          protectedModeEnabled: false,
          hasPassword: false,
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await SaferFilePicker.pickFile(context: context);
              },
              child: const Text('Pick File'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Pick File'));
      await tester.pumpAndSettle();

      expect(result?.path, '/mock/test.txt');
      expect(fileCalled, isTrue);
    });
  });

  group('SaferFilePicker in Kiosk Mode', () {
    setUp(() {
      isKioskMode = true;
    });

    testWidgets('blocks getDirectoryPath completely in kiosk mode', (tester) async {
      String? result;
      await tester.pumpWidget(
        createTestWidget(
          protectedModeEnabled: true,
          hasPassword: true,
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await SaferFilePicker.getDirectoryPath(context: context);
              },
              child: const Text('Pick Dir'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Pick Dir'));
      await tester.pumpAndSettle();

      expect(result, isNull);
      expect(directoryCalled, isFalse);
      expect(find.byType(SaferModePasswordDialog), findsNothing);
    });

    testWidgets('blocks pickFile completely in kiosk mode', (tester) async {
      PlatformFile? result;
      await tester.pumpWidget(
        createTestWidget(
          protectedModeEnabled: true,
          hasPassword: true,
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await SaferFilePicker.pickFile(context: context);
              },
              child: const Text('Pick File'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Pick File'));
      await tester.pumpAndSettle();

      expect(result, isNull);
      expect(fileCalled, isFalse);
    });

    testWidgets('blocks pickFiles completely in kiosk mode', (tester) async {
      List<PlatformFile> result = [];
      await tester.pumpWidget(
        createTestWidget(
          protectedModeEnabled: true,
          hasPassword: true,
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await SaferFilePicker.pickFiles(context: context);
              },
              child: const Text('Pick Files'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Pick Files'));
      await tester.pumpAndSettle();

      expect(result, isEmpty);
      expect(filesCalled, isFalse);
    });

    testWidgets('blocks saveFile completely in kiosk mode', (tester) async {
      String? result;
      await tester.pumpWidget(
        createTestWidget(
          protectedModeEnabled: true,
          hasPassword: true,
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await SaferFilePicker.saveFile(context: context);
              },
              child: const Text('Save File'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Save File'));
      await tester.pumpAndSettle();

      expect(result, isNull);
      expect(saveCalled, isFalse);
    });
  });

  group('SaferFilePicker in Safer Mode', () {
    testWidgets('prompts for password and proceeds on correct password', (tester) async {
      String? result;
      await tester.pumpWidget(
        createTestWidget(
          protectedModeEnabled: true,
          hasPassword: true,
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await SaferFilePicker.getDirectoryPath(context: context);
              },
              child: const Text('Pick Dir'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Pick Dir'));
      await tester.pumpAndSettle();

      expect(find.byType(SaferModePasswordDialog), findsOneWidget);

      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text('אישור'));
      await tester.pumpAndSettle();

      expect(result, '/mock/path');
      expect(directoryCalled, isTrue);
    });

    testWidgets('cancels and returns null when dialog is cancelled', (tester) async {
      String? result;
      await tester.pumpWidget(
        createTestWidget(
          protectedModeEnabled: true,
          hasPassword: true,
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await SaferFilePicker.getDirectoryPath(context: context);
              },
              child: const Text('Pick Dir'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Pick Dir'));
      await tester.pumpAndSettle();

      expect(find.byType(SaferModePasswordDialog), findsOneWidget);

      await tester.tap(find.text('ביטול'));
      await tester.pumpAndSettle();

      expect(result, isNull);
      expect(directoryCalled, isFalse);
    });
  });
}
