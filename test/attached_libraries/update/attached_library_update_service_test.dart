import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/models/attached_library_update_status.dart';
import 'package:otzaria/attached_libraries/models/attached_update_manifest.dart';
import 'package:otzaria/attached_libraries/repository/attached_libraries_repository.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_probe.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_library_update_service.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_downloader.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_fetcher.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_file_swap.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_signature.dart';
import 'package:otzaria/plugins/services/plugin_settings_access_policy.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/utils/file/disk_free_space.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../../helpers/seforim_fixture_db.dart';
import '../../test_helpers/memory_cache_provider.dart';

const _url = 'https://updates.example.org/lib/manifest.json';

class _FakeFetcher extends AttachedUpdateFetcher {
  Uint8List manifest = Uint8List(0);
  Uint8List signature = Uint8List(0);
  int calls = 0;

  @override
  Future<({Uint8List manifest, Uint8List signature})> fetchSignedManifest(
    String manifestUrl, {
    AttachedUpdateCancelToken? cancel,
  }) async {
    calls++;
    return (manifest: manifest, signature: signature);
  }
}

/// Copies a prepared database to the output instead of downloading.
class _FakeDownloader extends AttachedUpdateDownloader {
  String? source;
  int calls = 0;
  Completer<void>? hold;
  final started = Completer<void>();

