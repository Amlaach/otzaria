import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_signature.dart';

void main() {
  final privateKey = AttachedUpdateSignature.generatePrivateKey();
  final publicKey = AttachedUpdateSignature.publicKeyOf(privateKey);
  final message = utf8.encode('{"format":1,"db_version":2}');
  final signature = utf8.encode(
    AttachedUpdateSignature.sign(message, privateKey),
  );

  bool verify(List<int> msg, List<int> sig, String key) =>
      AttachedUpdateSignature.verify(
        message: msg,
        signatureText: sig,
        publicKey: key,
      );

  test('valid signature verifies with the pinned key', () {
    expect(verify(message, signature, publicKey), isTrue);
    // A trailing newline in the .sig file is fine.
    expect(verify(message, [...signature, 10], publicKey), isTrue);
  });

  test('RFC 8032 test vector 1 (empty message)', () {
    const seedHex =
        '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60';
    const publicHex =
        'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a';
    const sigHex =
        'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155'
        '5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b';
    List<int> hex(String s) => [
      for (var i = 0; i < s.length; i += 2)
        int.parse(s.substring(i, i + 2), radix: 16),
    ];
    final key = base64.encode(hex(seedHex));
    expect(
      AttachedUpdateSignature.publicKeyOf(key),
      base64.encode(hex(publicHex)),
    );
    expect(
      AttachedUpdateSignature.sign(const [], key),
      base64.encode(hex(sigHex)),
    );
  });

  test('tampered manifest fails', () {
    final tampered = [...message]..[5] ^= 1;
    expect(verify(tampered, signature, publicKey), isFalse);
    expect(verify([...message, 32], signature, publicKey), isFalse);
  });

  test('wrong key fails', () {
    final otherKey = AttachedUpdateSignature.publicKeyOf(
      AttachedUpdateSignature.generatePrivateKey(),
    );
    expect(verify(message, signature, otherKey), isFalse);
  });

  test('bad signature text fails without throwing', () {
    final sigBytes = base64.decode(utf8.decode(signature));
    final flipped = [...sigBytes]..[10] ^= 1;
    expect(
      verify(message, utf8.encode(base64.encode(flipped)), publicKey),
      isFalse,
    );
    expect(verify(message, utf8.encode('not base64!'), publicKey), isFalse);
    expect(
      verify(message, utf8.encode(base64.encode([1, 2, 3])), publicKey),
      isFalse,
    );
    expect(verify(message, List.filled(2000, 65), publicKey), isFalse);
    expect(verify(message, [0xff, 0xfe], publicKey), isFalse);
    expect(verify(message, signature, 'AAAA'), isFalse);
  });
}
