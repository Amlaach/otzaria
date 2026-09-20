import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/models/attached_update_manifest.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_artifact_builder.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_delta_applier.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_fetcher.dart';
import 'package:otzaria/utils/file/zstd_patch_decoder.dart';
import 'package:path/path.dart' as p;

/// The zstd CLI and a libzstd for FFI, or null (the test is skipped).
({String exe, String lib})? _findZstd() {
  final which = Process.runSync(Platform.isWindows ? 'where' : 'which', [
    'zstd',
  ]);
  if (which.exitCode != 0) return null;
  final exe = (which.stdout as String).split(RegExp(r'[\r\n]+')).first.trim();
  final dir = p.dirname(File(exe).resolveSymbolicLinksSync());
  for (final candidate in [
    ?Platform.environment['LIBZSTD_PATH'],
    p.join(dir, 'dll', 'libzstd.dll'),
    p.join(dir, 'libzstd.dll'),
    'libzstd.so.1',
    'libzstd.so',
    '/opt/homebrew/lib/libzstd.dylib',
    '/usr/local/lib/libzstd.dylib',
  ]) {
    try {
      DynamicLibrary.open(candidate);
      return (exe: exe, lib: candidate);
    } catch (_) {}
  }
  return null;
}

AttachedUpdatePatchDecoder _decodeWith(String lib) =>
    (patch, base, output, max, cancel) async => decodePatchSyncForTest(
      patch,
      base,
      output,
      DynamicLibrary.open(lib),
      maxOutputBytes: max,
      cancelAddress: cancel?.address ?? 0,
    );

Uint8List _content(int seed, int length) {
  final random = Random(seed);
  return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
}

