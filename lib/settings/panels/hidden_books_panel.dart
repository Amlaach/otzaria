import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/hidden/hidden_books_import.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/library/hidden/hidden_library_store.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/settings/dialogs/hidden_books_list_dialog.dart';
import 'package:otzaria/settings/dialogs/hidden_books_picker_dialog.dart';
import 'package:otzaria/settings/l10n/settings_text.dart';
import 'package:otzaria/settings/search/settings_search_models.dart';
import 'package:otzaria/settings/view/settings_screen.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// מסך ניהול הספרים והקטגוריות שהוסתרו מהממשק (issue #1448).
///
/// ההסתרה היא של הממשק בלבד: מסד הספרים אינו משתנה, וספר מוסתר עדיין נפתח
/// מקישור, מהיסטוריה או מסימנייה.
class HiddenBooksPanel extends StatefulWidget {
  /// חנות ההסתרות. ניתנת להחלפה בבדיקות.
  final HiddenLibraryStore store;

  /// לצורכי בדיקה — עוקף את בורר הקבצים של המערכת.
  final Future<String?> Function()? pickFileOverride;

  /// לצורכי בדיקה — עוקף את טעינת הספרייה.
  final Future<Library> Function()? libraryLoader;

  /// מסיר ספרים מאינדקס החיפוש. ניתן להחלפה בבדיקות.
  final Future<bool> Function(Iterable<Book> books)? indexDropper;

  const HiddenBooksPanel({
    super.key,
    this.store = const HiddenLibraryStore(),
    this.pickFileOverride,
    this.libraryLoader,
    this.indexDropper,
  });

  /// פריטי חיפוש בהגדרות. נסרק על-ידי tool/generate_search_index.dart.
  static const List<SettingsSearchEntry> searchEntries = [
    SettingsSearchEntry(
      id: 'library.hidden_books.import',
      title: 'ייבוא רשימת הסתרות',
      subtitle: 'הסתרת ספרים מהממשק לפי רשימת שמות בקובץ CSV או JSON',
      tab: SettingsTab.library,
      cardId: 'library.hidden_books',
      keywords: ['הסתרה', 'מוסתר', 'הסתר', 'ייבוא', 'רשימה', 'CSV', 'JSON'],
    ),
    SettingsSearchEntry(
      id: 'library.hidden_books.list',
      title: 'ספרים מוסתרים',
      subtitle: 'הצגת הספרים שהוסתרו וביטול ההסתרה',
      tab: SettingsTab.library,
      cardId: 'library.hidden_books',
      keywords: ['הסתרה', 'מוסתר', 'ביטול', 'שחזור', 'ספרים'],
    ),
  ];

  @override
  State<HiddenBooksPanel> createState() => _HiddenBooksPanelState();
}

class _HiddenBooksPanelState extends State<HiddenBooksPanel> {
  late HiddenLibrarySelection _hidden = widget.store.load();

  /// מפתח ספר → כותרת להצגה. ספר שאינו בספרייה יוצג לפי המפתח הגולמי, כדי
  /// שהמשתמש יוכל להסיר גם הסתרה של ספר שנעלם.
  Map<String, String> _titles = const {};

  @override
  void initState() {
    super.initState();
    unawaited(_loadTitles());
  }

  Future<void> _loadTitles() async {
    if (_hidden.bookKeys.isEmpty) return;
    try {
      final library = await _library();
      if (!mounted) return;
      setState(() {
        _titles = {
          for (final book in library.getAllBooks())
            PerBookSettings.bookKey(book): book.title,
        };
      });
    } catch (_) {
      // הספרייה לא נטענה — הרשימה תוצג לפי המפתחות.
    }
  }

  Future<Library> _library() =>
      widget.libraryLoader?.call() ?? DataRepository.instance.library;

  Future<void> _save(HiddenLibrarySelection next) async {
    await widget.store.save(next);
    if (!mounted) return;
    setState(() => _hidden = next);
    // בלי זה ההסתרה נכנסת לתוקף רק בהפעלה הבאה: LibraryBloc שומר את העץ
    // ב-state והמסנן חל רק ברגע הטעינה (issue #1448).
    context.read<LibraryBloc>().add(const HiddenBooksChanged());
  }

  Future<void> _showHiddenList() async {
    final updated = await showHiddenBooksListDialog(
      context: context,
      hidden: _hidden,
      titles: _titles,
    );
    if (updated == null || !mounted) return;
    await _save(updated);
  }

