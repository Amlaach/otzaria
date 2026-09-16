/// גופן CFF (‏OTF) אינו יכול להיות מוטמע כקובץ TrueType: הוא נכתב כ-
/// CIDFontType0 עם `/FontFile3`. בלי זה הקורא מפרש מבנה אחר מזה שקיבל.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:opentype_shaper/opentype_shaper.dart';
import 'package:otzaria/printing/shaped_text/pdf_shaped_font.dart';
import 'package:pdf/pdf.dart';

const String _pointedWord = 'שָׁ֖לֹם';

String? _findNativeLibrary() {
  final name = Platform.isWindows
      ? 'opentype_shaper.dll'
      : Platform.isMacOS
      ? 'libopentype_shaper.dylib'
      : 'libopentype_shaper.so';
  for (final profile in const ['release', 'debug']) {
    final candidate = File('C:/opentype_shaper/rust/target/$profile/$name');
    if (candidate.existsSync()) return candidate.absolute.path;
  }
  return null;
}

/// קובץ הגופן של חבילת `otzaria_ashurit`, דרך מפת החבילות של הבדיקה.
File? _packagedFont(String name) {
  final config = File('.dart_tool/package_config.json');
  if (!config.existsSync()) return null;
  final packages =
      (jsonDecode(config.readAsStringSync()) as Map)['packages'] as List;
  for (final package in packages.cast<Map<String, dynamic>>()) {
    if (package['name'] != 'otzaria_ashurit') continue;
    // בלי הלוכסן בסוף, resolve היה מחליף את הסיפא של שורש החבילה.
    final root = Uri.parse('${package['rootUri']}/');
    final file = File.fromUri(root.resolve('lib/$name'));
    return file.existsSync() ? file : null;
  }
  return null;
}

void main() {
  final libraryPath = _findNativeLibrary();
  final font = _packagedFont('OtzariaAshurit-Regular.otf');

  final skipReason = libraryPath == null
      ? 'the native shaper is not built'
      : font == null
      ? 'the Ashurit package is not resolved'
      : null;

  group('PdfShapedFont with CFF outlines', () {
    late ShaperFont shaper;
    late PdfDocument document;
    late PdfShapedFont pdfFont;
    late Uint8List bytes;

    setUp(() {
      ShaperLibrary.path = libraryPath;
      bytes = font!.readAsBytesSync();
      shaper = ShaperFont.register(bytes);
      document = PdfDocument(compress: false);
      pdfFont = PdfShapedFont(document, shaper: shaper, fontBytes: bytes);
    });

    tearDown(() => shaper.dispose());

    Future<String> renderPage() async {
      final page = PdfPage(document, pageFormat: PdfPageFormat.a5);
      final canvas = page.getGraphics()..setFillColor(PdfColors.black);
      pdfFont.drawShapedRun(
        canvas,
        shaper.shape(_pointedWord, rtl: true, script: 'hebr'),
        x: 60,
        y: 300,
        fontSize: 48,
      );
      return String.fromCharCodes(await document.save());
    }

    test('הגופן מוטמע כ-CIDFontType0 עם FontFile3', () async {
      final text = await renderPage();

      expect(text, contains('/Type0'));
      expect(text, contains('/Identity-H'));
      expect(text, contains('/CIDFontType0'));
      expect(text, isNot(contains('/CIDFontType2')));
      expect(text, contains('/FontFile3'));
      expect(text, isNot(contains('/FontFile2')));
      // מפת CID→גליף היא של ה-CFF עצמו; המפתח הזה שייך ל-TrueType בלבד.
      expect(text, isNot(contains('/CIDToGIDMap')));
      expect(text, contains('/Subtype/OpenType'));
    });

    test('הבדיקה רצה על גופן CFF אמיתי', () {
      expect(bytes.sublist(0, 4), [0x4F, 0x54, 0x54, 0x4F]);
    });
  }, skip: skipReason);
}
