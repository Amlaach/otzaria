import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/pdf_book/view/pdf_commentary_panel.dart';

Link _link(String path2, int index1, int index2) => Link(
  heRef: path2,
  index1: index1,
  path2: path2,
  index2: index2,
  connectionType: 'commentary',
);

void main() {
  test('קטעי מפרש על אותה שורה ממוינים לפי שורת היעד (#1330)', () {
    // מעל 32 פריטים המיון של Dart עובר ל-quicksort לא יציב.
    final expected = [
      for (var line = 1; line <= 20; line++)
        for (var target = 0; target < 3; target++)
          _link('חברותא על סנהדרין', line, line * 10 + target),
      _link('רש"י על סנהדרין', 1, 5),
      _link('רש"י על סנהדרין', 1, 6),
    ];

    for (var seed = 0; seed < 20; seed++) {
      final links = [...expected]..shuffle(Random(seed));
      links.sort(comparePdfCommentaryLinks);
      expect(
        links.map((l) => '${l.path2}|${l.index1}|${l.index2}').toList(),
        expected.map((l) => '${l.path2}|${l.index1}|${l.index2}').toList(),
        reason: 'seed $seed',
      );
    }
  });
}
