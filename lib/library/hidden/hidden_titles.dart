import 'package:flutter/foundation.dart' show debugPrint;
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/hidden/hidden_library_store.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';

Library? _cachedLibrary;
HiddenLibrarySelection? _cachedSelection;
Set<String>? _cachedHiddenTitles;

/// כותרות מוסתרות שאין להן עותק גלוי באותו שם, בלי לשכפל את עץ הספרייה.
Set<String> hiddenBookTitlesForSelection(
  Library library,
  HiddenLibrarySelection selection,
) {
  if (selection.isEmpty) return const {};
  if (identical(library, _cachedLibrary) && selection == _cachedSelection) {
    return _cachedHiddenTitles!;
  }
  final visibleTitles = <String>{};
  final hiddenTitles = <String>{};

  void visit(Category category, bool parentHidden) {
    final categoryHidden = parentHidden || selection.isCategoryHidden(category);
    for (final book in category.books) {
      final target = categoryHidden || selection.isBookHidden(book)
          ? hiddenTitles
          : visibleTitles;
      target.add(book.title);
    }
    for (final child in category.subCategories) {
      visit(child, categoryHidden);
    }
  }

  visit(library, false);
  _cachedLibrary = library;
  _cachedSelection = selection;
  return _cachedHiddenTitles = hiddenTitles.difference(visibleTitles);
}

Future<Set<String>> currentHiddenBookTitles() async {
  const store = HiddenLibraryStore();
  if (store.load().isEmpty) return const {};
  try {
    final library = await DataRepository.instance.library;
    return hiddenBookTitlesForSelection(library, store.load());
  } catch (error) {
    debugPrint('[HiddenLibrary] failed to resolve hidden titles: $error');
    return const {};
  }
}
