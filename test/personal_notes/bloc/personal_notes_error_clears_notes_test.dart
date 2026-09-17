import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';

/// issue #1313 — כשטעינת ההערות של ספר נכשלה (למשל תוכן הספר אינו זמין),
/// מצב השגיאה נשא את ההערות של הספר הקודם, ומסך "הערות אישיות" הציג אותן
/// תחת הספר השגוי.
class _Repository implements PersonalNotesRepository {
  @override
  Future<List<PersonalNote>> loadNotes(String bookId, {int? categoryId}) async {
    if (bookId == 'ספר שבור') throw Exception('Book not found');
    return [
      PersonalNote(
        id: 'n1',
        bookId: bookId,
        lineNumber: 3,
        lastKnownLineNumber: 3,
        status: PersonalNoteStatus.located,
        content: 'הערה על $bookId',
        contentPlain: 'הערה על $bookId',
        contentFormat: PersonalNoteContentFormat.plain,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RefreshFailingRepository extends _Repository {
  bool _loaded = false;

  @override
  Future<List<PersonalNote>> loadNotes(String bookId, {int? categoryId}) async {
    if (bookId == 'ספר תקין' && _loaded) {
      throw Exception('Temporary load failure');
    }
    _loaded = true;
    return super.loadNotes(bookId, categoryId: categoryId);
  }
}

void main() {
  test('כשל בטעינת ספר אינו משאיר את הערות הספר הקודם (issue #1313)', () async {
    final bloc = PersonalNotesBloc(repository: _Repository());
    addTearDown(bloc.close);

    bloc.add(const LoadPersonalNotes('ספר תקין'));
    await bloc.stream.firstWhere((s) => !s.isLoading && s.bookId == 'ספר תקין');
    expect(bloc.state.locatedNotes.length + bloc.state.missingNotes.length, 1);

    bloc.add(const LoadPersonalNotes('ספר שבור'));
    final failed = await bloc.stream.firstWhere(
      (s) => !s.isLoading && s.bookId == 'ספר שבור',
    );
    expect(failed.errorMessage, isNotNull);
    expect(failed.locatedNotes, isEmpty, reason: 'הערות של ספר אחר');
    expect(failed.missingNotes, isEmpty);
    expect(failed.filteredLocatedNotes, isEmpty);
  });

  test('כשל ברענון אותו ספר משאיר את ההערות שכבר נטענו', () async {
    final bloc = PersonalNotesBloc(repository: _RefreshFailingRepository());
    addTearDown(bloc.close);

    bloc.add(const LoadPersonalNotes('ספר תקין'));
    await bloc.stream.firstWhere((s) => !s.isLoading && s.bookId == 'ספר תקין');
    final previous = bloc.state.locatedNotes;

    bloc.add(const LoadPersonalNotes('ספר תקין'));
    final failed = await bloc.stream.firstWhere(
      (s) => !s.isLoading && s.bookId == 'ספר תקין',
    );
    expect(failed.errorMessage, isNotNull);
    expect(failed.locatedNotes, previous);
    expect(failed.filteredLocatedNotes, previous);
  });
}
