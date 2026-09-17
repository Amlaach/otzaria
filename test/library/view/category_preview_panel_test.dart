import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/view/book_preview_panel.dart';
import 'package:otzaria/library/view/category_preview_panel.dart';
import 'package:otzaria/models/books.dart';

import '../../helpers/memory_settings_cache.dart';

Category _category(String title, {String description = ''}) => Category(
  title: title,
  description: description,
  shortDescription: '',
  order: 0,
  subCategories: [],
  books: [],
  parent: null,
);

Future<void> _pump(
  WidgetTester tester, {
  required Category category,
  List<Category> subCategories = const [],
  List<Book> books = const [],
  VoidCallback? onOpen,
  bool alreadyOpen = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: CategoryPreviewPanel(
            category: category,
            parentPath: 'תנ״ך, ראשונים',
            subCategories: subCategories,
            books: books,
            onOpen: alreadyOpen ? null : (onOpen ?? () {}),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  group('categoryContentCountsText', () {
    test('יחיד, רבים והשמטת אפס', () {
      expect(
        categoryContentCountsText(subCategories: 1, books: 1),
        'תיקייה אחת · ספר אחד',
      );
      expect(categoryContentCountsText(subCategories: 0, books: 5), '5 ספרים');
      expect(categoryContentCountsText(subCategories: 3, books: 0), '3 תיקיות');
      expect(categoryContentCountsText(subCategories: 0, books: 0), isNull);
    });
  });

  testWidgets('מציג שם, נתיב, מונים ותוכן — בלי תיאור כשאין', (tester) async {
    await _pump(
      tester,
      category: _category('רש״י'),
      subCategories: [_category('תורה')],
      books: [TextBook(title: 'רש״י על בראשית')],
    );

    expect(find.text('רש״י'), findsOneWidget);
    expect(find.text('תנ״ך, ראשונים'), findsOneWidget);
    expect(find.text('תיקייה אחת · ספר אחד'), findsOneWidget);
    expect(find.text('תורה'), findsOneWidget);
    expect(find.textContaining('רש״י על בראשית'), findsOneWidget);
  });

  testWidgets('מציג את התיאור כשקיים ב-DB', (tester) async {
    await _pump(
      tester,
      category: _category('חסידות', description: 'ספרי תורת החסידות'),
    );

    expect(find.text('ספרי תורת החסידות'), findsOneWidget);
  });

  testWidgets('שורות התוכן אינן מנווטות; רק "פתח תיקייה" פותח', (
    tester,
  ) async {
    var opened = 0;
    await _pump(
      tester,
      category: _category('חסידות'),
      subCategories: [_category('חב״ד')],
      onOpen: () => opened++,
    );

    await tester.tap(find.text('חב״ד'));
    await tester.pumpAndSettle();
    expect(opened, 0);

    await tester.tap(find.text('פתח תיקייה'));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('כיתוב החלונית הריקה ניתן להחלפה (ספרייה: ספר או תיקייה)', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BookPreviewPanel(emptyMessage: 'בחר ספר או תיקייה'),
        ),
      ),
    );
    expect(find.text('בחר ספר או תיקייה'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: BookPreviewPanel())),
    );
    expect(find.text('בחר ספר לתצוגה מקדימה'), findsOneWidget);
  });

  testWidgets('התיקייה הפתוחה כבר — בלי כפתור "פתח תיקייה"', (tester) async {
    await _pump(tester, category: _category('חסידות'), alreadyOpen: true);

    expect(find.text('חסידות'), findsOneWidget);
    expect(find.text('פתח תיקייה'), findsNothing);
  });
}
