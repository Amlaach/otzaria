import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:otzaria/attached_libraries/models/attached_library_update_source.dart';
import 'package:otzaria/attached_libraries/models/attached_update_manifest.dart';
import 'package:pinenacl/ed25519.dart' as ed;

/// חתימות ed25519 על מניפסט העדכון. קובץ החתימה (`<manifest>.sig`) הוא
/// base64 של 64 בתים. Dart טהור — משמש גם את כלי המפרסם.
abstract final class AttachedUpdateSignature {
  static const seedLength = 32;
  static const signatureLength = 64;

  /// מפתח פרטי חדש (זרע של 32 בתים) ב-base64.
  static String generatePrivateKey() {
    final random = Random.secure();
    return base64.encode([
      for (var i = 0; i < seedLength; i++) random.nextInt(256),
    ]);
  }

  /// המפתח הציבורי (base64) של [privateKey].
  static String publicKeyOf(String privateKey) => base64.encode(
    _signingKey(privateKey).verifyKey.asTypedList,
  );

  /// תוכן קובץ ה-`.sig` עבור [message].
  static String sign(List<int> message, String privateKey) {
    final signed = _signingKey(privateKey).sign(Uint8List.fromList(message));
    return base64.encode(signed.signature.asTypedList);
  }

  /// מאמת את [message] מול [signatureText] ב-[publicKey] הנעוץ. false על כל
  /// חתימה פגומה, מפתח שגוי או קלט לא תקני — לעולם לא זורק.
  static bool verify({
    required List<int> message,
    required List<int> signatureText,
    required String publicKey,
  }) {
    final key = AttachedLibraryUpdateSource.decodePublicKey(publicKey);
    if (key == null ||
        signatureText.length > AttachedUpdateManifest.maxSignatureBytes) {
      return false;
    }
    final Uint8List signature;
    try {
      signature = base64.decode(ascii.decode(signatureText).trim());
    } on FormatException {
      return false;
    }
    if (signature.length != signatureLength) return false;
    try {
      return ed.VerifyKey(Uint8List.fromList(key)).verify(
        signature: ed.Signature(signature),
        message: Uint8List.fromList(message),
      );
    } catch (_) {
      // pinenacl זורק Exception כללי על חתימה שאינה תקפה.
      return false;
    }
  }

  static ed.SigningKey _signingKey(String privateKey) {
    final seed = base64.decode(privateKey.trim());
    if (seed.length != seedLength) {
      throw const FormatException('private key must be 32 bytes (base64)');
    }
    return ed.SigningKey.fromSeed(seed);
  }
}
