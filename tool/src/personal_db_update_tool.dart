import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:otzaria/attached_libraries/models/attached_library_update_source.dart';
import 'package:otzaria/attached_libraries/models/attached_update_manifest.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_artifact_builder.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_artifact_planner.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_delta_applier.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_signature.dart';
import 'package:otzaria/utils/file/zstd_patch_decoder.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// שגיאת שימוש או קלט — מודפסת כמו שהיא, בלי stack trace.
class UpdateToolException implements Exception {
  final String message;
  const UpdateToolException(this.message);

  @override
  String toString() => message;
}

/// מתחת למגבלת 2 GiB לקובץ ב-GitHub Releases.
const int kDefaultPartSize = 1900 * 1024 * 1024;

/// החלון המרבי שמפענח ה-zstd באוצריא מקבל בלי הגדרה מיוחדת (2^27).
const int kZstdMaxWindowLog = 27;

/// תיקוני דלתא מפוענחים עם `ZSTD_d_windowLogMax = 31` — 2GiB, תקרת הקובץ הישן.
const int kZstdPatchWindowLog = 31;

/// מספר מקורות ה-`--delta-from` לפרסום אחד; הרבה מתחת ל-`maxDeltas`.
const int kMaxDeltaSources = 4;

/// ערכי schema_meta שהכלי קורא מהמסד.
class PersonalDbUpdateMeta {
  final String? libraryId;
  final String? dbVersion;
  final String? manifestUrl;
  final String? publicKey;

  const PersonalDbUpdateMeta({
    this.libraryId,
    this.dbVersion,
    this.manifestUrl,
    this.publicKey,
  });

  static PersonalDbUpdateMeta read(String dbPath) {
    final db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
    try {
      final rows = db.select(
        "SELECT key, value FROM schema_meta WHERE key IN ('library_id', "
        "'db_version', '${AttachedLibraryUpdateSource.metaManifestUrlKey}', "
        "'${AttachedLibraryUpdateSource.metaPublicKeyKey}')",
      );
      final meta = {
        for (final row in rows)
          row['key'] as String: row['value']?.toString().trim(),
      };
      return PersonalDbUpdateMeta(
        libraryId: meta['library_id'],
        dbVersion: meta['db_version'],
        manifestUrl: meta[AttachedLibraryUpdateSource.metaManifestUrlKey],
        publicKey: meta[AttachedLibraryUpdateSource.metaPublicKeyKey],
      );
    } on SqliteException catch (e) {
      throw UpdateToolException('Cannot read schema_meta: ${e.message}');
    } finally {
      db.close();
    }
  }
}

/// יוצר מפתח חדש ל-[privateKeyPath] ומחזיר את המפתח הציבורי.
String keygen(String privateKeyPath, {bool force = false}) {
  final file = File(privateKeyPath);
  if (file.existsSync() && !force) {
    throw UpdateToolException(
      '$privateKeyPath already exists. Losing or replacing the key means every '
      'user must re-attach the database; pass --force to overwrite.',
    );
  }
  final privateKey = AttachedUpdateSignature.generatePrivateKey();
  file.writeAsStringSync('$privateKey\n');
  return AttachedUpdateSignature.publicKeyOf(privateKey);
}

class PackResult {
  final AttachedUpdateManifest manifest;
  final String manifestPath;
  final List<String> partPaths;
  final List<String> warnings;

  const PackResult(
    this.manifest,
    this.manifestPath,
    this.partPaths,
    this.warnings,
  );
}

