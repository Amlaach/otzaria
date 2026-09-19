// כלי המפרסם לעדכוני מסד ספרים אישי: מפתחות, אריזה, חתימה ואימות.
// מדריך מלא: docs/personal_databases.md.
//
//   dart run tool/personal_db_update.dart keygen --out <private.key> [--force]
//   dart run tool/personal_db_update.dart pack <db> --out <dir> --url-prefix <https://...>
//       [--part-size <bytes>] [--compression zstd|none] [--level <1-22>]
//       [--zstd <path to zstd>] [--notes <file>] [--library-id <id>] [--db-version <n>]
//   dart run tool/personal_db_update.dart sign <manifest.json> --key <private.key>
//   dart run tool/personal_db_update.dart verify <manifest.json>
//       (--public-key <base64> | --db <db>) [--sig <file>] [--parts <dir>]
//
// קוד יציאה: 0 הצלחה, 1 כשל, 64 שימוש שגוי.

import 'dart:io';

import 'package:otzaria/attached_libraries/models/attached_update_manifest.dart';

import 'src/personal_db_update_tool.dart';

const _usage = '''
Usage: dart run tool/personal_db_update.dart <command> ...

  keygen --out <private.key> [--force]
  pack <db> --out <dir> --url-prefix <https://...> [--part-size <bytes>]
       [--compression zstd|none] [--level <1-22>] [--zstd <exe>]
       [--notes <file>] [--library-id <id>] [--db-version <n>]
  sign <manifest.json> --key <private.key>
  verify <manifest.json> (--public-key <base64> | --db <db>) [--sig <file>]
       [--parts <dir>]
''';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
    stdout.write(_usage);
    exitCode = args.isEmpty ? 64 : 0;
    return;
  }
  try {
    final options = _Options.parse(args.skip(1).toList());
    switch (args.first) {
      case 'keygen':
        final publicKey = keygen(
          options.require('out'),
          force: options.flags.contains('force'),
        );
        stdout
          ..writeln('Private key written to ${options.require('out')}.')
          ..writeln('Keep it secret and backed up: it cannot be replaced.')
          ..writeln()
          ..writeln('Public key: $publicKey')
          ..writeln()
          ..writeln('Add to the database:')
          ..writeln(
            "  INSERT OR REPLACE INTO schema_meta(key, value) VALUES "
            "('update_public_key', '$publicKey');",
          )
          ..writeln(
            "  INSERT OR REPLACE INTO schema_meta(key, value) VALUES "
            "('update_manifest_url', 'https://.../manifest.json');",
          );
      case 'pack':
        final notesPath = options.values['notes'];
        final result = await pack(
          dbPath: options.positional(0),
          outDir: options.require('out'),
          urlPrefix: options.require('url-prefix'),
          partSize: options.intValue('part-size') ?? kDefaultPartSize,
          compression: _compression(options.values['compression']),
          level: options.intValue('level') ?? 19,
          zstdExecutable: options.values['zstd'] ?? 'zstd',
          releaseNotes: notesPath == null
              ? null
              : File(notesPath).readAsStringSync().trim(),
          libraryId: options.values['library-id'],
          dbVersion: options.intValue('db-version'),
        );
        for (final warning in result.warnings) {
          stderr.writeln('WARNING: $warning');
        }
        stdout.writeln('Manifest: ${result.manifestPath}');
        for (final part in result.manifest.full.parts) {
          stdout.writeln('  ${part.url}  (${part.size} bytes)');
        }
        stdout.writeln(
          'Upload the parts to those URLs, then sign manifest.json and upload '
          'manifest.json + manifest.json.sig.',
        );
      case 'sign':
        final path = sign(options.positional(0), options.require('key'));
        stdout.writeln('Signature written to $path');
      case 'verify':
        final dbPath = options.values['db'];
        final meta = dbPath == null ? null : PersonalDbUpdateMeta.read(dbPath);
        final publicKey = options.values['public-key'] ?? meta?.publicKey;
        if (publicKey == null) {
          throw const UpdateToolException(
            'Pass --public-key, or --db of a database that declares '
            'update_public_key.',
          );
        }
        final manifest = await verify(
          manifestPath: options.positional(0),
          publicKey: publicKey,
          signaturePath: options.values['sig'],
          expectedLibraryId: meta?.libraryId,
          partsDir: options.values['parts'],
        );
        stdout.writeln(
          'OK: ${manifest.libraryId} db_version ${manifest.dbVersion}, '
          '${manifest.full.parts.length} part(s), '
          '${manifest.full.compressedSize} bytes to download.',
        );
      default:
        throw const _UsageException();
    }
  } on _UsageException {
    stderr.write(_usage);
    exitCode = 64;
  } on UpdateToolException catch (e) {
    stderr.writeln('ERROR: ${e.message}');
    exitCode = 1;
  }
}

AttachedUpdateCompression _compression(String? value) => switch (value) {
  null || 'zstd' => AttachedUpdateCompression.zstd,
  'none' => AttachedUpdateCompression.none,
  _ => throw const UpdateToolException('--compression must be zstd or none'),
};

class _UsageException implements Exception {
  const _UsageException();
}

class _Options {
  final List<String> _positional = [];
  final Map<String, String> values = {};
  final Set<String> flags = {};

  static const _flagNames = {'force'};

  static _Options parse(List<String> args) {
    final options = _Options();
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (!arg.startsWith('--')) {
        options._positional.add(arg);
        continue;
      }
      final name = arg.substring(2);
      if (_flagNames.contains(name)) {
        options.flags.add(name);
      } else if (i + 1 < args.length) {
        options.values[name] = args[++i];
      } else {
        throw const _UsageException();
      }
    }
    return options;
  }

  String positional(int index) => index < _positional.length
      ? _positional[index]
      : throw const _UsageException();

  String require(String name) =>
      values[name] ?? (throw const _UsageException());

  int? intValue(String name) {
    final raw = values[name];
    if (raw == null) return null;
    return int.tryParse(raw) ??
        (throw UpdateToolException('--$name must be an integer'));
  }
}
