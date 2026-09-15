import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui show IsolateNameServer;

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/bookmarks/repository/bookmark_repository.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/core/windowing/shared_hive_store.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/history/history_repository.dart';
import 'package:otzaria/workspaces/workspace.dart';
import 'package:otzaria/workspaces/workspace_repository.dart';

/// ⚠️ קידומת ייחודית לסוויטה — [ui.IsolateNameServer] גלובלי לתהליך.
const String _namespace = 'otzaria.test.cas.store';

/// בעלים אמיתי: מריץ את `handleRequest` — הקוד שמשרת כל חלון משני.
///
/// ⚠️ החלפת צד הבעלים במימוש חלופי הייתה משאירה את `handleRequest` עצמו
/// לא-נבדק, וזה הצד שבו יושב בורר הגרסאות.
class _FakeOwner {
  _FakeOwner(this.slot);

  final int slot;
  final SharedHiveStore store = SharedHiveStore.owner();
  late final ReceivePort _port;

  String get _name => '$_namespace.$slot';

  void register() {
    _port = ReceivePort();
    ui.IsolateNameServer.registerPortWithName(_port.sendPort, _name);
    ui.IsolateNameServer.registerPortWithName(
      _port.sendPort,
      '$_namespace.owner',
    );
    _port.listen((message) async {
      final map = message as Map;
      final reply = map['reply'] as SendPort;
      final body = Map<String, dynamic>.from(map['body'] as Map);
      try {
        reply.send({'ok': true, 'result': await store.handleRequest(body)});
      } catch (e) {
        reply.send({'ok': false, 'error': '$e'});
      }
    });
  }

  void dispose() {
    ui.IsolateNameServer.removePortNameMapping(_name);
    ui.IsolateNameServer.removePortNameMapping('$_namespace.owner');
    _port.close();
  }
}

/// בעלים רשום שאינו עונה — חלון שעסוק בבניית הקטלוג.
class _SilentOwner {
  late final ReceivePort _port;

  void register() {
    _port = ReceivePort();
    ui.IsolateNameServer.registerPortWithName(_port.sendPort, '$_namespace.1');
    ui.IsolateNameServer.registerPortWithName(
      _port.sendPort,
      '$_namespace.owner',
    );
    _port.listen((_) {});
  }

  void dispose() {
    ui.IsolateNameServer.removePortNameMapping('$_namespace.1');
    ui.IsolateNameServer.removePortNameMapping('$_namespace.owner');
    _port.close();
  }
}

Future<String> _outcome(Future<void> f) =>
    f.then((_) => 'ok').catchError((Object e) => e.runtimeType.toString());