/// דוחס (zstd חיצוני) ומפצל את [dbPath] ל-[outDir], וכותב `manifest.json`.
/// [dbVersion]/[libraryId] — ברירת המחדל מ-schema_meta של המסד.
Future<PackResult> pack({
  required String dbPath,
  required String outDir,
  required String urlPrefix,
  int partSize = kDefaultPartSize,
  AttachedUpdateCompression compression = AttachedUpdateCompression.zstd,
  int level = 19,
  String zstdExecutable = 'zstd',
  String? releaseNotes,
  String? libraryId,
  int? dbVersion,
  List<String> deltaFrom = const [],
}) async {
  if (!File(dbPath).existsSync()) {
    throw UpdateToolException('No such file: $dbPath');
  }
  if (partSize < 1) throw const UpdateToolException('--part-size must be > 0');
  if (deltaFrom.length > kMaxDeltaSources) {
    throw const UpdateToolException(
      '--delta-from may be given at most $kMaxDeltaSources times',
    );
  }
  final prefix = urlPrefix.endsWith('/') ? urlPrefix : '$urlPrefix/';
  if (!AttachedLibraryUpdateSource.isValidManifestUrl('${prefix}x')) {
    throw const UpdateToolException('--url-prefix must be an https URL');
  }
  final meta = PersonalDbUpdateMeta.read(dbPath);
  final id = libraryId ?? meta.libraryId;
  if (id == null || id.isEmpty) {
    throw const UpdateToolException(
      'The database has no schema_meta.library_id (or pass --library-id).',
    );
  }
  final version = dbVersion ?? int.tryParse(meta.dbVersion ?? '');
  if (version == null || version < 1) {
    throw const UpdateToolException(
      'schema_meta.db_version must be a positive integer (or pass --db-version).',
    );
  }
  final warnings = <String>[
    if (libraryId != null && libraryId != meta.libraryId)
      'library_id in the database is "${meta.libraryId}", not "$libraryId".',
    if (dbVersion != null && '$dbVersion' != meta.dbVersion)
      'db_version in the database is "${meta.dbVersion}", not "$dbVersion" — '
          'after installing, Otzaria would offer this update again.',
    if (AttachedLibraryUpdateSource.fromMeta(
          libraryId: id,
          manifestUrl: meta.manifestUrl,
          publicKey: meta.publicKey,
        ) ==
        null)
      'The database does not declare a valid update_manifest_url and '
          'update_public_key; once installed, it will not receive further '
          'updates.',
  ];

  Directory(outDir).createSync(recursive: true);
  final baseName = '${_safeFileName(id)}-$version.db';
  final String payload;
  switch (compression) {
    case AttachedUpdateCompression.zstd:
      payload = p.join(outDir, '$baseName.zst');
      final result = await Process.run(zstdExecutable, [
        '-q',
        '-f',
        '-$level',
        if (level > 19) '--ultra',
        '-T0',
        '--long=$kZstdMaxWindowLog',
        dbPath,
        '-o',
        payload,
      ]);
      if (result.exitCode != 0) {
        throw UpdateToolException('zstd failed: ${result.stderr}');
      }
    case AttachedUpdateCompression.none:
      payload = dbPath;
    case AttachedUpdateCompression.zstdPatch:
      throw const UpdateToolException(
        'zstd-patch is produced by --delta-from, not by the full artifact',
      );
  }

  final singlePath = p.join(
    outDir,
    compression == AttachedUpdateCompression.zstd ? '$baseName.zst' : baseName,
  );
  final partPaths = await _split(payload, singlePath, partSize);
  if (payload != dbPath && partPaths.length > 1) File(payload).deleteSync();
  final full = AttachedUpdateArtifact(
    compression: compression,
    size: File(dbPath).lengthSync(),
    sha256: await _sha256OfFile(dbPath),
    parts: await _partsOf(partPaths, prefix),
  );

  final deltas = <AttachedUpdateDelta>[];
  for (final oldPath in deltaFrom) {
    final delta = await _packDelta(
      oldPath: oldPath,
      newPath: dbPath,
      outDir: outDir,
      baseName: baseName,
      prefix: prefix,
      libraryId: id,
      version: version,
      partSize: partSize,
      level: level,
      zstdExecutable: zstdExecutable,
      full: full,
      warnings: warnings,
      partPaths: partPaths,
    );
    if (delta != null) deltas.add(delta);
  }

  final manifest = AttachedUpdateManifest(
    libraryId: id,
    dbVersion: version,
    releaseNotes: releaseNotes,
    full: full,
    deltas: deltas,
  );
  final manifestPath = p.join(outDir, 'manifest.json');
  final bytes = utf8.encode(
    '${const JsonEncoder.withIndent('  ').convert(manifest.toJson())}\n',
  );
  // אותו מפענח שהתוכנה מריצה — מניפסט שהכלי כותב חייב לעבור אותו.
  AttachedUpdateManifest.parse(bytes);
  File(manifestPath).writeAsBytesSync(bytes);
  return PackResult(manifest, manifestPath, partPaths, warnings);
}