void main() {
  late Directory dir;
  late ({String exe, String lib})? zstd;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('delta_applier_test');
    zstd = _findZstd();
  });
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  String path(String name) => p.join(dir.path, name);

  /// Writes old.db/new.db and a real `zstd --patch-from` patch; returns the
  /// artifact describing the resulting new.db.
  Future<AttachedUpdateArtifact> fixture({
    Uint8List? oldBytes,
    Uint8List? newBytes,
  }) async {
    final base = oldBytes ?? _content(1, 400 * 1024);
    final target =
        newBytes ??
        Uint8List.fromList([
          ...base.sublist(0, 300 * 1024),
          ..._content(2, 40 * 1024),
        ]);
    File(path('old.db')).writeAsBytesSync(base);
    File(path('new.db')).writeAsBytesSync(target);
    final run = Process.runSync(zstd!.exe, [
      '--patch-from=${path('old.db')}',
      '--long=31',
      '-1',
      path('new.db'),
      '-o',
      path('patch.zst'),
    ]);
    expect(run.exitCode, 0, reason: run.stderr.toString());
    return AttachedUpdateArtifact(
      compression: AttachedUpdateCompression.zstdPatch,
      size: target.length,
      sha256: sha256.convert(target).toString(),
      parts: const [
        AttachedUpdatePart(url: 'https://e.org/p', size: 1, sha256: ''),
      ],
    );
  }

  Future<void> expectFails(AttachedUpdateArtifact artifact) async {
    final before = sha256.convert(File(path('old.db')).readAsBytesSync());
    final applier = AttachedUpdateDeltaApplier(
      decodePatch: _decodeWith(zstd!.lib),
    );
    await expectLater(
      applier.apply(
        artifact,
        path('patch.zst'),
        path('old.db'),
        path('out.db'),
      ),
      throwsA(anything),
    );
    expect(File(path('out.db')).existsSync(), isFalse);
    // The base file is byte-identical, and the patch stays for a retry.
    expect(sha256.convert(File(path('old.db')).readAsBytesSync()), before);
    expect(File(path('patch.zst')).existsSync(), isTrue);
    // A leaked mapping would keep the base locked and break the later swap.
    File(path('old.db')).renameSync(path('swapped.db'));
    File(path('swapped.db')).renameSync(path('old.db'));
  }

  test('applies a real zstd --patch-from patch', () async {
    if (zstd == null) return markTestSkipped('zstd / libzstd not available');
    final artifact = await fixture();
    final applier = AttachedUpdateDeltaApplier(
      decodePatch: _decodeWith(zstd!.lib),
    );
    await applier.apply(
      artifact,
      path('patch.zst'),
      path('old.db'),
      path('out.db'),
    );
    expect(
      File(path('out.db')).readAsBytesSync(),
      File(path('new.db')).readAsBytesSync(),
    );
    // The consumed patch is removed; the base file is untouched.
    expect(File(path('patch.zst')).existsSync(), isFalse);
    expect(File(path('old.db')).existsSync(), isTrue);
  });

  test('a corrupt patch throws and deletes the output', () async {
    if (zstd == null) return markTestSkipped('zstd / libzstd not available');
    final artifact = await fixture();
    final patch = File(path('patch.zst'));
    final bytes = patch.readAsBytesSync();
    bytes[bytes.length ~/ 2] ^= 0xff;
    patch.writeAsBytesSync(bytes);
    await expectFails(artifact);
  });

  test('the wrong base file throws and deletes the output', () async {
    if (zstd == null) return markTestSkipped('zstd / libzstd not available');
    final artifact = await fixture();
    File(path('old.db')).writeAsBytesSync(_content(9, 400 * 1024));
    await expectFails(artifact);
  });

  test('output larger than the declared size aborts', () async {
    if (zstd == null) return markTestSkipped('zstd / libzstd not available');
    final artifact = await fixture();
    await expectFails(
      AttachedUpdateArtifact(
        compression: artifact.compression,
        size: artifact.size ~/ 2,
        sha256: artifact.sha256,
        parts: artifact.parts,
      ),
    );
  });

  test('a sha256 mismatch throws and deletes the output', () async {
    if (zstd == null) return markTestSkipped('zstd / libzstd not available');
    final artifact = await fixture();
    await expectFails(
      AttachedUpdateArtifact(
        compression: artifact.compression,
        size: artifact.size,
        sha256: 'c' * 64,
        parts: artifact.parts,
      ),
    );
  });

  test('a missing base file, and a non-patch artifact, are rejected', () async {
    const applier = AttachedUpdateDeltaApplier();
    const artifact = AttachedUpdateArtifact(
      compression: AttachedUpdateCompression.zstd,
      size: 10,
      sha256: 'd',
      parts: [],
    );
    await expectLater(
      applier.apply(artifact, path('p'), path('old.db'), path('out.db')),
      throwsA(isA<AttachedUpdateArtifactMismatch>()),
    );
    await expectLater(
      AttachedUpdateDeltaApplier(
        decodePatch: (_, _, _, _, _) async => fail('must not decode'),
      ).apply(
        AttachedUpdateArtifact(
          compression: AttachedUpdateCompression.zstdPatch,
          size: artifact.size,
          sha256: artifact.sha256,
          parts: artifact.parts,
        ),
        path('p'),
        path('missing.db'),
        path('out.db'),
      ),
      throwsA(isA<AttachedUpdateArtifactMismatch>()),
    );
  });

  test('a cancel raised while applying stops the decode', () async {
    if (zstd == null) return markTestSkipped('zstd / libzstd not available');
    final artifact = await fixture();
    final before = sha256.convert(File(path('old.db')).readAsBytesSync());
    final cancel = AttachedUpdateCancelToken();
    final cancelled = Completer<void>();
    cancel.onCancel(cancelled.complete);
    final running = Completer<void>();
    final real = _decodeWith(zstd!.lib);
    final applier = AttachedUpdateDeltaApplier(
      decodePatch: (patch, base, output, max, flag) async {
        // The token is cancelled only once apply() is under way, so the
        // flag has to reach the decode loop through the subscription.
        running.complete();
        await cancelled.future;
        return real(patch, base, output, max, flag);
      },
    );
    final done = applier.apply(
      artifact,
      path('patch.zst'),
      path('old.db'),
      path('out.db'),
      cancel: cancel,
    );
    await running.future;
    cancel.cancel();
    await expectLater(done, throwsA(isA<AttachedUpdateCancelled>()));
    // The decode stopped instead of producing the (valid) patched file.
    expect(File(path('out.db')).existsSync(), isFalse);
    expect(sha256.convert(File(path('old.db')).readAsBytesSync()), before);
  });

  test('a failure opening the output leaves no open handle behind', () async {
    if (zstd == null) return markTestSkipped('zstd / libzstd not available');
    await fixture();
    // A directory in place of the output file makes openSync throw.
    Directory(path('out.db')).createSync();
    expect(
      () => decodePatchSyncForTest(
        path('patch.zst'),
        path('old.db'),
        path('out.db'),
        DynamicLibrary.open(zstd!.lib),
      ),
      throwsA(anything),
    );
    // Both would fail on Windows if the patch handle or the mapping leaked.
    File(path('patch.zst')).deleteSync();
    File(path('old.db')).deleteSync();
  });
}
