// בדיקות ל-SaferModeGuard: נעילה מחדש ביציאה ממסך ההגדרות בלי להרוס את
// ה-State של המסך המוגן (הוא נשאר בעץ Offstage, והנעילה היא שכבה בלבד).

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/settings/dialogs/safer_mode_password_dialog.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

class MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class MockNavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

class _FakeSettingsRepository extends Fake implements SettingsRepository {
  @override
  bool hasProtectedModePassword() => true;

  @override
  bool verifyProtectedModePassword(String password) => password == '1234';
}

/// ילד עם State פנימי — מוכיח שהנעילה לא הורסת את המסך המוגן.
class _CounterChild extends StatefulWidget {
  const _CounterChild();

  @override
  State<_CounterChild> createState() => _CounterChildState();
}

class _CounterChildState extends State<_CounterChild> {
  int count = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => setState(() => count++),
          child: Text('count: $count'),
        ),
      ),
    );
  }
}

void main() {
  late MockSettingsBloc settingsBloc;
  late MockNavigationBloc navigationBloc;
  late StreamController<NavigationState> navStates;
  late _FakeSettingsRepository repository;

  setUp(() {
    settingsBloc = MockSettingsBloc();
    navigationBloc = MockNavigationBloc();
    navStates = StreamController<NavigationState>();
    repository = _FakeSettingsRepository();
    whenListen(
      settingsBloc,
      const Stream<SettingsState>.empty(),
      initialState: SettingsState.initial().copyWith(
        protectedModeEnabled: true,
      ),
    );
    whenListen(
      navigationBloc,
      navStates.stream,
      initialState: const NavigationState(currentScreen: Screen.settings),
    );
  });

  tearDown(() => navStates.close());

  Widget buildGuard() {
    return MaterialApp(
      home: RepositoryProvider<SettingsRepository>.value(
        value: repository,
        child: MultiBlocProvider(
          providers: [
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
            BlocProvider<NavigationBloc>.value(value: navigationBloc),
          ],
          child: const SaferModeGuard(child: _CounterChild()),
        ),
      ),
    );
  }

  Future<void> pumpLockedGuard(WidgetTester tester) async {
    await tester.pumpWidget(buildGuard());
    await tester.pump(); // postFrame של בדיקת ההגנה
    await tester.pump();
  }

  Future<void> enterPassword(WidgetTester tester, String password) async {
    await tester.enterText(find.byType(RtlTextField), password);
    await tester.tap(find.text('אישור'));
    await tester.pumpAndSettle();
  }

  testWidgets('במצב סייפר פעיל — מסך נעילה ודיאלוג סיסמה, הילד חי אך מוסתר', (
    tester,
  ) async {
    await pumpLockedGuard(tester);

    expect(find.byType(SaferModePasswordDialog), findsOneWidget);
    expect(find.text('count: 0'), findsNothing);
    // הילד נשאר בעץ (Offstage) — לא נהרס
    expect(find.text('count: 0', skipOffstage: false), findsOneWidget);
  });

  testWidgets('סיסמה נכונה פותחת את המסך המוגן', (tester) async {
    await pumpLockedGuard(tester);
    await enterPassword(tester, '1234');

    expect(find.byType(SaferModePasswordDialog), findsNothing);
    expect(find.text('count: 0'), findsOneWidget);
  });

  testWidgets('יציאה מההגדרות נועלת מחדש, וחזרה מבקשת סיסמה בלי לאבד State', (
    tester,
  ) async {
    await pumpLockedGuard(tester);
    await enterPassword(tester, '1234');

    // שינוי State פנימי בילד
    await tester.tap(find.text('count: 0'));
    await tester.pump();
    expect(find.text('count: 1'), findsOneWidget);

    // יציאה ממסך ההגדרות — נעילה מחדש בלי דיאלוג (המסך אינו בחזית)
    navStates.add(const NavigationState(currentScreen: Screen.library));
    await tester.pump();
    await tester.pump();
    expect(find.text('הנך במצב סייפר'), findsOneWidget);
    expect(find.byType(SaferModePasswordDialog), findsNothing);
    expect(find.text('count: 1'), findsNothing);

    // חזרה להגדרות — נדרשת סיסמה מחדש
    navStates.add(const NavigationState(currentScreen: Screen.settings));
    await tester.pump();
    await tester.pump();
    expect(find.byType(SaferModePasswordDialog), findsOneWidget);

    // אחרי אימות — הילד חוזר עם ה-State שנשמר
    await enterPassword(tester, '1234');
    expect(find.text('count: 1'), findsOneWidget);
  });

  testWidgets('כשמצב סייפר כבוי — הילד מוצג מיד ללא דיאלוג', (tester) async {
    whenListen(
      settingsBloc,
      const Stream<SettingsState>.empty(),
      initialState: SettingsState.initial(),
    );

    await pumpLockedGuard(tester);

    expect(find.byType(SaferModePasswordDialog), findsNothing);
    expect(find.text('count: 0'), findsOneWidget);
  });
}