/// מייצר תיקון `zstd --patch-from` מ-[oldPath] ל-[newPath] ומפצל אותו.
/// מחזיר null (עם אזהרה) כשהתיקון אינו קטן מהקובץ המלא.
Future<AttachedUpdateDelta?> _packDelta({
  required String oldPath,
  required String newPath,
  required String outDir,
  required String baseName,
  required String prefix,
  required String libraryId,
  required int version,
  required int partSize,
  required int level,
  required String zstdExecutable,
  required AttachedUpdateArtifact full,
  required List<String> warnings,
  required List<String> partPaths,
}) async {
  if (!File(oldPath).existsSync()) {
    throw UpdateToolException('No such file: $oldPath');
  }
  final meta = PersonalDbUpdateMeta.read(oldPath);
  if (meta.libraryId != libraryId) {
    throw UpdateToolException(
      '--delta-from $oldPath has library_id "${meta.libraryId}", '
      'not "$libraryId".',
    );
  }
  final fromVersion = int.tryParse(meta.dbVersion ?? '');
  if (fromVersion == null || fromVersion < 1 || fromVersion >= version) {
    throw UpdateToolException(
      '--delta-from $oldPath must have an integer db_version below $version '
      '(found "${meta.dbVersion}").',
    );
  }
  final oldSize = File(oldPath).lengthSync();
  if (oldSize > kMaxDeltaBaseBytes) {
    warnings.add(
      '--delta-from $oldPath is larger than 2 GiB; Otzaria cannot use it as a '
      'patch base, so no delta was produced for db_version $fromVersion.',
    );
    return null;
  }
  final patchName = '$baseName.from-$fromVersion.patch';
  final patchPath = p.join(outDir, '$patchName.zst');
  final result = await Process.run(zstdExecutable, [
    '-q',
    '-f',
    '--patch-from=$oldPath',
    '--long=$kZstdPatchWindowLog',
    '--ultra',
    '-$level',
    newPath,
    '-o',
    patchPath,
  ]);
  if (result.exitCode != 0) {
    throw UpdateToolException('zstd --patch-from failed: ${result.stderr}');
  }
  final patchSize = File(patchPath).lengthSync();
  if (patchSize >= full.compressedSize) {
    warnings.add(
      'The delta from db_version $fromVersion is $patchSize bytes, not smaller '
      'than the full artifact (${full.compressedSize}); it was dropped.',
    );
    File(patchPath).deleteSync();
    return null;
  }
  final paths = await _split(patchPath, patchPath, partSize);
  if (paths.length > 1) File(patchPath).deleteSync();
  partPaths.addAll(paths);
  return AttachedUpdateDelta(
    fromDbVersion: fromVersion,
    fromSha256: await _sha256OfFile(oldPath),
    artifact: AttachedUpdateArtifact(
      compression: AttachedUpdateCompression.zstdPatch,
      size: full.size,
      sha256: full.sha256,
      parts: await _partsOf(paths, prefix),
    ),
  );
}

Future<List<AttachedUpdatePart>> _partsOf(
  List<String> paths,
  String prefix,
) async => [
  for (final path in paths)
    AttachedUpdatePart(
      url: '$prefix${Uri.encodeComponent(p.basename(path))}',
      size: File(path).lengthSync(),
      sha256: await _sha256OfFile(path),
    ),
];

/// חלק יחיד נשאר ב-[single]; כמה חלקים מקבלים סיומת `.001`, `.002`...
Future<List<String>> _split(String payload, String single, int partSize) async {
  final total = File(payload).lengthSync();
  if (total <= partSize) {
    if (!p.equals(payload, single)) File(payload).copySync(single);
    return [single];
  }
  final count = (total + partSize - 1) ~/ partSize;
  final paths = <String>[];
  final input = File(payload).openSync();
  try {
    for (var i = 0; i < count; i++) {
      final path = '$single.${(i + 1).toString().padLeft(3, '0')}';
      final output = File(path).openSync(mode: FileMode.write);
      try {
        var remaining = partSize;
        while (remaining > 0) {
          final chunk = input.readSync(
            remaining < 1 << 20 ? remaining : 1 << 20,
          );
          if (chunk.isEmpty) break;
          output.writeFromSync(chunk);
          remaining -= chunk.length;
        }
      } finally {
        output.closeSync();
      }
      paths.add(path);
    }
  } finally {
    input.closeSync();
  }
  return paths;
}

/// חותם את [manifestPath] וכותב `<manifest>.sig`. מחזיר את נתיב החתימה.
String sign(String manifestPath, String privateKeyPath) {
  final bytes = File(manifestPath).readAsBytesSync();
  try {
    AttachedUpdateManifest.parse(bytes);
  } on AttachedUpdateManifestException catch (e) {
    throw UpdateToolException(
      'Refusing to sign an invalid manifest: ${e.message}',
    );
  }
  final signature = AttachedUpdateSignature.sign(
    bytes,
    File(privateKeyPath).readAsStringSync(),
  );
  final path = '$manifestPath.sig';
  File(path).writeAsStringSync('$signature\n');
  return path;
}