void main() {
  late Directory tmp;

  setUp(() {
    WindowBus.namespace = _namespace;
    // הרישום ללוג כבוי כאן כדי שהבדיקות לא יכתבו ל-errors.txt האמיתי.
    SharedHiveUnavailable.logSink = (_) {};
    WindowRole.isSecondary = false;
    // ⚠️ תיקייה זמנית **ייחודית** ולא נתיב קבוע ב-systemTemp: שתי הרצות
    // מקבילות באותה מכונה היו נועלות זו לזו את קובצי ה-Hive.
    tmp = Directory.systemTemp.createTempSync('otzaria_cas_');
    Hive.init(tmp.path);
  });

  tearDown(() async {
    SharedHiveUnavailable.logSink = ErrorLogFile.appendText;
    SharedHiveUnavailable.resetLogForTest();
    WindowRole.isSecondary = false;
    WindowBus.instance.onRequest = null;
    WindowBus.instance.unregister();
    SharedHiveStore.instance.resetForTest();
    for (var i = 1; i <= WindowBus.slotCount; i++) {
      ui.IsolateNameServer.removePortNameMapping('$_namespace.$i');
    }
    ui.IsolateNameServer.removePortNameMapping('$_namespace.owner');
    WindowBus.namespace = 'otzaria.window';
    await Hive.deleteFromDisk();
  });

  group('C2: בורר הגרסאות ב-_writeAsOwner', () {
    test('[בעלים, מקומי] שתי כתיבות מקבילות עם אותו ifRevision — בדיוק אחת '
        'עוברת', () async {
      // ⚠️ `box.put` הוא נקודת yield. בלי תור פר-מפתח שתי הכתיבות עברו
      // שתיהן את בדיקת הגרסה, הראשונה נדרסה **בשקט**, והגרסה עלתה ב-1
      // בלבד — כך שגם קורא שלישי לא ידע שהיו שתי כתיבות.
      await Hive.openBox<dynamic>('history');
      final store = SharedHiveStore.instance;
      final base = await store.read('history', 'history');
      final results = await Future.wait([
        _outcome(
          store.write(
            'history',
            'history',
            [
              {'title': 'A'},
            ],
            ifRevision: base.revision,
          ),
        ),
        _outcome(
          store.write(
            'history',
            'history',
            [
              {'title': 'B'},
            ],
            ifRevision: base.revision,
          ),
        ),
      ]);

      expect(results.where((r) => r == 'ok').length, 1);
      expect(results.where((r) => r == 'SharedHiveConflict').length, 1);
      // הגרסה עלתה פעם אחת בלבד — כי כתיבה אחת בלבד התקבלה.
      final after = await store.read('history', 'history');
      expect(after.revision, base.revision + 1);
    });

    test('[משני, מרוחק דרך handleRequest] שתי כתיבות מקבילות — בדיוק אחת '
        'עוברת', () async {
      final owner = _FakeOwner(1)..register();
      addTearDown(owner.dispose);
      await Hive.openBox<dynamic>('history');
      WindowRole.isSecondary = true;
      WindowBus.instance.register();

      final store = SharedHiveStore.instance;
      final base = await store.read('history', 'history');
      final results = await Future.wait([
        _outcome(
          store.write(
            'history',
            'history',
            [
              {'title': 'A'},
            ],
            ifRevision: base.revision,
          ),
        ),
        _outcome(
          store.write(
            'history',
            'history',
            [
              {'title': 'B'},
            ],
            ifRevision: base.revision,
          ),
        ),
      ]);

      expect(results.where((r) => r == 'ok').length, 1);
      expect(results.where((r) => r == 'SharedHiveConflict').length, 1);
    });
  });

  group('C3: קריאה שאינה מוסמכת אינה "ריק"', () {
    test('[משני, אין בעלים] load זורק ואינו מחזיר [] בשקט', () async {
      // ⚠️ זה מסלול אובדן הנתונים החמור: `load` שהחזיר `[]` הפך "לא
      // הצלחנו לשאול" ל"אין נתונים", וגיבוי שנוצר באותו רגע נכתב עם
      // סעיפים ריקים **בלי שגיאה**. שחזור ממנו מוחק הכול.
      WindowRole.isSecondary = true;
      WindowBus.instance.register();
      await Hive.openBox<dynamic>('history');
      await Hive.openBox<dynamic>('bookmarks');

      final snapshot = await SharedHiveStore.instance.read(
        'history',
        'history',
      );
      expect(snapshot.authoritative, isFalse);

      await expectLater(
        HistoryRepository().loadHistory(),
        throwsA(isA<SharedHiveUnavailable>()),
      );
      await expectLater(
        BookmarkRepository().loadBookmarks(),
        throwsA(isA<SharedHiveUnavailable>()),
      );
    });

    test('[משני, בעלים שאינו עונה] load זורק אחרי ה-timeout', () async {
      final silent = _SilentOwner()..register();
      addTearDown(silent.dispose);
      WindowRole.isSecondary = true;
      WindowBus.instance.register();
      await Hive.openBox<dynamic>('history');

      await expectLater(
        HistoryRepository().loadHistory(),
        throwsA(isA<SharedHiveUnavailable>()),
      );
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('כשל קריאה של הבעלים עובר על החוט ואינו נראה כערך מוסמך', () async {
      // ⚠️ `handleRequest` שלח `revision`/`value` בלבד, והקורא סימן
      // `authoritative: true` באופן עיוור — כלומר box שאינו פתוח אצל
      // הבעלים הוחזר לחלון המשני כ-null **מוסמך**.
      final owner = _FakeOwner(1)..register();
      addTearDown(owner.dispose);
      WindowRole.isSecondary = true;
      WindowBus.instance.register();

      // ה-box אינו נפתח בכלל — הקריאה המקומית אצל הבעלים תיכשל.
      final snapshot = await SharedHiveStore.instance.read(
        'bookmarks',
        'bookmarks',
      );
      expect(snapshot.authoritative, isFalse);
    });
  });

  group('H2: WorkspaceRepository בחלון משני', () {
    test('box מקומי ריק + רשימה משותפת — אין נפילה לשולחן הראשון', () async {
      // ⚠️ ה-box המקומי של חלון משני ריק **תמיד** (שורש Hive פרטי חדש בכל
      // פתיחה), ולכן מיגרציית ה-legacy קיבעה אותו על השולחן הראשון — אותו
      // שולחן שהחלון הראשון עומד עליו. שני חלונות על אותו שולחן דורסים זה
      // לזה את ה-stash, וכרטיסיה נעלמת משניהם.
      final owner = _FakeOwner(1)..register();
      addTearDown(owner.dispose);
      await Hive.openBox<dynamic>('workspaces');

      final a = Workspace(name: 'א', tabs: const []);
      final b = Workspace(name: 'ב', tabs: const []);
      await owner.store.write('workspaces', WorkspaceRepository.workspacesKey, [
        a.toJson(),
        b.toJson(),
      ]);
      expect(
        Hive.box<dynamic>('workspaces').get('key-current-workspace-id'),
        isNull,
      );

      WindowRole.isSecondary = true;
      WindowBus.instance.register();

      final (workspaces, activeId) = await WorkspaceRepository()
          .loadWorkspaces();

      expect(workspaces, hasLength(2));
      expect(activeId, isNull);
    });

    test('[חלון ראשון] מיגרציית ה-legacy כן רצה ובוחרת שולחן', () async {
      // בקרה: הגידור הוא על חלון משני בלבד, ואינו משנה את החלון הראשון.
      await Hive.openBox<dynamic>('workspaces');
      final a = Workspace(name: 'א', tabs: const []);
      await SharedHiveStore.instance.write(
        'workspaces',
        WorkspaceRepository.workspacesKey,
        [a.toJson()],
      );

      final (workspaces, activeId) = await WorkspaceRepository()
          .loadWorkspaces();

      expect(workspaces, hasLength(1));
      expect(activeId, a.id);
    });
  });
}
