import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';

/// תצוגה מקדימה של תיקייה (issue #1173): ספר ותיקייה אינם מסומנים יחד.
void main() {
  final category = Category(
    title: 'חסידות',
    description: '',
    shortDescription: '',
    order: 0,
    subCategories: [],
    books: [],
    parent: null,
  );
  final book = TextBook(title: 'תניא');

  test('בחירת תיקייה מנקה את הספר המוצג', () {
    final state = const LibraryState()
        .copyWith(previewBook: book)
        .copyWith(previewCategory: category);

    expect(state.previewCategory, category);
    expect(state.previewBook, isNull);
  });

  test('בחירת ספר מנקה את התיקייה המוצגת', () {
    final state = const LibraryState()
        .copyWith(previewCategory: category)
        .copyWith(previewBook: book);

    expect(state.previewBook, book);
    expect(state.previewCategory, isNull);
  });

  test('copyWith רגיל שומר את התיקייה, ו-clearPreviewBook מנקה גם אותה', () {
    final state = const LibraryState().copyWith(previewCategory: category);

    expect(state.copyWith(isSearching: true).previewCategory, category);
    expect(state.copyWith(clearPreviewBook: true).previewCategory, isNull);
  });
}
