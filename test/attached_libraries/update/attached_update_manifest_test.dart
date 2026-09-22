import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/models/attached_library_update_source.dart';
import 'package:otzaria/attached_libraries/models/attached_update_manifest.dart';

final _sha = 'a' * 64;
final _sha2 = 'b' * 64;

Map<String, Object?> _valid() => {
  'format': 1,
  'library_id': 'my-lib',
  'db_version': 7,
  'release_notes': 'notes <b>not html</b>',
  'full': {
    'compression': 'zstd',
    'size': 1000,
    'sha256': _sha,
    'parts': [
      {'url': 'https://example.org/a.001', 'size': 300, 'sha256': _sha2},
      {'url': 'https://example.org/a.002', 'size': 200, 'sha256': _sha2},
    ],
  },
};

List<int> _bytes(Object? json) => utf8.encode(jsonEncode(json));

Matcher _rejected(String fragment) => throwsA(
  isA<AttachedUpdateManifestException>().having(
    (e) => e.message,
    'message',
    contains(fragment),
  ),
);

const _pinned = AttachedLibraryUpdateSource(
  libraryId: 'my-lib',
  manifestUrl: 'https://example.org/manifest.json',
  publicKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
);

void main() {
  test('parses a valid manifest', () {
    final m = AttachedUpdateManifest.parse(_bytes(_valid()));
    expect(m.libraryId, 'my-lib');
    expect(m.dbVersion, 7);
    expect(m.releaseNotes, 'notes <b>not html</b>');
    expect(m.full.compression, AttachedUpdateCompression.zstd);
    expect(m.full.parts, hasLength(2));
    expect(m.full.compressedSize, 500);
    expect(m.deltas, isEmpty);
    // toJson -> parse is stable (the CLI writes through toJson).
    final again = AttachedUpdateManifest.parse(_bytes(m.toJson()));
    expect(again.toJson(), m.toJson());
  });

  test('ignores unknown fields', () {
    final json = _valid()..['future_field'] = {'x': 1};
    expect(AttachedUpdateManifest.parse(_bytes(json)).dbVersion, 7);
  });

  test('rejects oversize, non-JSON and non-object input', () {
    expect(
      () => AttachedUpdateManifest.parse(
        List.filled(AttachedUpdateManifest.maxManifestBytes + 1, 32),
      ),
      _rejected('too large'),
    );
    expect(
      () => AttachedUpdateManifest.parse(utf8.encode('{')),
      _rejected('JSON'),
    );
    expect(
      () => AttachedUpdateManifest.parse(_bytes([1])),
      _rejected('object'),
    );
  });

  test('rejects newer format', () {
    expect(
      () => AttachedUpdateManifest.parse(_bytes(_valid()..['format'] = 2)),
      _rejected('newer version'),
    );
  });

  test('rejects bad field types and values', () {
    Map<String, Object?> full(Map<String, Object?> j) =>
        j['full'] as Map<String, Object?>;
    final cases = <String, void Function(Map<String, Object?>)>{
      'db_version': (j) => j['db_version'] = 7.0,
      'db_version ': (j) => j['db_version'] = '8',
      'library_id': (j) => j['library_id'] = '',
      'release_notes': (j) => j['release_notes'] = 'x' * 20001,
      'compression': (j) => full(j)['compression'] = 'gzip',
      'sha256': (j) => full(j)['sha256'] = _sha.toUpperCase(),
      'parts': (j) => full(j)['parts'] = [],
      'https': (j) =>
          (full(j)['parts'] as List).first['url'] = 'http://example.org/a',
      'size': (j) => (full(j)['parts'] as List).first['size'] = 0,
      'size cap': (j) => full(j)['size'] = 65 * 1024 * 1024 * 1024,
    };
    for (final entry in cases.entries) {
      final json = jsonDecode(jsonEncode(_valid())) as Map<String, Object?>;
      entry.value(json);
      expect(
        () => AttachedUpdateManifest.parse(_bytes(json)),
        throwsA(isA<AttachedUpdateManifestException>()),
        reason: entry.key,
      );
    }
  });

  test('uncompressed parts must add up to size', () {
    final json = _valid();
    (json['full'] as Map)['compression'] = 'none';
    expect(
      () => AttachedUpdateManifest.parse(_bytes(json)),
      _rejected('add up'),
    );
    (json['full'] as Map)['size'] = 500;
    expect(AttachedUpdateManifest.parse(_bytes(json)).full.size, 500);
  });

  test('parses optional delta entries', () {
    final json = _valid()
      ..['delta'] = [
        {
          'from_db_version': 6,
          'from_sha256': _sha2,
          'compression': 'zstd',
          'size': 50,
          'sha256': _sha,
          'parts': [
            {'url': 'https://example.org/p', 'size': 20, 'sha256': _sha},
          ],
        },
      ];
    final m = AttachedUpdateManifest.parse(_bytes(json));
    expect(m.deltas.single.fromDbVersion, 6);
    expect(m.deltas.single.artifact.size, 50);
    expect(
      AttachedUpdateManifest.parse(_bytes(m.toJson())).deltas,
      hasLength(1),
    );

    ((json['delta'] as List).first as Map)['from_db_version'] = 7;
    expect(AttachedUpdateManifest.parse(_bytes(json)).deltas, isEmpty);
  });

  Map<String, Object?> deltaEntry(int fromVersion, {String? compression}) => {
    'from_db_version': fromVersion,
    'from_sha256': _sha2,
    'compression': compression ?? 'zstd',
    'size': 50,
    'sha256': _sha,
    'parts': [
      {'url': 'https://example.org/p', 'size': 20, 'sha256': _sha},
    ],
  };

  test('skips a delta entry it cannot read and keeps the rest', () {
    final json = _valid()
      ..['delta'] = [
        deltaEntry(3, compression: 'brotli-patch-v9'),
        {'from_db_version': 4, 'shape': 'unknown'},
        'not an object',
        deltaEntry(5),
      ];
    final m = AttachedUpdateManifest.parse(_bytes(json));
    expect(m.deltas.single.fromDbVersion, 5);
  });

  test('accepts zstd-patch in a delta and rejects it in full', () {
    final json = _valid()
      ..['delta'] = [deltaEntry(6, compression: 'zstd-patch')];
    final m = AttachedUpdateManifest.parse(_bytes(json));
    expect(
      m.deltas.single.artifact.compression,
      AttachedUpdateCompression.zstdPatch,
    );
    expect(m.deltas.single.toJson()['compression'], 'zstd-patch');

    (json['full'] as Map)['compression'] = 'zstd-patch';
    expect(
      () => AttachedUpdateManifest.parse(_bytes(json)),
      _rejected('full.compression'),
    );
  });

  group('checkApplicable', () {
    final manifest = AttachedUpdateManifest.parse(_bytes(_valid()));

    test('accepts a newer version of the pinned library', () {
      manifest.checkApplicable(pinned: _pinned, installedDbVersion: '6');
    });

    test('rejects same or older version (rollback / replay)', () {
      expect(
        () =>
            manifest.checkApplicable(pinned: _pinned, installedDbVersion: '7'),
        _rejected('not newer'),
      );
      expect(
        () =>
            manifest.checkApplicable(pinned: _pinned, installedDbVersion: '9'),
        _rejected('not newer'),
      );
    });

    test('rejects a non-integer installed version', () {
      expect(
        () =>
            manifest.checkApplicable(pinned: _pinned, installedDbVersion: null),
        _rejected('integer'),
      );
      expect(
        () => manifest.checkApplicable(
          pinned: _pinned,
          installedDbVersion: '2026-09',
        ),
        _rejected('integer'),
      );
    });

    test('rejects library_id mismatch', () {
      const other = AttachedLibraryUpdateSource(
        libraryId: 'other-lib',
        manifestUrl: 'https://example.org/manifest.json',
        publicKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      );
      expect(
        () => manifest.checkApplicable(pinned: other, installedDbVersion: '1'),
        _rejected('library_id'),
      );
    });
  });
}