  @override
  Future<void> download(
    AttachedUpdateArtifact artifact, {
    required String combinedPath,
    required String outputPath,
    AttachedUpdateProgress? onProgress,
    AttachedUpdateCancelToken? cancel,
  }) async {
    calls++;
    onProgress?.call(1, 2);
    final gate = hold;
    if (gate != null) {
      await File(combinedPath).writeAsBytes([1, 2, 3]);
      started.complete();
      cancel?.onCancel(() {
        if (!gate.isCompleted) {
          gate.completeError(const AttachedUpdateCancelled());
        }
      });
      await gate.future;
    }
    await File(source!).copy(outputPath);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late AttachedLibraryRegistry registry;
  late AttachedLibrariesRepository repository;
  late _FakeFetcher fetcher;
  late _FakeDownloader downloader;
  late String privateKey;
  late String publicKey;
  var counter = 0;
  var freeBytes = 1 << 40;
  var offline = false;
  var enabled = true;
  var due = true;
  var recorded = 0;

  AttachedLibraryUpdateService service() => AttachedLibraryUpdateService(
    repository: repository,
    fetcher: fetcher,
    downloader: downloader,
    probe: (path) async => AttachedLibraryProbe.probeSync(path),
    swap: const AttachedUpdateFileSwap(lockRetries: 1),
    diskSpace: (_) async => DiskSpaceInfo(volumeId: 'V', freeBytes: freeBytes),
    workDirectory: () async => p.join(temp.path, 'work'),
    isOfflineMode: () => offline,
    areUpdatesEnabled: () => enabled,
    isAutoCheckDue: () => due,
    recordCheck: () async => recorded++,
  );

  /// A fixture database; [meta] overrides schema_meta rows.
  String database({
    String version = '1',
    String libraryId = 'my-lib',
    String? key,
    String? dir,
  }) {
    final folder = Directory(dir ?? p.join(temp.path, 'db${counter++}'))
      ..createSync(recursive: true);
    final created = SeforimFixtureDb.create(
      Directory(p.join(temp.path, 'raw${counter++}'))..createSync(),
      SeforimFixtureVariant.full,
    );
    final path = p.join(folder.path, 'lib.db');
    File(created).copySync(path);
    final db = sqlite3.sqlite3.open(path);
    final meta = {
      'library_id': libraryId,
      'db_version': version,
      'update_manifest_url': _url,
      'update_public_key': key ?? publicKey,
    };
    for (final entry in meta.entries) {
      db.execute('DELETE FROM schema_meta WHERE key = ?', [entry.key]);
      db.execute('INSERT INTO schema_meta VALUES (?, ?)', [
        entry.key,
        entry.value,
      ]);
    }
    db.close();
    return path;
  }

  void publish(String newDb, {int version = 2, String signWith = ''}) {
    final bytes = File(newDb).readAsBytesSync();
    final manifest = AttachedUpdateManifest(
      libraryId: 'my-lib',
      dbVersion: version,
      releaseNotes: 'notes',
      full: AttachedUpdateArtifact(
        compression: AttachedUpdateCompression.none,
        size: bytes.length,
        sha256: sha256.convert(bytes).toString(),
        parts: [
          AttachedUpdatePart(
            url: 'https://updates.example.org/lib/part1',
            size: bytes.length,
            sha256: sha256.convert(bytes).toString(),
          ),
        ],
      ),
    );
    fetcher.manifest = Uint8List.fromList(
      utf8.encode(jsonEncode(manifest.toJson())),
    );
    fetcher.signature = Uint8List.fromList(
      ascii.encode(
        AttachedUpdateSignature.sign(
          fetcher.manifest,
          signWith.isEmpty ? privateKey : signWith,
        ),
      ),
    );
    downloader.source = newDb;
  }

  Future<AttachedLibrary> attach(
    String path, {
    AttachedLibraryMode? mode,
  }) async {
    final result = await repository.importFile(path, mode: mode);
    expect(result.isOk, isTrue, reason: '${result.problem}');
    return result.library!;
  }

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    temp = await Directory.systemTemp.createTemp('otzaria_attached_upd');
    registry = AttachedLibraryRegistry(idleTimeout: null);
    repository = AttachedLibrariesRepository(
      registry: registry,
      probe: (path) async => AttachedLibraryProbe.probeSync(path),
      copyDirectory: () async => p.join(temp.path, 'copies'),
      copyByDefault: false,
    );
    fetcher = _FakeFetcher();
    downloader = _FakeDownloader();
    privateKey = AttachedUpdateSignature.generatePrivateKey();
    publicKey = AttachedUpdateSignature.publicKeyOf(privateKey);
    freeBytes = 1 << 40;
    offline = false;
    enabled = true;
    due = true;
    recorded = 0;
  });

  tearDown(() async {
    await registry.closeAll();
    try {
      await temp.delete(recursive: true);
    } catch (_) {}
  });

  group('scheduled check', () {
    Future<AttachedLibraryUpdateService> runWith({
      bool off = false,
      bool on = true,
      bool isDue = true,
    }) async {
      await attach(database());
      publish(database(version: '2'));
      offline = off;
      enabled = on;
      due = isDue;
      final svc = service();
      await svc.runScheduledCheck();
      return svc;
    }

    test('offline mode ⇒ no network', () async {
      await runWith(off: true);
      expect(fetcher.calls, 0);
    });

    test('updates disabled ⇒ no network', () async {
      await runWith(on: false);
      expect(fetcher.calls, 0);
    });

    test('not due by cadence ⇒ no network', () async {
      await runWith(isDue: false);
      expect(fetcher.calls, 0);
      expect(recorded, 0);
    });

    test('enabled and due ⇒ offer found and the check recorded', () async {
      final svc = await runWith();
      expect(fetcher.calls, 1);
      expect(recorded, 1);
      final status = svc.statusOf(repository.libraries.single);
      expect(status, isA<AttachedUpdateAvailable>());
    });

    test('a database with a changed source is never contacted', () async {
      final path = database();
      await attach(path);
      final db = sqlite3.sqlite3.open(path);
      db.execute(
        "UPDATE schema_meta SET value = 'https://other.example.net/m.json' "
        "WHERE key = 'update_manifest_url'",
      );
      db.close();
      File(path).setLastModifiedSync(
        DateTime.now().add(const Duration(minutes: 1)),
      );
      await repository.rescan();
      expect(repository.libraries.single.updateSourceMismatch, isTrue);
      await service().runScheduledCheck();
      expect(fetcher.calls, 0);
    });
  });

  group('manual check', () {
    test(
      'newer signed version ⇒ available, persisted for next session',
      () async {
        final library = await attach(database());
        publish(database(version: '2'));
        final svc = service();
        final status = await svc.check(library);
        expect(status, isA<AttachedUpdateAvailable>());
        expect(status.offer!.dbVersion, 2);
        expect(status.offer!.domain, 'updates.example.org');
        expect(status.offer!.releaseNotes, 'notes');

        final next = service();
        await next.restorePending();
        expect(next.statusOf(library), isA<AttachedUpdateAvailable>());
      },
    );

    test('same version ⇒ up to date', () async {
      final library = await attach(database());
      publish(database(), version: 1);
      expect(await service().check(library), isA<AttachedUpdateUpToDate>());
    });

    test('signed by another key ⇒ rejected', () async {
      final library = await attach(database());
      publish(
        database(version: '2'),
        signWith: AttachedUpdateSignature.generatePrivateKey(),
      );
      final status = await service().check(library);
      expect(
        status,
        const AttachedUpdateFailed(AttachedUpdateError.badSignature),
      );
    });

    test('offline ⇒ refused without network', () async {
      final library = await attach(database());
      offline = true;
      expect(
        await service().check(library),
        const AttachedUpdateFailed(AttachedUpdateError.offline),
      );
      expect(fetcher.calls, 0);
    });
  });

  group('install', () {
    Future<(AttachedLibraryUpdateService, AttachedLibrary)> offered(
      String newDb, {
      AttachedLibraryMode mode = AttachedLibraryMode.link,
      int version = 2,
    }) async {
      final library = await attach(database(), mode: mode);
      publish(newDb, version: version);
      final svc = service();
      expect(await svc.check(library), isA<AttachedUpdateAvailable>());
      return (svc, library);
    }

    void expectNoLeftovers(String target) {
      expect(
        File(AttachedUpdateFileSwap.backupPathFor(target)).existsSync(),
        isFalse,
      );
      expect(
        File(AttachedUpdateFileSwap.stagedPathFor(target)).existsSync(),
        isFalse,
      );
    }

    test('link mode: replaced in place and refreshed', () async {
      final (svc, library) = await offered(database(version: '2'));
      final changed = repository.changes.first;
      await svc.install(library);
      expect(svc.statusOf(library), const AttachedUpdateInstalled(2));
      final updated = repository.libraries.single;
      expect(updated.path, library.path);
      expect(updated.fingerprint!.dbVersion, '2');
      expect(await changed, contains(library.slug));
      expectNoLeftovers(library.path);
      expect(
        AttachedLibraryProbe.probeSync(library.path).fingerprint!.dbVersion,
        '2',
      );
    });

    test('copy mode: replaced inside the managed folder', () async {
      final (svc, library) = await offered(
        database(version: '2'),
        mode: AttachedLibraryMode.copy,
      );
      expect(p.isWithin(p.join(temp.path, 'copies'), library.path), isTrue);
      await svc.install(library);
      expect(svc.statusOf(library), const AttachedUpdateInstalled(2));
      expect(repository.libraries.single.fingerprint!.dbVersion, '2');
      expectNoLeftovers(library.path);
    });

    test('an open handle is released before the swap', () async {
      final (svc, library) = await offered(database(version: '2'));
      expect(await registry.repositoryFor(library.slug), isNotNull);
      expect(registry.isOpen(library.slug), isTrue);
      await svc.install(library);
      expect(svc.statusOf(library), const AttachedUpdateInstalled(2));
    });

    Future<void> expectRejected(String newDb, {int version = 2}) async {
      final (svc, library) = await offered(newDb, version: version);
      final before = File(library.path).readAsBytesSync();
      await svc.install(library);
      final status = svc.statusOf(library);
      expect(status, isA<AttachedUpdateFailed>());
      expect(
        (status as AttachedUpdateFailed).error,
        AttachedUpdateError.verifyFailed,
      );
      expect(status.offer, isNotNull);
      expect(File(library.path).readAsBytesSync(), before);
      expect(repository.libraries.single.fingerprint!.dbVersion, '1');
      expectNoLeftovers(library.path);
    }

    test('the version on disk, not the cached one, blocks a replay', () async {
      final (svc, library) = await offered(database(version: '2'));
      final db = sqlite3.sqlite3.open(library.path);
      db.execute(
        "UPDATE schema_meta SET value = '3' WHERE key = 'db_version'",
      );
      db.close();
      await svc.install(library);
      expect(svc.statusOf(library), isA<AttachedUpdateFailed>());
      expect(
        AttachedLibraryProbe.probeSync(library.path).fingerprint!.dbVersion,
        '3',
      );
    });

    test('corrupt new file ⇒ old file kept', () async {
      final junk = p.join(temp.path, 'junk.db');
      File(junk).writeAsBytesSync(List.filled(4096, 7));
      await expectRejected(junk);
    });

    test('new file with another key ⇒ old file kept', () async {
      final otherKey = AttachedUpdateSignature.publicKeyOf(
        AttachedUpdateSignature.generatePrivateKey(),
      );
      await expectRejected(database(version: '2', key: otherKey));
    });

    test('new file with another library_id ⇒ old file kept', () async {
      await expectRejected(database(version: '2', libraryId: 'other-lib'));
    });

    test(
      'new file at another version than the manifest ⇒ old file kept',
      () async {
        await expectRejected(database(version: '3'));
      },
    );

    test('not enough disk space ⇒ nothing downloaded', () async {
      final (svc, library) = await offered(database(version: '2'));
      freeBytes = 1024;
      await svc.install(library);
      final status = svc.statusOf(library) as AttachedUpdateFailed;
      expect(status.error, AttachedUpdateError.noSpace);
      expect(status.requiredBytes, greaterThan(1024));
      expect(downloader.calls, 0);
      expectNoLeftovers(library.path);
    });

    test('missing file (drive gone) ⇒ clear error', () async {
      final (svc, library) = await offered(database(version: '2'));
      File(library.path).deleteSync();
      await svc.install(library);
      expect(
        (svc.statusOf(library) as AttachedUpdateFailed).error,
        AttachedUpdateError.fileMissing,
      );
    });

    test('cancel mid-download ⇒ offer kept, temp files removed', () async {
      final (svc, library) = await offered(database(version: '2'));
      downloader.hold = Completer<void>();
      final running = svc.install(library);
      await downloader.started.future;
      expect(svc.statusOf(library), isA<AttachedUpdateInProgress>());
      svc.cancel(library);
      await running;
      expect(svc.statusOf(library), isA<AttachedUpdateAvailable>());
      expectNoLeftovers(library.path);
      final work = Directory(p.join(temp.path, 'work'));
      expect(
        work.existsSync() ? work.listSync() : const <FileSystemEntity>[],
        isEmpty,
      );
      expect(repository.libraries.single.fingerprint!.dbVersion, '1');
    });
  });

  group('swap and crash recovery', () {
    test('rejected after the swap ⇒ backup restored', () async {
      final library = await attach(database());
      final before = File(library.path).readAsBytesSync();
      final staged = AttachedUpdateFileSwap.stagedPathFor(library.path);
      File(database(version: '2')).copySync(staged);
      await expectLater(
        repository.installUpdate(library, staged, accept: (_) => false),
        throwsA(isA<AttachedUpdateVerificationFailed>()),
      );
      expect(File(library.path).readAsBytesSync(), before);
      expect(
        File(AttachedUpdateFileSwap.backupPathFor(library.path)).existsSync(),
        isFalse,
      );
    });

    test('crash after the swap ⇒ old file restored on next start', () async {
      final library = await attach(database());
      final before = File(library.path).readAsBytesSync();
      final backup = AttachedUpdateFileSwap.backupPathFor(library.path);
      File(library.path).renameSync(backup);
      File(database(version: '2')).copySync(library.path);
      File('${library.path}-wal').writeAsBytesSync([1]);
      File(
        AttachedUpdateFileSwap.stagedPathFor(library.path),
      ).writeAsBytesSync([1]);

      await repository.recoverInterruptedUpdates();
      expect(File(library.path).readAsBytesSync(), before);
      expect(File(backup).existsSync(), isFalse);
      expect(File('${library.path}-wal').existsSync(), isFalse);
      expect(
        File(AttachedUpdateFileSwap.stagedPathFor(library.path)).existsSync(),
        isFalse,
      );
    });

    test('crash between the two renames ⇒ backup moved back', () async {
      final library = await attach(database());
      final before = File(library.path).readAsBytesSync();
      File(library.path).renameSync(
        AttachedUpdateFileSwap.backupPathFor(library.path),
      );
      await repository.recoverInterruptedUpdates();
      expect(File(library.path).readAsBytesSync(), before);
    });

    test('side files of the old database move with the backup', () async {
      final library = await attach(database());
      File('${library.path}-wal').writeAsBytesSync([9]);
      final staged = AttachedUpdateFileSwap.stagedPathFor(library.path);
      File(database(version: '2')).copySync(staged);
      await const AttachedUpdateFileSwap().swapIn(library.path, staged);
      expect(File('${library.path}-wal').existsSync(), isFalse);
      expect(
        File(
          '${AttachedUpdateFileSwap.backupPathFor(library.path)}-wal',
        ).existsSync(),
        isTrue,
      );
    });
  });

  test('pending offers are hidden from plugins', () {
    expect(
      PluginSettingsAccessPolicy.isBlocked(
        SettingsRepository.keyAttachedLibraryPendingUpdates,
      ),
      isTrue,
    );
  });
}
