import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/library/hidden/hidden_library_store.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/panels/hidden_books_panel.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';

Library _library() {
  final tora = Category(
    title: 'תורה',
    description: '',
    shortDescription: '',
    order: 1,
    subCategories: [],
    books: [
      TextBook(title: 'בראשית', categoryId: 10),
      TextBook(title: 'שמות', categoryId: 10),
    ],
    parent: null,
  );
  final library = Library(categories: [tora]);
  tora.parent = library;
  return library;
}

String _key(String title) =>
    PerBookSettings.bookKey(TextBook(title: title, categoryId: 10));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _TestLibraryBloc libraryBloc;
  final droppedFromIndex = <String>[];

  setUp(() async {
    await Settings.init(cacheProvider: _MemoryCacheProvider());
    tempDir = await Directory.systemTemp.createTemp('hidden_books_panel');
    droppedFromIndex.clear();
    libraryBloc = _TestLibraryBloc();
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<void> pump(
    WidgetTester tester, {
    Future<String?> Function()? pickFile,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      BlocProvider<LibraryBloc>.value(
        value: libraryBloc,
        child: MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SingleChildScrollView(
                child: HiddenBooksPanel(
                  pickFileOverride: pickFile,
                  libraryLoader: () async => _library(),
                  indexDropper: (books) async {
                    droppedFromIndex.addAll(books.map((b) => b.title));
                    return true;
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('בחירת ספר מהרשימה מסתירה אותו (issue #1448)', (tester) async {
    await pump(tester);

    await tester.tap(find.text('פתח רשימה'));
    await tester.pumpAndSettle();

    expect(find.text('בחירת ספרים להסתרה'), findsWidgets);
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('שמור'));
    await tester.pumpAndSettle();

    expect(const HiddenLibraryStore().load().bookKeys, {_key('בראשית')});
    expect(droppedFromIndex, ['בראשית']);
  });

  testWidgets('הסתרה מרעננת את עץ הספרייה מיד (issue #1448)', (tester) async {
    await pump(tester);

    await tester.tap(find.text('פתח רשימה'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('שמור'));
    await tester.pumpAndSettle();

    expect(
      libraryBloc.addedEvents.whereType<HiddenBooksChanged>(),
      hasLength(1),
      reason: 'בלעדיו ההסתרה נכנסת לתוקף רק בהפעלה הבאה',
    );
  });

  testWidgets('ביטול בדיאלוג הבחירה אינו משנה דבר (issue #1448)', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('פתח רשימה'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ביטול'));
    await tester.pumpAndSettle();

    expect(const HiddenLibraryStore().load().isEmpty, isTrue);
    expect(droppedFromIndex, isEmpty);
  });

  testWidgets('אין הסתרות — מוצג הסבר ולא רשימה (issue #1448)', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('אין ספרים מוסתרים'), findsOneWidget);
    expect(
      find.text('הצג רשימה'),
      findsNothing,
      reason: 'אין מה להציג, ולכן אין כפתור לחלון',
    );
  });

  testWidgets('ייבוא CSV מסתיר ושומר (issue #1448)', (tester) async {
    final file = File('${tempDir.path}/hide.csv')
      ..writeAsStringSync('בראשית\nאין כזה\n');

    await pump(tester, pickFile: () async => file.path);
    // הייבוא קורא קובץ אמיתי; pumpAndSettle מריץ פריימים ואינו ממתין ל-IO.
    await tester.runAsync(() async {
      await tester.tap(find.text('בחר קובץ'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(
      const HiddenLibraryStore().load().bookKeys,
      {_key('בראשית')},
      reason: 'רק השם שהותאם נשמר',
    );
    expect(find.text('1 פריטים מוסתרים'), findsOneWidget);
  });

  testWidgets('ספר שהוסתר יורד מאינדקס החיפוש (issue #1448)', (tester) async {
    final file = File('${tempDir.path}/hide.csv')..writeAsStringSync('שמות\n');

    await pump(tester, pickFile: () async => file.path);
    await tester.runAsync(() async {
      await tester.tap(find.text('בחר קובץ'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(
      droppedFromIndex,
      ['שמות'],
      reason: 'הסרה מהאינדקס ולא סינון תוצאות — כך המונה נשאר נכון',
    );
  });

  testWidgets('ביטול הסתרה מתוך החלון (issue #1448)', (tester) async {
    await const HiddenLibraryStore().save(
      HiddenLibrarySelection(bookKeys: {_key('שמות')}),
    );

    await pump(tester);
    expect(find.text('1 פריטים מוסתרים'), findsOneWidget);

    await tester.tap(find.text('הצג רשימה'));
    await tester.pumpAndSettle();
    expect(find.text('שמות'), findsOneWidget);

    await tester.tap(find.text('בטל הסתרה').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('שמור'));
    await tester.pumpAndSettle();

    expect(const HiddenLibraryStore().load().isEmpty, isTrue);
    expect(find.text('אין ספרים מוסתרים'), findsOneWidget);
  });

  testWidgets('קטגוריה מוסתרת מוצגת בחלון לפי הנתיב (issue #1448)', (
    tester,
  ) async {
    await const HiddenLibraryStore().save(
      const HiddenLibrarySelection(categoryPaths: {'/תנ"ך/תורה'}),
    );

    await pump(tester);
    await tester.tap(find.text('הצג רשימה'));
    await tester.pumpAndSettle();

    expect(find.text('/תנ"ך/תורה'), findsOneWidget);
  });

  testWidgets('הרשימה אינה מוצגת בגוף מסך ההגדרות (issue #1448)', (
    tester,
  ) async {
    await const HiddenLibraryStore().save(
      HiddenLibrarySelection(bookKeys: {_key('שמות')}),
    );

    await pump(tester);

    expect(
      find.text('שמות'),
      findsNothing,
      reason: 'מספר ההסתרות אינו חסום — רשימה פנימית הייתה מאריכה את המסך',
    );
  });
}

class _MemoryCacheProvider extends CacheProvider {
  final Map<String, Object?> _values = {};

  @override
  Future<void> init() async {}

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  Set getKeys() => _values.keys.toSet();

  @override
  bool? getBool(String key, {bool? defaultValue}) =>
      _values[key] as bool? ?? defaultValue;

  @override
  double? getDouble(String key, {double? defaultValue}) =>
      _values[key] as double? ?? defaultValue;

  @override
  int? getInt(String key, {int? defaultValue}) =>
      _values[key] as int? ?? defaultValue;

  @override
  String? getString(String key, {String? defaultValue}) =>
      _values[key] as String? ?? defaultValue;

  @override
  T? getValue<T>(String key, {T? defaultValue}) {
    final value = _values[key];
    if (value is T) {
      return value;
    }
    return defaultValue;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> removeAll() async {
    _values.clear();
  }

  @override
  Future<void> setBool(String key, bool? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setDouble(String key, double? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setInt(String key, int? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setObject<T>(String key, T? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setString(String key, String? value) async {
    _values[key] = value;
  }
}

class _TestLibraryBloc extends Cubit<LibraryState> implements LibraryBloc {
  _TestLibraryBloc() : super(LibraryState.initial());

  final List<LibraryEvent> addedEvents = [];

  @override
  void add(LibraryEvent event) => addedEvents.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