/// מאמת חתימה ומניפסט, כמו שהתוכנה תעשה. [partsDir] — בודק גם את החלקים
/// המקומיים (לפי שם הקובץ שבכתובת). מחזיר את המניפסט המפוענח.
Future<AttachedUpdateManifest> verify({
  required String manifestPath,
  required String publicKey,
  String? signaturePath,
  String? expectedLibraryId,
  String? partsDir,
  List<String> deltaFrom = const [],
  String? zstdLibraryPath,
}) async {
  final bytes = File(manifestPath).readAsBytesSync();
  final sigFile = File(signaturePath ?? '$manifestPath.sig');
  if (!sigFile.existsSync()) {
    throw UpdateToolException('No signature file: ${sigFile.path}');
  }
  if (!AttachedUpdateSignature.verify(
    message: bytes,
    signatureText: sigFile.readAsBytesSync(),
    publicKey: publicKey,
  )) {
    throw const UpdateToolException('Signature does NOT match the public key.');
  }
  final AttachedUpdateManifest manifest;
  try {
    manifest = AttachedUpdateManifest.parse(bytes);
  } on AttachedUpdateManifestException catch (e) {
    throw UpdateToolException('Invalid manifest: ${e.message}');
  }
  if (expectedLibraryId != null && manifest.libraryId != expectedLibraryId) {
    throw UpdateToolException(
      'Manifest library_id "${manifest.libraryId}" differs from the database '
      '("$expectedLibraryId").',
    );
  }
  if (partsDir != null) {
    await _checkParts(manifest.full.parts, partsDir, 'Part');
    for (final delta in manifest.deltas) {
      final at = 'Delta (from db_version ${delta.fromDbVersion}) part';
      await _checkParts(delta.artifact.parts, partsDir, at);
      await _applyDelta(delta, partsDir, deltaFrom, zstdLibraryPath);
    }
  }
  return manifest;
}

/// מחיל תיקון דלתא בדיוק כמו התוכנה — אותו [AttachedUpdateDeltaApplier] —
/// על המסד מ-[deltaFrom] שה-sha256 שלו תואם, ובודק גודל ו-sha256.
Future<void> _applyDelta(
  AttachedUpdateDelta delta,
  String partsDir,
  List<String> deltaFrom,
  String? zstdLibraryPath,
) async {
  final at = 'db_version ${delta.fromDbVersion}';
  String? base;
  for (final candidate in deltaFrom) {
    if (!File(candidate).existsSync()) {
      throw UpdateToolException('No such file: $candidate');
    }
    if (await _sha256OfFile(candidate) == delta.fromSha256) base = candidate;
  }
  if (base == null) {
    throw UpdateToolException(
      'The delta from $at cannot be checked: pass --delta-from <old.db> whose '
      'sha256 is ${delta.fromSha256}.',
    );
  }
  final lib = _openZstdLibrary(zstdLibraryPath);
  final temp = Directory.systemTemp.createTempSync('otzaria_delta_verify');
  try {
    final combined = p.join(temp.path, 'combined.patch');
    final sink = File(combined).openWrite();
    try {
      for (final part in delta.artifact.parts) {
        final name = Uri.decodeComponent(Uri.parse(part.url).pathSegments.last);
        await sink.addStream(File(p.join(partsDir, name)).openRead());
      }
    } finally {
      await sink.close();
    }
    final output = p.join(temp.path, 'patched.db');
    try {
      await AttachedUpdateDeltaApplier(
        decodePatch: (patch, from, out, max, _) async => decodePatchSyncForTest(
          patch,
          from,
          out,
          lib,
          maxOutputBytes: max,
        ),
      ).apply(delta.artifact, combined, base, output);
    } on AttachedUpdateArtifactMismatch catch (e) {
      throw UpdateToolException(
        'The delta from $at does not apply: ${e.message}',
      );
    }
  } finally {
    try {
      temp.deleteSync(recursive: true);
    } catch (_) {}
  }
}

Future<void> _checkParts(
  List<AttachedUpdatePart> parts,
  String partsDir,
  String at,
) async {
  for (final (i, part) in parts.indexed) {
    final name = Uri.decodeComponent(Uri.parse(part.url).pathSegments.last);
    final file = File(p.join(partsDir, name));
    if (!file.existsSync()) {
      throw UpdateToolException('$at ${i + 1} missing: ${file.path}');
    }
    if (file.lengthSync() != part.size ||
        await _sha256OfFile(file.path) != part.sha256) {
      throw UpdateToolException('$at ${i + 1} does not match: ${file.path}');
    }
  }
}

/// libzstd לפענוח התיקון: הכלי רץ ב-Dart טהור, בלי תוסף ה-zstandard של Flutter.
DynamicLibrary _openZstdLibrary(String? path) {
  for (final candidate in [
    ?path,
    ?Platform.environment['LIBZSTD_PATH'],
    if (Platform.isWindows) ...['libzstd.dll', 'zstd.dll'],
    if (Platform.isMacOS) ...[
      'libzstd.dylib',
      '/opt/homebrew/lib/libzstd.dylib',
      '/usr/local/lib/libzstd.dylib',
    ],
    if (!Platform.isWindows && !Platform.isMacOS) ...[
      'libzstd.so.1',
      'libzstd.so',
    ],
  ]) {
    try {
      return DynamicLibrary.open(candidate);
    } catch (_) {}
  }
  throw const UpdateToolException(
    'Cannot load libzstd; install it or pass --zstd-lib <path to libzstd>.',
  );
}

Future<String> _sha256OfFile(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();

String _safeFileName(String value) {
  final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-');
  return safe.isEmpty ? 'library' : safe;
}
