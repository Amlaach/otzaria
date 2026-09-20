import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/models/attached_update_manifest.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_artifact_builder.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_fetcher.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_host_policy.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_signature.dart';
import 'package:otzaria/utils/file/zstd_stream_extractor_io.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../../tool/src/personal_db_update_tool.dart';
import '../../tool/src/personal_db_validator.dart';
import '../helpers/seforim_fixture_db.dart';

/// zstd בשורת הפקודה ו-libzstd לפענוח ב-FFI; null כשאחד חסר (הבדיקה מדלגת).
({String exe, DynamicLibrary lib, String libPath})? _findZstd() {
  final which = Process.runSync(Platform.isWindows ? 'where' : 'which', [
    'zstd',
  ]);
  if (which.exitCode != 0) return null;
  final exe = (which.stdout as String).split(RegExp(r'[\r\n]+')).first.trim();
  final dir = p.dirname(File(exe).resolveSymbolicLinksSync());
  final candidates = [
    ?Platform.environment['LIBZSTD_PATH'],
    p.join(dir, 'dll', 'libzstd.dll'),
    p.join(dir, 'libzstd.dll'),
    'libzstd.so.1',
    'libzstd.so',
    '/opt/homebrew/lib/libzstd.dylib',
    '/usr/local/lib/libzstd.dylib',
  ];
  for (final candidate in candidates) {
    try {
      return (
        exe: exe,
        lib: DynamicLibrary.open(candidate),
        libPath: candidate,
      );
    } catch (_) {}
  }
  return null;
}

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('otzaria_update_tool');
  });

  tearDown(() async {
    try {
      await temp.delete(recursive: true);
    } catch (_) {}
  });

  String makeDb({
    required String publicKey,
    int bytes = 200000,
    String name = 'lib.db',
    String version = '3',
  }) {
    final path = p.join(temp.path, name);
    final db = sqlite3.open(path);
    db.execute('CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT)');
    db.execute('CREATE TABLE filler (data BLOB)');
    for (final entry in {
      'library_id': 'my-lib',
      'db_version': version,
      'update_manifest_url': 'https://example.org/lib/manifest.json',
      'update_public_key': publicKey,
    }.entries) {
      db.execute('INSERT INTO schema_meta VALUES (?, ?)', [
        entry.key,
        entry.value,
      ]);
    }
    db.execute('INSERT INTO filler VALUES (randomblob(?))', [bytes]);
    db.close();
    return path;
  }

  test('keygen writes a key and refuses to overwrite it', () {
    final keyPath = p.join(temp.path, 'k.key');
    final publicKey = keygen(keyPath);
    expect(
      AttachedUpdateSignature.publicKeyOf(File(keyPath).readAsStringSync()),
      publicKey,
    );
    expect(() => keygen(keyPath), throwsA(isA<UpdateToolException>()));
    expect(keygen(keyPath, force: true), isNot(publicKey));
  });

  test('pack (split) + sign + verify, and tampering is caught', () async {
    final keyPath = p.join(temp.path, 'k.key');
    final publicKey = keygen(keyPath);
    final db = makeDb(publicKey: publicKey);
    final out = p.join(temp.path, 'out');
    final result = await pack(
      dbPath: db,
      outDir: out,
      urlPrefix: 'https://example.org/releases/v3',
      partSize: 50000,
      compression: AttachedUpdateCompression.none,
      releaseNotes: 'fixes',
    );
    expect(result.warnings, isEmpty);
    final manifest = result.manifest;
    expect(manifest.libraryId, 'my-lib');
    expect(manifest.dbVersion, 3);
    expect(manifest.full.parts.length, greaterThan(1));
    expect(
      manifest.full.parts.first.url,
      'https://example.org/releases/v3/my-lib-3.db.001',
    );

    sign(result.manifestPath, keyPath);
    final verified = await verify(
      manifestPath: result.manifestPath,
      publicKey: publicKey,
      expectedLibraryId: 'my-lib',
      partsDir: out,
    );
    expect(verified.toJson(), manifest.toJson());

    final otherKey = AttachedUpdateSignature.publicKeyOf(
      AttachedUpdateSignature.generatePrivateKey(),
    );
    await expectLater(
      verify(manifestPath: result.manifestPath, publicKey: otherKey),
      throwsA(isA<UpdateToolException>()),
    );
    await expectLater(
      verify(
        manifestPath: result.manifestPath,
        publicKey: publicKey,
        expectedLibraryId: 'other',
      ),
      throwsA(isA<UpdateToolException>()),
    );

    final partFile = File(result.partPaths.last);
    partFile.writeAsBytesSync([...partFile.readAsBytesSync()]..[0] ^= 1);
    await expectLater(
      verify(
        manifestPath: result.manifestPath,
        publicKey: publicKey,
        partsDir: out,
      ),
      throwsA(isA<UpdateToolException>()),
    );

    final manifestFile = File(result.manifestPath);
    manifestFile.writeAsStringSync(
      manifestFile.readAsStringSync().replaceFirst(
        '"db_version": 3',
        '"db_version": 4',
      ),
    );
    await expectLater(
      verify(manifestPath: result.manifestPath, publicKey: publicKey),
      throwsA(isA<UpdateToolException>()),
    );
  });

  test('pack warns when the database declares no update source', () async {
    final db = makeDb(publicKey: 'not-a-key');
    final result = await pack(
      dbPath: db,
      outDir: p.join(temp.path, 'out'),
      urlPrefix: 'https://example.org/v3/',
      compression: AttachedUpdateCompression.none,
    );
    expect(result.warnings.single, contains('update_public_key'));
    await expectLater(
      pack(
        dbPath: db,
        outDir: p.join(temp.path, 'out2'),
        urlPrefix: 'http://example.org/v3/',
        compression: AttachedUpdateCompression.none,
      ),
      throwsA(isA<UpdateToolException>()),
    );
  });

  group('round trip: pack output -> download -> build', () {
    late HttpServer server;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final file = File(
          p.join(temp.path, 'out', p.basename(request.uri.path)),
        );
        if (file.existsSync()) {
          request.response.add(file.readAsBytesSync());
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    Future<String> downloadAndBuild(
      AttachedUpdateManifest manifest,
      AttachedUpdateArtifactBuilder builder,
    ) async {
      // המניפסט מכריז על https; בבדיקה החלקים מוגשים מהשרת המקומי באותו שם.
      final local = [
        for (final part in manifest.full.parts)
          AttachedUpdatePart(
            url:
                'http://127.0.0.1:${server.port}/'
                '${Uri.parse(part.url).pathSegments.last}',
            size: part.size,
            sha256: part.sha256,
          ),
      ];
      final fetcher = AttachedUpdateFetcher(
        policy: AttachedUpdateHostPolicy.allowLoopbackForTesting({server.port}),
      );
      final combined = p.join(temp.path, 'download.part');
      final output = p.join(temp.path, 'new.db');
      await fetcher.downloadParts(local, combined);
      await builder.build(manifest.full, combined, output);
      return output;
    }

    test('uncompressed, split into parts', () async {
      final db = makeDb(publicKey: keygen(p.join(temp.path, 'k.key')));
      final result = await pack(
        dbPath: db,
        outDir: p.join(temp.path, 'out'),
        urlPrefix: 'https://example.org/v3',
        partSize: 40000,
        compression: AttachedUpdateCompression.none,
      );
      final output = await downloadAndBuild(
        result.manifest,
        const AttachedUpdateArtifactBuilder(),
      );
      expect(File(output).readAsBytesSync(), File(db).readAsBytesSync());
    });

    test('zstd, split into parts, streamed FFI decompression', () async {
      final zstd = _findZstd();
      if (zstd == null) {
        markTestSkipped('zstd / libzstd not available');
        return;
      }
      final db = makeDb(publicKey: keygen(p.join(temp.path, 'k.key')));
      final result = await pack(
        dbPath: db,
        outDir: p.join(temp.path, 'out'),
        urlPrefix: 'https://example.org/v3',
        partSize: 30000,
        level: 3,
        zstdExecutable: zstd.exe,
      );
      expect(result.manifest.full.parts.length, greaterThan(1));
      final builder = AttachedUpdateArtifactBuilder(
        decompress: (archive, output, max) async => decompressSyncForTest(
          archive,
          output,
          zstd.lib,
          maxOutputBytes: max,
        ),
      );
      final output = await downloadAndBuild(result.manifest, builder);
      expect(File(output).readAsBytesSync(), File(db).readAsBytesSync());
      expect(File(p.join(temp.path, 'download.part')).existsSync(), isFalse);
    });

    test('final sha256 mismatch deletes the output', () async {
      final db = makeDb(publicKey: keygen(p.join(temp.path, 'k.key')));
      final result = await pack(
        dbPath: db,
        outDir: p.join(temp.path, 'out'),
        urlPrefix: 'https://example.org/v3',
        compression: AttachedUpdateCompression.none,
      );
      final full = result.manifest.full;
      final lying = AttachedUpdateManifest(
        libraryId: 'my-lib',
        dbVersion: 3,
        full: AttachedUpdateArtifact(
          compression: full.compression,
          size: full.size,
          sha256: 'e' * 64,
          parts: full.parts,
        ),
      );
      await expectLater(
        downloadAndBuild(lying, const AttachedUpdateArtifactBuilder()),
        throwsA(isA<AttachedUpdateArtifactMismatch>()),
      );
      expect(File(p.join(temp.path, 'new.db')).existsSync(), isFalse);
    });
  });

  group('validator reports update fields', () {
    String fixture(Map<String, String> meta) {
      final dir = Directory(p.join(temp.path, 'v${meta.length}'))
        ..createSync(recursive: true);
      final path = SeforimFixtureDb.create(dir, SeforimFixtureVariant.full);
      final db = sqlite3.open(path);
      for (final entry in meta.entries) {
        db.execute('INSERT OR REPLACE INTO schema_meta VALUES (?, ?)', [
          entry.key,
          entry.value,
        ]);
      }
      db.close();
      return path;
    }

    Set<String> codes(PersonalDbReport r) => {for (final i in r.issues) i.code};

    test('no update fields: info only', () {
      final report = validatePersonalDb(fixture({}), checkFiles: false);
      expect(report.updatesEnabled, isFalse);
      expect(codes(report), contains('no_update_source'));
    });

    test('valid update fields', () {
      final report = validatePersonalDb(
        fixture({
          'library_id': 'my-lib',
          'db_version': '5',
          'update_manifest_url': 'https://example.org/m.json',
          'update_public_key': AttachedUpdateSignature.publicKeyOf(
            AttachedUpdateSignature.generatePrivateKey(),
          ),
        }),
        checkFiles: false,
      );
      expect(report.updatesEnabled, isTrue);
      expect(codes(report), isNot(contains('update_source_invalid')));
      expect(formatReport(report), contains('signed, from example.org'));
    });

    test('invalid update fields are warnings, not errors', () {
      final report = validatePersonalDb(
        fixture({
          'library_id': 'my-lib',
          'db_version': 'v5',
          'update_manifest_url': 'http://example.org/m.json',
          'update_public_key': 'short',
          'extra': 'x',
        }),
        checkFiles: false,
      );
      expect(report.updatesEnabled, isFalse);
      final warnings = [
        for (final i in report.issues)
          if (i.code == 'update_source_invalid') i,
      ];
      expect(warnings, hasLength(3));
      expect(warnings.every((i) => i.severity == Severity.warning), isTrue);
    });
  });

  group('delta artifacts', () {
    /// עותק של [oldDb] עם db_version חדש ושורה קטנה נוספת — תיקון קטן.
    String evolve(String oldDb, String version) {
      final path = p.join(temp.path, 'new-$version.db');
      File(oldDb).copySync(path);
      final db = sqlite3.open(path);
      db.execute('UPDATE schema_meta SET value = ? WHERE key = ?', [
        version,
        'db_version',
      ]);
      db.execute('INSERT INTO filler VALUES (?)', ['small change']);
      db.close();
      return path;
    }

    test('pack --delta-from + verify applies the patch', () async {
      final zstd = _findZstd();
      if (zstd == null) {
        markTestSkipped('zstd / libzstd not available');
        return;
      }
      final keyPath = p.join(temp.path, 'k.key');
      final publicKey = keygen(keyPath);
      final old = makeDb(publicKey: publicKey, version: '2', name: 'old.db');
      final updated = evolve(old, '3');
      final out = p.join(temp.path, 'out');

      final result = await pack(
        dbPath: updated,
        outDir: out,
        urlPrefix: 'https://example.org/releases/v3',
        level: 3,
        zstdExecutable: zstd.exe,
        deltaFrom: [old],
      );
      expect(result.warnings, isEmpty);
      final delta = result.manifest.deltas.single;
      expect(delta.fromDbVersion, 2);
      expect(delta.artifact.compression, AttachedUpdateCompression.zstdPatch);
      expect(delta.artifact.size, result.manifest.full.size);
      expect(delta.artifact.sha256, result.manifest.full.sha256);
      expect(
        delta.artifact.compressedSize,
        lessThan(result.manifest.full.compressedSize),
      );

      sign(result.manifestPath, keyPath);
      final verified = await verify(
        manifestPath: result.manifestPath,
        publicKey: publicKey,
        partsDir: out,
        deltaFrom: [old],
        zstdLibraryPath: zstd.libPath,
      );
      expect(verified.deltas, hasLength(1));
    });

    test('verify without the matching base fails', () async {
      final zstd = _findZstd();
      if (zstd == null) {
        markTestSkipped('zstd / libzstd not available');
        return;
      }
      final keyPath = p.join(temp.path, 'k.key');
      final publicKey = keygen(keyPath);
      final old = makeDb(publicKey: publicKey, version: '2', name: 'old.db');
      final updated = evolve(old, '3');
      final out = p.join(temp.path, 'out');
      final result = await pack(
        dbPath: updated,
        outDir: out,
        urlPrefix: 'https://example.org/releases/v3',
        level: 3,
        zstdExecutable: zstd.exe,
        deltaFrom: [old],
      );
      sign(result.manifestPath, keyPath);
      await expectLater(
        verify(
          manifestPath: result.manifestPath,
          publicKey: publicKey,
          partsDir: out,
          zstdLibraryPath: zstd.libPath,
        ),
        throwsA(isA<UpdateToolException>()),
      );
    });

    test('--delta-from of another library is an error', () async {
      final publicKey = keygen(p.join(temp.path, 'k.key'));
      final old = makeDb(publicKey: publicKey, version: '2', name: 'old.db');
      final db = sqlite3.open(old);
      db.execute("UPDATE schema_meta SET value = 'other' WHERE key = ?", [
        'library_id',
      ]);
      db.close();
      await expectLater(
        pack(
          dbPath: makeDb(publicKey: publicKey, name: 'new.db'),
          outDir: p.join(temp.path, 'out'),
          urlPrefix: 'https://example.org/releases/v3',
          compression: AttachedUpdateCompression.none,
          deltaFrom: [old],
        ),
        throwsA(isA<UpdateToolException>()),
      );
    });
  });
}
