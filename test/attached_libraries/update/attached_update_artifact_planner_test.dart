import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/models/attached_update_manifest.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_artifact_planner.dart';
import 'package:path/path.dart' as p;

AttachedUpdateArtifact _artifact({
  required AttachedUpdateCompression compression,
  required int size,
  required String sha256,
  required int downloadSize,
  String url = 'https://updates.example.org/lib/part',
}) => AttachedUpdateArtifact(
  compression: compression,
  size: size,
  sha256: sha256,
  parts: [AttachedUpdatePart(url: url, size: downloadSize, sha256: sha256)],
);

void main() {
  late Directory temp;
  late String installed;
  late String installedSha;

  setUp(() async {
    AttachedUpdateArtifactPlanner.clearCacheForTesting();
    temp = await Directory.systemTemp.createTemp('otzaria_delta_plan');
    installed = p.join(temp.path, 'lib.db');
    final bytes = List<int>.generate(4096, (i) => i % 251);
    await File(installed).writeAsBytes(bytes);
    installedSha = sha256.convert(bytes).toString();
  });

  tearDown(() async {
    try {
      await temp.delete(recursive: true);
    } catch (_) {}
  });

  AttachedUpdateManifest manifest(List<AttachedUpdateDelta> deltas) =>
      AttachedUpdateManifest(
        libraryId: 'lib',
        dbVersion: 3,
        full: _artifact(
          compression: AttachedUpdateCompression.zstd,
          size: 9000,
          sha256: 'a' * 64,
          downloadSize: 5000,
        ),
        deltas: deltas,
      );

  AttachedUpdateDelta delta({
    int fromDbVersion = 2,
    String? fromSha256,
    int downloadSize = 1000,
    String url = 'https://updates.example.org/lib/patch',
  }) => AttachedUpdateDelta(
    fromDbVersion: fromDbVersion,
    fromSha256: fromSha256 ?? installedSha,
    artifact: _artifact(
      compression: AttachedUpdateCompression.zstdPatch,
      size: 9000,
      sha256: 'a' * 64,
      downloadSize: downloadSize,
      url: url,
    ),
  );

  Future<AttachedUpdatePlan> planWith(
    List<AttachedUpdateDelta> deltas, {
    int? pointerSize,
    int maxBaseBytes = kMaxDeltaBaseBytes,
    void Function(String path)? onHash,
  }) => AttachedUpdateArtifactPlanner(
    pointerSize: pointerSize ?? 8,
    maxBaseBytes: maxBaseBytes,
    hashFile: (path) async {
      onHash?.call(path);
      return sha256.convert(await File(path).readAsBytes()).toString();
    },
  ).plan(manifest(deltas), installedPath: installed, installedDbVersion: 2);

  test('picks the smallest applicable delta', () async {
    final small = delta(downloadSize: 700, url: 'https://x.example.org/small');
    final plan = await planWith([delta(downloadSize: 1500), small]);
    expect(plan.isDelta, isTrue);
    expect(plan.delta, same(small));
    expect(plan.artifact.compressedSize, 700);
  });

  test('a delta for another db_version is ignored', () async {
    final plan = await planWith([delta(fromDbVersion: 1)]);
    expect(plan.isDelta, isFalse);
    expect(plan.artifact.compressedSize, 5000);
  });

  test('a delta whose from_sha256 differs is ignored', () async {
    final plan = await planWith([delta(fromSha256: 'b' * 64)]);
    expect(plan.isDelta, isFalse);
  });

  test(
    'a delta that is not smaller than the full download is ignored',
    () async {
      final plan = await planWith([delta(downloadSize: 5000)]);
      expect(plan.isDelta, isFalse);
    },
  );

  test('a 32-bit process never uses a delta', () async {
    var hashed = 0;
    final plan = await planWith(
      [delta()],
      pointerSize: 4,
      onHash: (_) => hashed++,
    );
    expect(plan.isDelta, isFalse);
    expect(hashed, 0);
  });

  test('an installed file over the window ceiling is ignored', () async {
    final plan = await planWith([delta()], maxBaseBytes: 100);
    expect(plan.isDelta, isFalse);
  });

  test('a missing installed file falls back to the full artifact', () async {
    await File(installed).delete();
    final plan = await planWith([delta()]);
    expect(plan.isDelta, isFalse);
  });

  test('the installed file is not hashed without a matching delta', () async {
    var hashed = 0;
    await planWith([delta(fromDbVersion: 1)], onHash: (_) => hashed++);
    expect(hashed, 0);
  });

  test('the hash is cached, and recomputed after the file changes', () async {
    var hashed = 0;
    expect(
      (await planWith([delta()], onHash: (_) => hashed++)).isDelta,
      isTrue,
    );
    expect(
      (await planWith([delta()], onHash: (_) => hashed++)).isDelta,
      isTrue,
    );
    expect(hashed, 1);

    await File(installed).writeAsBytes([1, 2, 3]);
    expect(
      (await planWith([delta()], onHash: (_) => hashed++)).isDelta,
      isFalse,
    );
    expect(hashed, 2);
  });
}
