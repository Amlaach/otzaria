import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';

import 'support/seeded_reference_library.dart';

void main() {
  tearDown(resetSeededLibrary);

  test('ביטול בזמן await מונע מהחיפוש הישן להגיש בקשת TOC ראשונה', () async {
    seedLibrary(const [
      (id: 1, title: 'בראשית', acronyms: []),
      (id: 2, title: 'שמות', acronyms: []),
    ]);
    final firstEntered = Completer<void>();
    final firstGate = Completer<List<int>?>();
    final tocBooks = <int>[];
    var altCalls = 0;
    final repo = FindRefRepository(
      isReferenceBooksCacheLoaded: () => true,
      getAltStructureBookIds: () {
        if (altCalls++ == 0) {
          firstEntered.complete();
          return firstGate.future;
        }
        return Future.value(const []);
      },
      getTocEntriesForReference: (id, title, {queryTokens}) async {
        tocBooks.add(id);
        return const [];
      },
      getAltTocEntriesForReference: (id, title, {queryTokens}) async =>
          const [],
      getAllAltTocFlatEntries: () async => const [],
      getCategoryPath: (_) async => 'ספרייה',
    );
    addTearDown(repo.dispose);

    final old = expectLater(
      repo.findRefs('בראשית פרק'),
      throwsA(isA<FindRefQueryCancelled>()),
    );
    await firstEntered.future;
    repo.cancelPendingSearch(); // אירוע הקלדה, לפני תום ה-debounce
    await repo.findRefs('שמות פרק');
    firstGate.complete(const []);
    await old;

    expect(tocBooks, [2], reason: 'המשך חיפוש ישן לא שולח TOC בדור החדש');
  });

  test('ביטול אחרי בקשת TOC פעילה מונע את שאר הספרים', () async {
    seedLibrary(const [
      (id: 1, title: 'ספר ראשון', acronyms: []),
      (id: 2, title: 'ספר שני', acronyms: []),
    ]);
    final firstTocEntered = Completer<void>();
    final firstTocGate = Completer<List<Map<String, dynamic>>>();
    final tocBooks = <int>[];
    final repo = FindRefRepository(
      isReferenceBooksCacheLoaded: () => true,
      getAltStructureBookIds: () async => const [],
      getTocEntriesForReference: (id, title, {queryTokens}) {
        tocBooks.add(id);
        if (tocBooks.length == 1) {
          firstTocEntered.complete();
          return firstTocGate.future;
        }
        return Future.value(const []);
      },
      getAltTocEntriesForReference: (id, title, {queryTokens}) async =>
          const [],
      getAllAltTocFlatEntries: () async => const [],
      getCategoryPath: (_) async => 'ספרייה',
    );
    addTearDown(repo.dispose);

    final old = expectLater(
      repo.findRefs('ספר פרק'),
      throwsA(isA<FindRefQueryCancelled>()),
    );
    await firstTocEntered.future;
    repo.cancelPendingSearch();
    firstTocGate.complete(const []);
    await old;

    expect(
      tocBooks,
      hasLength(1),
      reason: 'אחרי הבקשה שכבר רצה אין עוד עבודה ישנה',
    );
  });

  test(
    'dispose מבטל המשך חיפוש, משחרר scope פעם אחת וחוסם שימוש נוסף',
    () async {
      seedLibrary(const [(id: 1, title: 'בראשית', acronyms: [])]);
      final entered = Completer<void>();
      final gate = Completer<List<int>?>();
      var released = 0;
      var tocCalls = 0;
      final repo = FindRefRepository(
        isReferenceBooksCacheLoaded: () => true,
        getAltStructureBookIds: () {
          entered.complete();
          return gate.future;
        },
        getTocEntriesForReference: (id, title, {queryTokens}) async {
          tocCalls++;
          return const [];
        },
        getAltTocEntriesForReference: (id, title, {queryTokens}) async =>
            const [],
        releaseSearchScope: () => released++,
      );

      final pending = expectLater(
        repo.findRefs('בראשית פרק'),
        throwsA(isA<FindRefQueryCancelled>()),
      );
      await entered.future;
      repo.dispose();
      repo.dispose();
      gate.complete(const []);
      await pending;

      expect(released, 1);
      expect(tocCalls, 0);
      await expectLater(
        repo.findRefs('בראשית פרק'),
        throwsA(isA<FindRefQueryCancelled>()),
      );
    },
  );
}
