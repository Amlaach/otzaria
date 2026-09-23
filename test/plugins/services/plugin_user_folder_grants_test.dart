import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_user_folder_grants.dart';

/// KV בזיכרון, ממופתח לפי תוסף — כדי לוודא שתוסף אחד אינו רואה תיקיות של אחר.
class _Registry extends PluginRegistryRepository {
  final Map<String, String> kv = {};

  @override
  Future<void> setKV(
    String pluginId,
    String namespace,
    String key,
    String valueJson,
  ) async => kv['$pluginId/$namespace/$key'] = valueJson;

  @override
  Future<String?> getKV(String pluginId, String namespace, String key) async =>
      kv['$pluginId/$namespace/$key'];
}

void main() {
  late _Registry registry;
  late PluginUserFolderGrants grants;

  setUp(() {
    registry = _Registry();
    grants = PluginUserFolderGrants(registry);
  });

  test('ריק כשאין רשומה, וכש-JSON פגום', () async {
    expect(await grants.list('a'), isEmpty);
    registry.kv['a/_internal/user_folder_grants'] = '{not json';
    expect(await grants.list('a'), isEmpty);
  });

  test('add / list / byToken / byPath, ובידוד בין תוספים', () async {
    await grants.add('a', (token: 'dir-1', path: '/x/שיעורים'));
    await grants.add('a', (token: 'dir-2', path: '/y/מאמרים'));
    expect(await grants.list('a'), [
      (token: 'dir-1', path: '/x/שיעורים'),
      (token: 'dir-2', path: '/y/מאמרים'),
    ]);
    expect(await grants.byToken('a', 'dir-2'), (
      token: 'dir-2',
      path: '/y/מאמרים',
    ));
    expect((await grants.byPath('a', '/x/שיעורים'))?.token, 'dir-1');
    expect(await grants.byToken('a', 'nope'), isNull);
    expect(await grants.list('b'), isEmpty);
  });

  test('רשומה פגומה מדולגת ברשימה', () async {
    registry.kv['a/_internal/user_folder_grants'] =
        '{"dir-1":{"path":"/x"},"dir-2":{"oops":1}}';
    expect(await grants.list('a'), [(token: 'dir-1', path: '/x')]);
  });

  test('revoke מחזיר את מה שהוסר, ואידמפוטנטי', () async {
    await grants.add('a', (token: 'dir-1', path: '/x'));
    await grants.add('a', (token: 'dir-2', path: '/y'));
    expect(await grants.revoke('a', 'dir-1'), (token: 'dir-1', path: '/x'));
    expect(await grants.revoke('a', 'dir-1'), isNull);
    expect(await grants.list('a'), [(token: 'dir-2', path: '/y')]);
  });
}
