import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/canonical_json.dart';

void main() {
  // מפענחים את ה-JSON ולא משווים בייטים של הקובץ: git עשוי להמיר סיומות שורה.
  final fixtures =
      jsonDecode(
            File(
              'test/fixtures/text_corrections/digest_fixtures.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final cases = (fixtures['cases'] as List).cast<Map<String, dynamic>>();

  group('[T29] OCJ-1 מול ה-fixtures המשותפים לאתר', () {
    test('יש fixtures לשני סוגי ה-digest', () {
      expect(fixtures['spec'], 'OCJ-1');
      expect(cases.map((c) => c['kind']).toSet(), {
        'change_digest',
        'content_digest',
      });
    });

    for (final fixture in cases) {
      test('[T29] ${fixture['name']}: canonical ו-sha256 זהים', () {
        final input = fixture['input'];
        final canonical = canonicalJsonEncode(input);
        expect(canonical, fixture['canonical']);
        expect(
          sha256
              .convert(utf8.encode(fixture['canonical'] as String))
              .toString(),
          fixture['sha256'],
          reason: 'ה-fixture עצמו עקבי',
        );
        expect(canonicalJsonSha256(input), fixture['sha256']);
      });
    }
  });

  group('OCJ-1 — כללי הסריאליזציה', () {
    test('מפתחות ממוינים לפי יחידות UTF-16, בלי רווחים', () {
      expect(
        canonicalJsonEncode({'b': 1, 'a': null, 'א': true, 'Z': false}),
        '{"Z":false,"a":null,"b":1,"א":true}',
      );
    });

    test(
      'escaping כמו JSON.stringify: בקרה ב-hex קטן, U+2028 ו-NBSP ליטרליים',
      () {
        expect(
          canonicalJsonEncode('\b\f\n\r\t"\\ ‏ '),
          '"\\u0001\\u001f\\b\\f\\n\\r\\t\\"\\\\ ‏ "',
        );
      },
    );

    test('זוג surrogate תקין נשמר; surrogate בודד נדחה', () {
      expect(canonicalJsonEncode('😀'), '"😀"');
      expect(() => canonicalJsonEncode('\uD83D'), throwsArgumentError);
      expect(() => canonicalJsonEncode('a\uDE00b'), throwsArgumentError);
    });

    test('מספר לא-שלם נדחה', () {
      expect(() => canonicalJsonEncode({'x': 1.5}), throwsArgumentError);
    });

    test('מערכים נשמרים בסדרם', () {
      expect(canonicalJsonEncode([3, 'a', null]), '[3,"a",null]');
    });
  });
}
