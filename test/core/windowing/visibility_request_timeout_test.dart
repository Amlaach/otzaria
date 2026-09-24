import 'dart:isolate';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';

const _namespace = 'otzaria.test.visibility.timeout';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ReceivePort owner;
  String? operationId;

  setUp(() {
    WindowBus.namespace = _namespace;
    MultiWindowService.visibilityRequestTimeout = const Duration(
      milliseconds: 20,
    );
    owner = ReceivePort();
    IsolateNameServer.registerPortWithName(
      owner.sendPort,
      '$_namespace.owner',
    );
    owner.listen((message) {
      final request = Map<String, dynamic>.from(
        (message as Map)['body'] as Map,
      );
      operationId = request['operationId'] as String;
    });
    WindowBus.instance.register();
  });

  tearDown(() {
    if (operationId != null) {
      MultiWindowService.completeVisibilityRequest(operationId!, true);
    }
    operationId = null;
    WindowBus.instance.unregister();
    IsolateNameServer.removePortNameMapping('$_namespace.owner');
    owner.close();
    WindowBus.namespace = 'otzaria.window';
    MultiWindowService.visibilityRequestTimeout = const Duration(seconds: 8);
  });

  test('פקיעת ACK מחזירה מצב לא ידוע ומפסיקה מעקב מקומי', () async {
    final result = await const MultiWindowService().requestVisibilityChange(
      const HiddenLibrarySelection(),
      const HiddenLibrarySelection(bookKeys: {'book'}),
    );

    expect(result.selection, isNull);
    expect(result.saved, isFalse);
    expect(result.uncertain, isTrue);
    expect(operationId, isNotNull);
    expect(MultiWindowService.pendingVisibilityRequestCountForTesting, 0);
    expect(
      MultiWindowService.completeVisibilityRequest(operationId!, true),
      isFalse,
    );
    operationId = null;
    expect(MultiWindowService.pendingVisibilityRequestCountForTesting, 0);
  });

  test('איפוס runtime מבטל מעקב אחר פעולות חלון קודמות', () {
    MultiWindowService.trackVisibilityRequestForTesting('before-restart');
    expect(MultiWindowService.pendingVisibilityRequestCountForTesting, 1);
    MultiWindowService.clearVisibilityRequestsForRestart();
    expect(MultiWindowService.pendingVisibilityRequestCountForTesting, 0);
    expect(
      MultiWindowService.completeVisibilityRequest('before-restart', false),
      isFalse,
    );
  });
}
