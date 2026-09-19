import 'dart:convert';

import 'package:otzaria/attached_libraries/models/attached_library_update_source.dart';

/// מניפסט עדכון של מסד מצורף. הבתים שנחתמו הם הקובץ כפי שהורד בדיוק;
/// הפענוח כאן בא רק אחרי אימות החתימה. Dart טהור — משמש גם את כלי המפרסם.
///
/// שדות לא מוכרים מתעלמים מהם (תאימות קדימה); שינוי שאינו תואם מעלה את
/// [format], ולקוח ישן דוחה אותו.
class AttachedUpdateManifest {
  static const currentFormat = 1;
  static const maxManifestBytes = 1024 * 1024;
  static const maxSignatureBytes = 1024;
  static const maxReleaseNotesLength = 20000;
  static const maxParts = 1000;
  static const maxDeltas = 50;

  /// תקרה לקובץ המסד הפרוס ולסך החלקים הדחוסים.
  static const maxArtifactBytes = 64 * 1024 * 1024 * 1024;

  final int format;
  final String libraryId;
  final int dbVersion;
  final String? releaseNotes;
  final AttachedUpdateArtifact full;

  /// תיקוני דלתא אופציונליים — מפוענחים ומאומתים, אך טרם מוחלים (v2).
  final List<AttachedUpdateDelta> deltas;

  const AttachedUpdateManifest({
    this.format = currentFormat,
    required this.libraryId,
    required this.dbVersion,
    this.releaseNotes,
    required this.full,
    this.deltas = const [],
  });

  /// השרתים שמהם יורדו הקבצים (חלקי הקובץ המלא והדלתאות), בלי כפילויות.
  List<String> get downloadHosts => {
    for (final artifact in [full, for (final delta in deltas) delta.artifact])
      for (final part in artifact.parts) Uri.parse(part.url).host.toLowerCase(),
  }.toList();

  /// מפענח בקפדנות. זורק [AttachedUpdateManifestException] על כל חריגה.
  static AttachedUpdateManifest parse(List<int> bytes) {
    if (bytes.length > maxManifestBytes) {
      throw const AttachedUpdateManifestException('manifest too large');
    }
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const AttachedUpdateManifestException('not valid UTF-8 JSON');
    }
    final root = _map(json, 'manifest');
    final format = _int(root, 'format', min: 1);
    if (format > currentFormat) {
      throw AttachedUpdateManifestException(
        'format $format requires a newer version of Otzaria',
      );
    }
    final libraryId = _string(root, 'library_id', maxLength: 256);
    final notes = _optionalString(
      root,
      'release_notes',
      maxLength: maxReleaseNotesLength,
    );
    final deltaList = root['delta'];
    if (deltaList != null && deltaList is! List) {
      throw const AttachedUpdateManifestException('"delta" must be a list');
    }
    final deltas = [
      for (final (i, item) in ((deltaList as List?) ?? const []).indexed)
        AttachedUpdateDelta._parse(_map(item, 'delta[$i]'), 'delta[$i]'),
    ];
    if (deltas.length > maxDeltas) {
      throw const AttachedUpdateManifestException('too many delta entries');
    }
    final dbVersion = _int(root, 'db_version', min: 1);
    for (final delta in deltas) {
      if (delta.fromDbVersion >= dbVersion) {
        throw const AttachedUpdateManifestException(
          'delta.from_db_version must be lower than db_version',
        );
      }
    }
    return AttachedUpdateManifest(
      format: format,
      libraryId: libraryId,
      dbVersion: dbVersion,
      releaseNotes: notes,
      full: AttachedUpdateArtifact._parse(_map(root['full'], 'full'), 'full'),
      deltas: deltas,
    );
  }

  /// דוחה מניפסט שאינו מיועד למסד המותקן או שאינו חדש ממנו. [installedDbVersion]
  /// הוא `schema_meta.db_version`; ערך שאינו מספר שלם — המסד אינו מתעדכן.
  void checkApplicable({
    required AttachedLibraryUpdateSource pinned,
    required String? installedDbVersion,
  }) {
    if (libraryId != pinned.libraryId) {
      throw const AttachedUpdateManifestException(
        'library_id does not match the attached database',
      );
    }
    final installed = int.tryParse(installedDbVersion?.trim() ?? '');
    if (installed == null) {
      throw const AttachedUpdateManifestException(
        'the attached database has no integer db_version',
      );
    }
    if (dbVersion <= installed) {
      throw AttachedUpdateManifestException(
        'db_version $dbVersion is not newer than the installed $installed',
      );
    }
  }

  Map<String, dynamic> toJson() => {
    'format': format,
    'library_id': libraryId,
    'db_version': dbVersion,
    if (releaseNotes != null) 'release_notes': releaseNotes,
    'full': full.toJson(),
    if (deltas.isNotEmpty) 'delta': [for (final d in deltas) d.toJson()],
  };
}

enum AttachedUpdateCompression { zstd, none }

/// קובץ שמורכב מחלקים שמשורשרים לפי הסדר ואז נפרסים לפי [compression].
class AttachedUpdateArtifact {
  final AttachedUpdateCompression compression;

  /// גודל הקובץ הפרוס, ו-sha256 שלו (hex קטן).
  final int size;
  final String sha256;
  final List<AttachedUpdatePart> parts;

  const AttachedUpdateArtifact({
    required this.compression,
    required this.size,
    required this.sha256,
    required this.parts,
  });

