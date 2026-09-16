import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/tour/widgets/live_tip_card.dart';
import 'package:otzaria/tour/widgets/tour_tooltip_card.dart';

/// בודק שכרטיסי הסיור והטיפים החיים מקבלים את כיוון שפת ההגדרות,
/// גם כשה-Overlay שמארח אותם נשאר RTL (issue #805).
void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    required SettingsLanguage language,
    required Widget card,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: SettingsTextScope(
            language: language,
            child: Scaffold(body: Center(child: card)),
          ),
        ),
      ),
    );
  }

  // isLastStep מציג כפתור יחיד — בפונט הבדיקה הרחב (Ahem) שורת כל
  // הכפתורים גולשת מרוחב הכרטיס וזה לא מעניינו של הטסט.
  Widget tooltipCard() => TourTooltipCard(
    title: 'סיום',
    body: 'גוף ההסבר',
    currentIndex: 0,
    totalSteps: 3,
    isLastStep: true,
    isWelcomeStep: false,
    onNext: () {},
    onSkip: () {},
    onToggleAutoPlay: () {},
  );

  Widget liveTipCard() => LiveTipCard(
    title: 'טיפ',
    description: 'תיאור הטיפ',
    onDismiss: () {},
    onDismissAll: () {},
  );

  TextDirection directionOf(WidgetTester tester, Type type) =>
      Directionality.of(
        tester.element(
          find
              .descendant(of: find.byType(type), matching: find.byType(Column))
              .first,
        ),
      );

  testWidgets('TourTooltipCard באנגלית — תוכן הכרטיס LTR', (tester) async {
    await pumpCard(
      tester,
      language: SettingsLanguage.english,
      card: tooltipCard(),
    );
    expect(directionOf(tester, TourTooltipCard), TextDirection.ltr);
  });

  testWidgets('TourTooltipCard בעברית — תוכן הכרטיס RTL', (tester) async {
    await pumpCard(
      tester,
      language: SettingsLanguage.hebrew,
      card: tooltipCard(),
    );
    expect(directionOf(tester, TourTooltipCard), TextDirection.rtl);
  });

  testWidgets('LiveTipCard באנגלית — תוכן הכרטיס LTR', (tester) async {
    await pumpCard(
      tester,
      language: SettingsLanguage.english,
      card: liveTipCard(),
    );
    expect(directionOf(tester, LiveTipCard), TextDirection.ltr);
  });

  testWidgets('LiveTipCard בעברית — תוכן הכרטיס RTL', (tester) async {
    await pumpCard(
      tester,
      language: SettingsLanguage.hebrew,
      card: liveTipCard(),
    );
    expect(directionOf(tester, LiveTipCard), TextDirection.rtl);
  });
}
