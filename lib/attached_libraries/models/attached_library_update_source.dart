import 'dart:convert';

import 'package:equatable/equatable.dart';

/// מקור העדכונים שמסד מצורף מצהיר עליו ב-`schema_meta`, והערכים שנעוצים
/// בתוכנה בפעם הראשונה שנראו (TOFU). Dart טהור — משמש גם את כלי המפרסם.
class AttachedLibraryUpdateSource extends Equatable {
  /// `schema_meta.library_id` כלשונו — חייב להופיע במניפסט ובמסד החדש.
  final String libraryId;

  /// `schema_meta.update_manifest_url` — https בלבד.
  final String manifestUrl;

  /// `schema_meta.update_public_key` — מפתח ed25519 ציבורי ב-base64.
  final String publicKey;

  const AttachedLibraryUpdateSource({
    required this.libraryId,
    required this.manifestUrl,
    required this.publicKey,
  });

  static const metaManifestUrlKey = 'update_manifest_url';
  static const metaPublicKeyKey = 'update_public_key';
  static const maxUrlLength = 2048;
  static const publicKeyLength = 32;

  /// המקור מתוך ערכי `schema_meta`, או null כשאחד חסר או פגום — מסד כזה
  /// אינו מתעדכן לעולם.
  static AttachedLibraryUpdateSource? fromMeta({
    required String? libraryId,
    required String? manifestUrl,
    required String? publicKey,
  }) {
    final id = libraryId?.trim() ?? '';
    final url = manifestUrl?.trim() ?? '';
    final key = publicKey?.trim() ?? '';
    if (id.isEmpty ||
        !isValidManifestUrl(url) ||
        decodePublicKey(key) == null) {
      return null;
    }
    return AttachedLibraryUpdateSource(
      libraryId: id,
      manifestUrl: url,
      publicKey: key,
    );
  }

  /// בדיקה תחבירית בלבד; בדיקת המארח (DNS, טווחים פרטיים) נעשית בעת ההורדה.
  static bool isValidManifestUrl(String url) {
    if (url.isEmpty || url.length > maxUrlLength) return false;
    final uri = Uri.tryParse(url);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !uri.hasFragment;
  }

  /// 32 בתים של מפתח ed25519, או null כשהטקסט אינו base64 תקני באורך הנכון.
  static List<int>? decodePublicKey(String base64Key) {
    try {
      final bytes = base64.decode(base64Key);
      return bytes.length == publicKeyLength ? bytes : null;
    } on FormatException {
      return null;
    }
  }

  /// המארח שמוצג למשתמש בהסכמה לצירוף ובאישור ההתקנה.
  String get host => Uri.parse(manifestUrl).host;

  Map<String, dynamic> toJson() => {
    'libraryId': libraryId,
    'manifestUrl': manifestUrl,
    'publicKey': publicKey,
  };

  static AttachedLibraryUpdateSource? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['libraryId'];
    final url = json['manifestUrl'];
    final key = json['publicKey'];
    if (id is! String || url is! String || key is! String) return null;
    return fromMeta(libraryId: id, manifestUrl: url, publicKey: key);
  }

  @override
  List<Object?> get props => [libraryId, manifestUrl, publicKey];
}
