import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// שני המופעים בונים [PluginBridgeDependencies] בנפרד. הבדיקה מונעת מצב שבו
/// רק מופע קדמי או רק מופע רקע חוזר לקריאה הישירה ל-findRefs בלי הספרים
/// האישיים.
void main() {
  const hosts = {
    'lib/plugins/view/plugin_tab_page.dart': 'מופע התוסף הקדמי',
    'lib/plugins/view/plugin_background_host.dart': 'מופע תוסף הרקע',
  };

  for (final entry in hosts.entries) {
    test('${entry.value} משתמש ב-resolver המשותף', () {
      final source = File(entry.key).readAsStringSync();

      expect(
        source,
        contains(
          "import 'package:otzaria/plugins/bridge/plugin_reference_resolver.dart';",
        ),
      );
      expect(
        source,
        contains(
          'resolveReference: buildPluginReferenceResolver(findRefRepository),',
        ),
      );
    });
  }
}
