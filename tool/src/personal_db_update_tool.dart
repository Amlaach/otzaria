import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:otzaria/attached_libraries/models/attached_library_update_source.dart';
import 'package:otzaria/attached_libraries/models/attached_update_manifest.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_signature.dart';
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
}) async {
  if (!File(dbPath).existsSync()) {
    throw UpdateToolException('No such file: $dbPath');
  }
  if (partSize < 1) throw const UpdateToolException('--part-size must be > 0');
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

  final partPaths = await _split(
    payload,
    outDir,
    baseName,
    compression,
    partSize,
  );
  if (payload != dbPath && partPaths.length > 1) File(payload).deleteSync();
  final parts = [
    for (final path in partPaths)
      AttachedUpdatePart(
        url: '$prefix${Uri.encodeComponent(p.basename(path))}',
        size: File(path).lengthSync(),
        sha256: await _sha256OfFile(path),
      ),
  ];
  final manifest = AttachedUpdateManifest(
    libraryId: id,
    dbVersion: version,
    releaseNotes: releaseNotes,
    full: AttachedUpdateArtifact(
      compression: compression,
      size: File(dbPath).lengthSync(),
      sha256: await _sha256OfFile(dbPath),
      parts: parts,
    ),
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

/// חלק יחיד נשאר בשמו; כמה חלקים מקבלים סיומת `.001`, `.002`...
Future<List<String>> _split(
  String payload,
  String outDir,
  String baseName,
  AttachedUpdateCompression compression,
  int partSize,
) async {
  final total = File(payload).lengthSync();
  final single = p.join(
    outDir,
    compression == AttachedUpdateCompression.zstd ? '$baseName.zst' : baseName,
  );
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
    for (final (i, part) in manifest.full.parts.indexed) {
      final name = Uri.decodeComponent(Uri.parse(part.url).pathSegments.last);
      final file = File(p.join(partsDir, name));
      if (!file.existsSync()) {
        throw UpdateToolException('Part ${i + 1} missing: ${file.path}');
      }
      if (file.lengthSync() != part.size ||
          await _sha256OfFile(file.path) != part.sha256) {
        throw UpdateToolException('Part ${i + 1} does not match: ${file.path}');
      }
    }
  }
  return manifest;
}

Future<String> _sha256OfFile(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();

String _safeFileName(String value) {
  final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-');
  return safe.isEmpty ? 'library' : safe;
}
