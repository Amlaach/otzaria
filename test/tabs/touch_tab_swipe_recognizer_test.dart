import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tabs/utils/touch_tab_swipe_recognizer.dart';

void main() {
  late int tabSwipeUpdates;
  late int contentScaleUpdates;

  Widget buildHarness({required bool singleFingerPansContent}) {
    tabSwipeUpdates = 0;
    contentScaleUpdates = 0;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: RawGestureDetector(
        gestures: {
          TouchTabSwipeRecognizer:
              GestureRecognizerFactoryWithHandlers<TouchTabSwipeRecognizer>(
                () => TouchTabSwipeRecognizer(
                  singleFingerPansContent: () => singleFingerPansContent,
                ),
                (recognizer) => recognizer.onUpdate = (_) => tabSwipeUpdates++,
              ),
        },
        // מדמה את ה-InteractiveViewer של pdfrx (pan + zoom).
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleUpdate: (_) => contentScaleUpdates++,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  Future<void> swipe(WidgetTester tester, {required int fingers}) async {
    final gestures = <TestGesture>[];
    for (var i = 0; i < fingers; i++) {
      gestures.add(
        await tester.startGesture(
          Offset(300, 200.0 + i * 100),
          pointer: i + 1,
          kind: PointerDeviceKind.touch,
        ),
      );
    }
    for (var step = 0; step < 10; step++) {
      for (final gesture in gestures) {
        await gesture.moveBy(const Offset(10, 0));
      }
    }
    for (final gesture in gestures) {
      await gesture.up();
    }
    await tester.pump();
  }

  testWidgets('אצבע אחת בלי זום מעבירה כרטיסיה', (tester) async {
    await tester.pumpWidget(buildHarness(singleFingerPansContent: false));
    await swipe(tester, fingers: 1);

    expect(tabSwipeUpdates, greaterThan(0));
    expect(contentScaleUpdates, 0);
  });

  testWidgets('אצבע אחת בדף מוגדל מזיזה את הדף', (tester) async {
    await tester.pumpWidget(buildHarness(singleFingerPansContent: true));
    await swipe(tester, fingers: 1);

    expect(tabSwipeUpdates, 0);
    expect(contentScaleUpdates, greaterThan(0));
  });

  testWidgets('שתי אצבעות מעבירות כרטיסיה גם בדף מוגדל', (tester) async {
    await tester.pumpWidget(buildHarness(singleFingerPansContent: true));
    await swipe(tester, fingers: 2);

    expect(tabSwipeUpdates, greaterThan(0));
    expect(contentScaleUpdates, 0);
  });
}
