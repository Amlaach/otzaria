import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/navigation/nav_panel_search.dart';
import 'package:otzaria/widgets/navigation/search_pane_base.dart';

/// ספר שנפתח מתוצאת חיפוש נפתח על לשונית החיפוש של חלונית הניווט. במסך צר
/// השדה יושב בתוך החלונית וממקד את עצמו — ואז המקלדת נפתחה מיד עם הספר, בלי
/// שהמשתמש ביקש לחפש. הבדיקה מריצה את אותה חוטית שבמסכי הספר: הלשונית
/// מסומנת ב-host דרך [NavPanelSearch.shouldMarkActiveTab].
class _NavPanelHarness extends StatefulWidget {
  final NavPanelSearchHost host;
  final TextEditingController controller;
  final FocusNode focusNode;
  final int initialIndex;
  final void Function(TabController) onControllerCreated;

  const _NavPanelHarness({
    required this.host,
    required this.controller,
    required this.focusNode,
    required this.initialIndex,
    required this.onControllerCreated,
  });

  @override
  State<_NavPanelHarness> createState() => _NavPanelHarnessState();
}

class _NavPanelHarnessState extends State<_NavPanelHarness>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late bool _autoSelected;

  @override
  void initState() {
    super.initState();
    _autoSelected = widget.initialIndex != 0;
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialIndex,
    );
    _tabController.addListener(() {
      _autoSelected = false;
      widget.host.activeTab = _tabController.index;
    });
    if (!_autoSelected) widget.host.activeTab = _tabController.index;
    widget.onControllerCreated(_tabController);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!NavPanelSearch.shouldMarkActiveTab(
      context,
      autoSelected: _autoSelected,
    )) {
      return;
    }
    widget.host.activeTab = _tabController.index;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NavPanelSearchScope(
        host: widget.host,
        child: TabBarView(
          controller: _tabController,
          children: [
            const NavPanelSearchSlot(
              index: 0,
              child: Center(child: Text('ניווט')),
            ),
            NavPanelSearchSlot(
              index: 1,
              child: SearchPaneBase(
                searchController: widget.controller,
                focusNode: widget.focusNode,
                resultsWidget: const SizedBox.shrink(),
                isNoResults: false,
                resetSearchCallback: () {},
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  late TextEditingController controller;
  late FocusNode focusNode;
  late NavPanelSearchHost host;
  TabController? tabController;

  setUp(() {
    controller = TextEditingController();
    focusNode = FocusNode(debugLabel: 'searchTabField');
    host = NavPanelSearchHost();
    tabController = null;
  });

  tearDown(() {
    controller.dispose();
    focusNode.dispose();
    host.dispose();
  });

  Future<void> pumpHarness(
    WidgetTester tester, {
    required Size size,
    required int initialIndex,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: _NavPanelHarness(
          host: host,
          controller: controller,
          focusNode: focusNode,
          initialIndex: initialIndex,
          onControllerCreated: (c) => tabController = c,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('טלפון: לשונית חיפוש שנבחרה אוטומטית אינה ממקדת את השדה', (
    tester,
  ) async {
    await pumpHarness(
      tester,
      size: const Size(412, 900),
      initialIndex: 1,
    );

    expect(find.byType(TextField), findsOneWidget, reason: 'השדה בתוך החלונית');
    expect(focusNode.hasFocus, isFalse);
  });

  testWidgets('טלפון: מעבר יזום ללשונית החיפוש כן ממקד את השדה', (
    tester,
  ) async {
    await pumpHarness(
      tester,
      size: const Size(412, 900),
      initialIndex: 1,
    );
    expect(focusNode.hasFocus, isFalse);

    // המשתמש עובר ללשונית הניווט וחוזר בעצמו ללשונית החיפוש.
    tabController!.index = 0;
    await tester.pumpAndSettle();
    tabController!.index = 1;
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(focusNode.hasFocus, isTrue);
  });

  testWidgets('מסך רחב: הלשונית שנבחרה אוטומטית מסומנת מיד (issue #1063)', (
    tester,
  ) async {
    await pumpHarness(
      tester,
      size: const Size(1200, 900),
      initialIndex: 1,
    );

    expect(host.activeTab, 1);
    expect(find.byType(TextField), findsOneWidget, reason: 'השדה בתוך החלונית');
  });

  testWidgets('הרחבת המסך: הלשונית האוטומטית מסומנת בדיעבד (issue #1063)', (
    tester,
  ) async {
    await pumpHarness(tester, size: const Size(412, 900), initialIndex: 1);
    expect(host.activeTab, 0, reason: 'במסך צר הלשונית האוטומטית אינה מסומנת');

    // סיבוב לרוחב / הגדלת החלון — מעתה יש לסמן.
    tester.view.physicalSize = const Size(900, 412);
    await tester.pumpAndSettle();

    expect(host.activeTab, 1);
    expect(focusNode.hasFocus, isFalse, reason: 'סימון אינו בקשת פוקוס');
  });
}
