import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';

/// ספק שמחזיר תשובות לפי סדר — מדמה כשל חולף ואחריו הצלחה.
class _ScriptedProvider extends Fake implements LibraryProvider {
  _ScriptedProvider(this.responses);

  final List<Object> responses;
  int calls = 0;

  @override
  Future<String> getLinkContent(Link link) async {
    final response = responses[calls++];
    if (response is Exception) throw response;
    return response as String;
  }
}

Link _link(int index2) => Link(
  heRef: 'רש"י על עירובין, ב., ב, א',
  index1: 1,
  path2: 'רש"י על עירובין',
  index2: index2,
  connectionType: LinkTypes.commentary,
);

void main() {
  final manager = LibraryProviderManager.instance;

  void seed(LibraryProvider provider) => manager.seedMappingsForTesting(
    mapping: <BookCompositeKey, LibraryProvider>{},
    providers: <LibraryProvider>[provider],
  );

  tearDown(manager.resetForTesting);

  test('תוצאת שגיאה אינה נשמרת במטמון — ניסיון נוסף טוען מחדש', () async {
    final provider = _ScriptedProvider(['שגיאה: מאגר לא מאותחל', 'תוכן רש"י']);
    seed(provider);
    final link = _link(9001);

    expect(await link.content, 'שגיאה: לא נמצא תוכן');
    await Future<void>.delayed(Duration.zero);
    expect(await link.content, 'תוכן רש"י');
    expect(provider.calls, 2);
  });

  test('תוצאה תקינה נשמרת במטמון', () async {
    final provider = _ScriptedProvider(['תוכן רש"י']);
    seed(provider);
    final link = _link(9002);

    expect(await link.content, 'תוכן רש"י');
    await Future<void>.delayed(Duration.zero);
    expect(await link.content, 'תוכן רש"י');
    expect(provider.calls, 1);
  });
}