  /// סך הבתים להורדה.
  int get compressedSize => parts.fold(0, (sum, part) => sum + part.size);

  static AttachedUpdateArtifact _parse(Map<String, Object?> map, String at) {
    final compression = AttachedUpdateCompression.values
        .where((c) => c.name == map['compression'])
        .firstOrNull;
    if (compression == null) {
      throw AttachedUpdateManifestException(
        '$at.compression must be "zstd" or "none"',
      );
    }
    final list = map['parts'];
    if (list is! List ||
        list.isEmpty ||
        list.length > AttachedUpdateManifest.maxParts) {
      throw AttachedUpdateManifestException(
        '$at.parts must list 1-${AttachedUpdateManifest.maxParts} parts',
      );
    }
    final artifact = AttachedUpdateArtifact(
      compression: compression,
      size: _int(map, 'size', min: 1, at: at),
      sha256: _sha256(map, 'sha256', at: at),
      parts: [
        for (final (i, item) in list.indexed)
          AttachedUpdatePart._parse(
            _map(item, '$at.parts[$i]'),
            '$at.parts[$i]',
          ),
      ],
    );
    if (artifact.size > AttachedUpdateManifest.maxArtifactBytes ||
        artifact.compressedSize > AttachedUpdateManifest.maxArtifactBytes) {
      throw AttachedUpdateManifestException('$at is larger than the size cap');
    }
    if (compression == AttachedUpdateCompression.none &&
        artifact.compressedSize != artifact.size) {
      throw AttachedUpdateManifestException(
        '$at: uncompressed parts must add up to size',
      );
    }
    return artifact;
  }

  Map<String, dynamic> toJson() => {
    'compression': compression.name,
    'size': size,
    'sha256': sha256,
    'parts': [for (final part in parts) part.toJson()],
  };
}

class AttachedUpdatePart {
  final String url;
  final int size;
  final String sha256;

  const AttachedUpdatePart({
    required this.url,
    required this.size,
    required this.sha256,
  });

  static AttachedUpdatePart _parse(Map<String, Object?> map, String at) {
    final url = _string(
      map,
      'url',
      maxLength: AttachedLibraryUpdateSource.maxUrlLength,
      at: at,
    );
    if (!AttachedLibraryUpdateSource.isValidManifestUrl(url)) {
      throw AttachedUpdateManifestException('$at.url must be an https URL');
    }
    return AttachedUpdatePart(
      url: url,
      size: _int(map, 'size', min: 1, at: at),
      sha256: _sha256(map, 'sha256', at: at),
    );
  }

  Map<String, dynamic> toJson() => {'url': url, 'size': size, 'sha256': sha256};
}

/// תיקון ממסד שה-sha256 שלו [fromSha256] לגרסת המניפסט. [artifact] הוא קובץ
/// patch של seforim_library_updater; המסד שמתקבל נבדק מול `full.sha256`.
class AttachedUpdateDelta {
  final int fromDbVersion;
  final String fromSha256;
  final AttachedUpdateArtifact artifact;

  const AttachedUpdateDelta({
    required this.fromDbVersion,
    required this.fromSha256,
    required this.artifact,
  });

  static AttachedUpdateDelta _parse(Map<String, Object?> map, String at) =>
      AttachedUpdateDelta(
        fromDbVersion: _int(map, 'from_db_version', min: 1, at: at),
        fromSha256: _sha256(map, 'from_sha256', at: at),
        artifact: AttachedUpdateArtifact._parse(map, at),
      );

  Map<String, dynamic> toJson() => {
    'from_db_version': fromDbVersion,
    'from_sha256': fromSha256,
    ...artifact.toJson(),
  };
}

class AttachedUpdateManifestException implements Exception {
  final String message;
  const AttachedUpdateManifestException(this.message);

  @override
  String toString() => 'AttachedUpdateManifestException: $message';
}

Map<String, Object?> _map(Object? value, String at) {
  if (value is! Map<String, Object?>) {
    throw AttachedUpdateManifestException('$at must be a JSON object');
  }
  return value;
}

int _int(Map<String, Object?> map, String key, {required int min, String? at}) {
  final value = map[key];
  // double כמו 3.0 נדחה: אין מקום לעיגול בגרסאות ובגדלים.
  if (value is! int || value < min) {
    throw AttachedUpdateManifestException(
      '${at == null ? '' : '$at.'}$key must be an integer >= $min',
    );
  }
  return value;
}

String _string(
  Map<String, Object?> map,
  String key, {
  required int maxLength,
  String? at,
}) {
  final value = map[key];
  if (value is! String || value.isEmpty || value.length > maxLength) {
    throw AttachedUpdateManifestException(
      '${at == null ? '' : '$at.'}$key must be a non-empty string '
      '(up to $maxLength characters)',
    );
  }
  return value;
}

String? _optionalString(
  Map<String, Object?> map,
  String key, {
  required int maxLength,
}) {
  if (!map.containsKey(key) || map[key] == null) return null;
  return _string(map, key, maxLength: maxLength);
}

final _hex64 = RegExp(r'^[0-9a-f]{64}$');

String _sha256(Map<String, Object?> map, String key, {required String at}) {
  final value = map[key];
  if (value is! String || !_hex64.hasMatch(value)) {
    throw AttachedUpdateManifestException(
      '$at.$key must be 64 lowercase hex characters',
    );
  }
  return value;
}
