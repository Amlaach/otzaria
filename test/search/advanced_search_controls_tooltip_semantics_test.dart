// issue #1399: כפתור "ברירת מחדל לחיפוש חדש" יושב בתוך MenuAnchor.builder עם
// tooltip. כשה-Tooltip עוטף את הכפתור מבחוץ, עוגן הבלון ועוגן התפריט מתמזגים
// לצומת סמנטיקה אחד, ובריחוף הבלון נשלח למערכת ההפעלה בלי אב — Windows דוחה
// את עדכון עץ הנגישות, העץ קופא והתוכנה קורסת במעבר הפוקוס הבא.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/view/advanced_search_controls.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';

import '../helpers/semantics_update_recorder.dart';
import '../support/search_engine_test_init.dart';
import '../test_helpers/memory_cache_provider.dart';

Future<void> main() async {
  // ה-binding המקליט חייב להיווצר לפני כל binding אחר.
  SemanticsRecordingBinding.ensure();
  final recorder = SemanticsRecordingBinding.recorder;

  // הווידג'ט קורא ל-splitQueryWords שמאציל למנוע ה-Rust; בלי הספרייה הנייטיבית
  // הבדיקה מדולגת כמו יתר בדיקות החיפוש התלויות בה.
  final engineReady = await tryInitSearchEngine();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  testWidgets(
    'ריחוף על "ברירת מחדל לחיפוש חדש" בתוך MenuAnchor אינו שולח צומת נגישות '
    'יתום (issue #1399)',
    (tester) async {
      recorder.reset();
      final handle = tester.ensureSemantics();
      final tab = SearchingTab('חיפוש', 'שלום');
      addTearDown(tab.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              child: AdvancedSearchControls(tab: tab),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      const tooltip = 'סמן אילו אפשרויות יופעלו אוטומטית בכל חיפוש חדש';
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byTooltip(tooltip)));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text(tooltip), findsOneWidget, reason: 'הבלון נפתח');
      expect(
        recorder.violations,
        isEmpty,
        reason: 'עדכוני הסמנטיקה חייבים להתקבל במנוע ללא צומת יתום',
      );

      await mouse.moveTo(const Offset(5, 5));
      await tester.pump(const Duration(seconds: 1));
      expect(recorder.violations, isEmpty);
      handle.dispose();
    },
    skip: !engineReady,
  );
}