  Future<void> _pickBooks() async {
    final library = await _library();
    if (!mounted) return;

    final picked = await showHiddenBooksPickerDialog(
      context: context,
      books: library.getAllBooks(),
      hiddenBookKeys: _hidden.bookKeys,
    );
    if (picked == null || !mounted) return;

    final added = picked.difference(_hidden.bookKeys);
    await _save(_hidden.copyWith(bookKeys: picked));
    await _dropFromIndex(library, added);
    await _loadTitles();
  }

  Future<void> _import() async {
    final path = await (widget.pickFileOverride?.call() ?? _pickFile());
    if (path == null || !mounted) return;

    final String content;
    try {
      content = await File(path).readAsString();
    } catch (error) {
      UiSnack.showError('לא ניתן לקרוא את הקובץ: $error');
      return;
    }

    final library = await _library();
    final result = parseHiddenBooksImport(content, library);
    if (!mounted) return;

    if (result.isEmpty) {
      UiSnack.showError('הקובץ ריק — לא הוסתר דבר');
      return;
    }

    await _save(
      _hidden.copyWith(
        bookKeys: {..._hidden.bookKeys, ...result.matchedBookKeys},
      ),
    );
    // ספר מוסתר יורד מאינדקס החיפוש מיד (issue #1448), ולא מסונן מהתוצאות:
    // כך מונה התוצאות וספירות חלונית הסינון נשארים נכונים.
    await _dropFromIndex(library, result.matchedBookKeys);
    await _loadTitles();
    if (!mounted) return;

    UiSnack.show(
      result.unmatchedNames.isEmpty
          ? 'הוסתרו ${result.matchedBookKeys.length} ספרים'
          : 'הוסתרו ${result.matchedBookKeys.length} ספרים; '
                '${result.unmatchedNames.length} שמות לא נמצאו בספרייה',
    );
  }

  Future<void> _dropFromIndex(Library library, Set<String> keys) async {
    if (keys.isEmpty) return;
    final books = library
        .getAllBooks()
        .where((book) => keys.contains(PerBookSettings.bookKey(book)))
        .toList();
    if (books.isEmpty) return;
    final drop =
        widget.indexDropper ??
        IndexingRepository(TantivyDataProvider.instance).dropBookIndexEntries;
    try {
      await drop(books);
    } catch (error) {
      // כשל בהסרה מהאינדקס אינו מבטל את ההסתרה — הספר כבר נעלם מהממשק,
      // וריצת האינדוקס הבאה תדלג עליו ממילא.
      debugPrint('[HiddenBooks] index drop failed: $error');
    }
  }

  Future<String?> _pickFile() async {
    final result = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'json', 'txt'],
    );
    return result?.path;
  }

  @override
  Widget build(BuildContext context) {
    final count = _hidden.bookKeys.length + _hidden.categoryPaths.length;

    return Column(
      children: [
        SettingsActionTile.text(
          icon: OtzariaIcons.book_24_regular,
          title: context.settingsText('בחירת ספרים להסתרה'),
          subtitle: context.settingsText(
            'רשימת כל הספרים בספרייה, עם חיפוש וסימון',
          ),
          actions: [
            ActionButton.recommended(
              text: context.settingsText('פתח רשימה'),
              onPressed: _pickBooks,
            ),
          ],
        ),
        SettingsActionTile.text(
          icon: FluentIcons.arrow_import_24_regular,
          title: context.settingsText('ייבוא רשימת הסתרות'),
          subtitle: context.settingsText(
            'קובץ CSV עם שם ספר בכל שורה, או JSON עם מערך שמות. שם שלא יימצא בספרייה ידווח',
          ),
          actions: [
            ActionButton.neutral(
              text: context.settingsText('בחר קובץ'),
              onPressed: _import,
            ),
          ],
        ),
        SettingsActionTile.text(
          icon: FluentIcons.eye_off_24_regular,
          title: count == 0
              ? context.settingsText('אין ספרים מוסתרים')
              : context.settingsText(
                  'פריטים מוסתרים: {count}',
                  args: {'count': count},
                ),
          subtitle: context.settingsText(
            'הסתרה משפיעה על מסך הספרייה, האיתור והחיפוש בלבד — ספר מוסתר עדיין נפתח מקישור או מההיסטוריה',
          ),
          actions: [
            if (count > 0)
              ActionButton.neutral(
                text: context.settingsText('הצג רשימה'),
                onPressed: _showHiddenList,
              ),
          ],
        ),
      ],
    );
  }
}
