import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:opentype_shaper/opentype_shaper.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_print_helpers.dart';
import 'package:otzaria/tools/calendar/helpers/zmanim_helpers.dart';
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart';
import 'package:pdf/pdf.dart';
import 'package:timezone/data/latest_all.dart' as tz;

String? _findNativeLibrary() {
  final name = Platform.isWindows
      ? 'opentype_shaper.dll'
      : Platform.isMacOS
      ? 'libopentype_shaper.dylib'
      : 'libopentype_shaper.so';
  final configFile = File('.dart_tool/package_config.json');
  if (!configFile.existsSync()) return null;

  final packages =
      jsonDecode(configFile.readAsStringSync())['packages'] as List;
  final shaper = packages.cast<Map<String, dynamic>>().firstWhere(
    (package) => package['name'] == 'opentype_shaper',
    orElse: () => const {},
  );
  final rootUri = shaper['rootUri'] as String?;
  if (rootUri == null) return null;
  final packageRoot = Uri.parse(rootUri);
  final resolvedRoot = packageRoot.hasScheme
      ? packageRoot
      : configFile.parent.uri.resolveUri(packageRoot);
  final packageDirectory = Directory.fromUri(resolvedRoot);

  for (final profile in const ['release', 'debug']) {
    final candidate = File.fromUri(
      packageDirectory.uri.resolve('rust/target/$profile/$name'),
    );
    if (candidate.existsSync()) return candidate.absolute.path;
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final libraryPath = _findNativeLibrary();

  setUpAll(() {
    ShaperLibrary.path = libraryPath;
    tz.initializeTimeZones();
  });

  for (final view in CalendarView.values) {
    test('לוח השנה בתצוגת ${view.name} מודפס בטקסט מעוצב וקטורי', () async {
      final state = CalendarState.initial().copyWith(calendarView: view);
      final bytes = await createCalendarPdf(state, PdfPageFormat.a4, count: 2);

      final raw = latin1.decode(bytes);
      expect(raw, contains('/Identity-H'));
      expect(raw, isNot(contains(RegExp(r'/Subtype\s*/Image'))));
      expect(RegExp(r'/Type\s*/Page(?![s\w])').allMatches(raw).length, 2);
    });
  }

  CalendarState dayState({Set<String>? enabled}) {
    final date = DateTime(2026, 9, 16);
    final base = CalendarState.initial();
    return base.copyWith(
      calendarView: CalendarView.day,
      selectedGregorianDate: date,
      dailyTimes: calculateDailyTimes(date, base.selectedCity),
      enabledZmanim: enabled,
    );
  }

  int pageCount(Uint8List bytes) => RegExp(
    r'/Type\s*/Page(?![s\w])',
  ).allMatches(latin1.decode(bytes)).length;

  test('בתצוגת יום מודפסים רק הזמנים שהופעלו, בשמם העברי', () {
    final state = dayState(enabled: {'chatzosLayla', 'sunset', 'sunrise'});
    final zmanim = calendarPrintedZmanim(state);
    // כמו במסך: לפי השעה, וחצות לילה בסוף.
    final names = {
      for (final def in kZmanimRegistry) def.id: def.fullName,
    };
    expect(
      [for (final (name, _) in zmanim) name],
      [
        names['sunrise'],
        names['sunset'],
        names['chatzosLayla'],
      ],
    );
    for (final (name, time) in zmanim) {
      expect(name, contains(RegExp('[א-ת]')));
      expect(time, contains(RegExp('[0-9]')));
    }
  });

  test('רשימת זמנים ארוכה בתצוגת יום ממשיכה לעמוד הבא', () async {
    final all = {for (final def in kZmanimRegistry) def.id};
    final state = dayState(enabled: all);
    expect(calendarPrintedZmanim(state).length, greaterThan(40));

    final bytes = await createCalendarPdf(state, PdfPageFormat.a4);
    expect(pageCount(bytes), greaterThan(1));
  });
}
