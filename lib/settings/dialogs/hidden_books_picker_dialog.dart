import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// בוחר ספרים להסתרה מתוך כל ספרי הספרייה (issue #1448).
///
/// הבחירה נעשית ממקום אחד ולא מכרטיס הספר: כך אין צורך להוסיף כפתור לכל
/// כרטיס בספרייה, וגם ביטול ההסתרה נעשה מאותו מסך.
///
/// מחזיר את קבוצת מפתחות הספרים המוסתרים, או `null` בביטול.
Future<Set<String>?> showHiddenBooksPickerDialog({
  required BuildContext context,
  required List<Book> books,
  required Set<String> hiddenBookKeys,
}) {
  return showDialog<Set<String>>(
    context: context,
    builder: settingsDialogBuilder(
      context,
      (_) => _HiddenBooksPickerDialog(books: books, hidden: hiddenBookKeys),
    ),
  );
}

class _HiddenBooksPickerDialog extends StatefulWidget {
  final List<Book> books;
  final Set<String> hidden;

  const _HiddenBooksPickerDialog({required this.books, required this.hidden});

  @override
  State<_HiddenBooksPickerDialog> createState() =>
      _HiddenBooksPickerDialogState();
}

class _PickerRow {
  final String key;
  final String title;
  final String details;
  final String haystack;

  _PickerRow(Book book)
    : key = PerBookSettings.bookKey(book),
      title = book.title,
      details = [
        if ((book.author ?? '').isNotEmpty) book.author!,
        if ((book.categoryPath ?? '').isNotEmpty) book.categoryPath!,
      ].join(' · '),
      haystack = '${book.title} ${book.author ?? ''} ${book.categoryPath ?? ''}'
          .toLowerCase();

  bool matches(String query) => haystack.contains(query.toLowerCase());
}

class _HiddenBooksPickerDialogState extends State<_HiddenBooksPickerDialog> {
  late final List<_PickerRow> _rows;
  late List<_PickerRow> _visible;
  late final Set<String> _selected;
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();

  /// מציג רק את המוסתרים — הדרך המהירה לבטל הסתרה בלי לחפש בין אלפי ספרים.
  bool _hiddenOnly = false;

  @override
  void initState() {
    super.initState();
    _rows = widget.books.map(_PickerRow.new).toList();
    _selected = {...widget.hidden};
    _visible = _rows;
    _search.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _search.removeListener(_applyFilter);
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _applyFilter() {
    final query = _search.text.trim();
    setState(() {
      _visible = _rows
          .where(
            (row) =>
                (query.isEmpty || row.matches(query)) &&
                (!_hiddenOnly || _selected.contains(row.key)),
          )
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final maxWidth = media.size.width * 0.9;

    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth > 720 ? 720 : maxWidth,
          maxHeight: media.size.height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(OtzariaIcons.book_24_regular, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.settingsText('בחירת ספרים להסתרה'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Text(
                    '${_selected.length} / ${_rows.length}',
                    style:
                        Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              RtlTextField(
                controller: _search,
                autofocus: true,
                decoration: InputDecoration(
                  prefixIcon: const Icon(OtzariaIcons.search_24_regular),
                  hintText: context.settingsText(
                    'חיפוש לפי שם, מחבר או קטגוריה',
                  ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  icon: Icon(
                    _hiddenOnly
                        ? FluentIcons.eye_off_24_regular
                        : FluentIcons.eye_24_regular,
                    size: 18,
                  ),
                  label: Text(
                    _hiddenOnly
                        ? context.settingsText('הצג את כל הספרים')
                        : context.settingsText('הצג רק מוסתרים'),
                  ),
                  onPressed: () {
                    _hiddenOnly = !_hiddenOnly;
                    _applyFilter();
                  },
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: _visible.isEmpty
                    ? Center(
                        child: Text(
                          context.settingsText('לא נמצאו ספרים'),
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      )
                    : Scrollbar(
                        controller: _scroll,
                        thumbVisibility: true,
                        child: ListView.separated(
                          controller: _scroll,
                          itemCount: _visible.length,
                          separatorBuilder: (_, _) => Divider(
                            height: 1,
                            color: cs.surfaceContainerHighest,
                          ),
                          itemBuilder: (_, i) {
                            final row = _visible[i];
                            return CheckboxListTile(
                              value: _selected.contains(row.key),
                              title: Text(row.title),
                              subtitle: row.details.isEmpty
                                  ? null
                                  : Text(row.details),
                              onChanged: (checked) {
                                setState(() {
                                  if (checked == true) {
                                    _selected.add(row.key);
                                  } else {
                                    _selected.remove(row.key);
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ActionButton.recommended(
                    text: context.settingsText('שמור'),
                    onPressed: () => Navigator.of(context).pop(_selected),
                  ),
                  const Spacer(),
                  ActionButton.ghost(
                    text: context.settingsText('ביטול'),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
