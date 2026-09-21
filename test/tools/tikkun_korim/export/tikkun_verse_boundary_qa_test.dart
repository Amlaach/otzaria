import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tikkun_korim/engine/stam_width_model.dart';
import 'package:otzaria/tools/tikkun_korim/engine/tikkun_processor.dart';
import 'package:otzaria/tools/tikkun_korim/export/tikkun_pdf_exporter.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';

import '../support/tikkun_fixtures.dart';

void main() {
  final book = processBook(
    readFixture('bereshit'),
    'בראשית',
    const StamWidthModel.uniform(),
  );

  test('ייצוא פסוק אמיתי אינו ריק כשהוא מתחיל באמצע שורה', () {
    var chapter = 1;
    for (final token in book.tokens) {
      if (token.type == TikkunTokenType.chapterBreak) {
        chapter = token.chapterNum!;
      }
      if (token.type != TikkunTokenType.verseBreak) continue;
      final verse = token.verseNum!;
      final result = selectTikkunExportColumns(
        [book.allLines],
        TikkunExportOptions(
          scope: TikkunExportScope.verseRange,
          fromChapter: chapter,
          fromVerse: verse,
          toChapter: chapter,
          toVerse: verse,
        ),
        0,
      );
      expect(result, isNotEmpty, reason: 'Genesis $chapter:$verse');
    }
  });

  test('תחום בורר הפסוקים כולל את הפסוק האחרון בכל פרק אמיתי', () {
    final expected = <int, int>{};
    var chapter = 1;
    for (final token in book.tokens) {
      if (token.type == TikkunTokenType.chapterBreak) {
        chapter = token.chapterNum!;
      } else if (token.type == TikkunTokenType.verseBreak) {
        expected[chapter] = token.verseNum!;
      }
    }
    final actual = tikkunVerseDomain([book.allLines]);
    for (final entry in expected.entries) {
      expect(actual[entry.key], entry.value, reason: 'Genesis ${entry.key}');
    }
  });

  test('תחום הבורר שומר את סוף הפרק כששורה חוצה לפרק הבא', () {
    final line = TikkunLine(
      sourceFromChapter: 1,
      sourceFromVerse: 30,
      sourceToChapter: 2,
      sourceToVerse: 1,
      sourceVerseMaxByChapter: const {1: 31, 2: 1},
    );

    expect(
      tikkunVerseDomain([
        [line],
      ]),
      {1: 31, 2: 1},
    );
  });
}
