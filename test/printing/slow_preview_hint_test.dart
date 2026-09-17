import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/printing/view/slow_preview_hint.dart';

double _opacity(WidgetTester tester) =>
    tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;

void main() {
  testWidgets('ההערה מופיעה רק אחרי ההשהיה', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SlowPreviewHint())),
    );
    expect(_opacity(tester), 0);

    await tester.pump(
      SlowPreviewHint.delay - const Duration(milliseconds: 100),
    );
    expect(_opacity(tester), 0);

    await tester.pump(const Duration(milliseconds: 200));
    expect(_opacity(tester), 1);
  });

  testWidgets('סגירה לפני ההשהיה אינה משאירה טיימר פעיל', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SlowPreviewHint())),
    );
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(SlowPreviewHint.delay);
  });
}
