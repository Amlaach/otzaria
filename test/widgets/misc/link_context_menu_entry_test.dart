import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/widgets/misc/link_context_menu_entry.dart';

void main() {
  Link buildLink() => Link(
    heRef: 'בראשית א א',
    index1: 1,
    path2: 'ספר.txt',
    index2: 5,
    connectionType: 'commentary',
  );

  group('buildLinkContextMenuEntry', () {
    testWidgets('כותרת התצוגה המקדימה פותחת את היעד (issue #1423)', (
      tester,
    ) async {
      var opened = 0;
      final entry = buildLinkContextMenuEntry(
        link: buildLink(),
        onTap: () => opened++,
      );

      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (builderContext) {
              context = builderContext;
              return const SizedBox();
            },
          ),
        ),
      );

      final preview =
          entry.hoverPreviewBuilder!(context) as LinkHoverPreviewContent;
      expect(
        preview.onOpen,
        isNotNull,
        reason: 'בלי onOpen הכותרת אינה לחיצה והחלונית המקובעת ללא דרך פתיחה',
      );

      preview.onOpen!();
      expect(opened, 1, reason: 'לחיצה על הכותרת פותחת את אותו יעד כמו הפריט');
    });
  });
}
