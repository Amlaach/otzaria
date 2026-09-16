import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:opentype_shaper/opentype_shaper.dart';
import 'package:otzaria/printing/shaped_text/pdf_shaped_font.dart';
import 'package:pdf/pdf.dart';

/// A pointed Hebrew word: three letters carrying nikud, one of them a ta'am.
const String pointedWord = 'שָׁ֖לֹם';

/// Free fonts already shipped with the app. The Guttman faces are proprietary
/// and deliberately not used here.
const List<String> _fontCandidates = [
  'fonts/TaameyDavidCLM-Medium.ttf',
  'fonts/NotoSerifHebrew-VariableFont_wdth,wght.ttf',
];

String? _findNativeLibrary() {
  final name = Platform.isWindows
      ? 'opentype_shaper.dll'
      : Platform.isMacOS
      ? 'libopentype_shaper.dylib'
      : 'libopentype_shaper.so';
  for (final profile in const ['release', 'debug']) {
    final candidate = File('C:/opentype_shaper/rust/target/$profile/$name');
    if (candidate.existsSync()) {
      return candidate.absolute.path;
    }
  }
  return null;
}

(String, Uint8List)? _readFont() {
  for (final path in _fontCandidates) {
    final file = File(path);
    if (file.existsSync()) {
      return (path, file.readAsBytesSync());
    }
  }
  return null;
}

void main() {
  final libraryPath = _findNativeLibrary();
  final font = _readFont();

  final skipReason = libraryPath == null
      ? 'the native shaper is not built'
      : font == null
      ? 'no test font found'
      : null;

  group('PdfShapedFont', () {
    late ShaperFont shaper;
    late PdfDocument document;
    late PdfShapedFont pdfFont;

    setUp(() {
      ShaperLibrary.path = libraryPath;
      shaper = ShaperFont.register(font!.$2);
      document = PdfDocument(compress: false);
      pdfFont = PdfShapedFont(
        document,
        shaper: shaper,
        fontBytes: font.$2,
      );
    });

    tearDown(() => shaper.dispose());

    Future<Uint8List> renderPage() async {
      final page = PdfPage(document, pageFormat: PdfPageFormat.a5);
      final canvas = page.getGraphics()..setFillColor(PdfColors.black);
      pdfFont.drawShapedRun(
        canvas,
        shaper.shape(pointedWord, rtl: true, script: 'hebr'),
        x: 60,
        y: 300,
        fontSize: 48,
      );
      return Uint8List.fromList(await document.save());
    }

    test('declares an Identity-H Type0 font with the file embedded', () async {
      final bytes = await renderPage();
      final text = String.fromCharCodes(bytes);

      expect(text, contains('/Type0'));
      expect(text, contains('/Identity-H'));
      expect(text, contains('/CIDFontType2'));
      // The dict serialiser writes no space between key and value.
      expect(text, contains('/CIDToGIDMap/Identity'));
      expect(text, contains('/FontFile2'));
      expect(text, contains('/ToUnicode'));
      // The whole font is embedded, so the stream is at least its size.
      expect(bytes.length, greaterThan(font!.$2.length));
    });

    test('emits glyph ids, not characters', () async {
      final bytes = await renderPage();
      final text = String.fromCharCodes(bytes);

      // Content streams carry hex glyph ids inside a TJ array.
      expect(text, contains('TJ'));
      expect(RegExp(r'<[0-9a-f]{4}>').hasMatch(text), isTrue);
      // No literal Hebrew may reach the content stream.
      expect(text.contains(pointedWord), isFalse);
    });

    test('maps every drawn glyph back to its characters', () async {
      final bytes = await renderPage();
      final text = String.fromCharCodes(bytes);

      final cmapStart = text.indexOf('beginbfchar');
      expect(cmapStart, greaterThan(-1));
      final cmap = text.substring(cmapStart, text.indexOf('endbfchar'));

      // Every character of the word must be recoverable from the text layer.
      for (final rune in pointedWord.runes) {
        final hex = rune.toRadixString(16).toUpperCase().padLeft(4, '0');
        expect(
          cmap,
          contains(hex),
          reason: 'U+$hex is missing from the ToUnicode map',
        );
      }
    });

    test('positions marks away from the pen', () async {
      final run = shaper.shape(pointedWord, rtl: true, script: 'hebr');
      // Guards the premise of the whole file: without GPOS offsets the PDF
      // would be no better than the unshaped path it replaces.
      final marks = [
        for (var index = 0; index < run.glyphCount; index++)
          if (run.xAdvance(index) == 0) index,
      ];
      expect(marks, isNotEmpty);
      expect(
        marks.any(
          (index) => run.xOffset(index) != 0 || run.yOffset(index) != 0,
        ),
        isTrue,
      );
    });

    test('writes a PDF that can be inspected by hand', () async {
      final bytes = await renderPage();
      final out = Directory.systemTemp
          .createTempSync('shaped_pdf')
          .childFile('shaped_sample.pdf');
      out.writeAsBytesSync(bytes);
      // The path is printed so a reviewer can open the file.
      // ignore: avoid_print
      print('wrote ${out.path}');
      expect(out.lengthSync(), greaterThan(1000));
    });
  }, skip: skipReason);

  /// Ts הוא מצב טקסט שנשאר בתוקף עד שנכתב שוב, ולכן כל בלוק חייב לכתוב אותו.
  test(
    'כל בלוק טקסט כותב rise משלו',
    () async {
      const word = 'וַיֹּ֕אמֶר';
      final file = File(_riseFontPath);
      final shaper = ShaperFont.register(file.readAsBytesSync());
      addTearDown(shaper.dispose);
      final document = PdfDocument(compress: false);
      final pdfFont = PdfShapedFont(
        document,
        shaper: shaper,
        fontBytes: file.readAsBytesSync(),
      );
      final run = shaper.shape(word, rtl: true, script: 'hebr');
      expect(
        [for (var i = 0; i < run.glyphCount; i++) run.yOffset(i)],
        contains(isNot(0)),
        reason: 'אין במילה סימן מוזז אנכית',
      );

      final page = PdfPage(document, pageFormat: PdfPageFormat.a5);
      pdfFont.drawShapedRun(
        page.getGraphics()..setFillColor(PdfColors.black),
        run,
        x: 60,
        y: 300,
        fontSize: 48,
      );
      final text = String.fromCharCodes(await document.save());

      final blocks = 'BT '.allMatches(text).length;
      expect(blocks, greaterThan(1), reason: 'הריצה לא פוצלה לפי ההזזה');
      expect(' Ts '.allMatches(text).length, blocks);
      expect(text, contains('0 Ts'));
    },
    skip: libraryPath == null
        ? 'the native shaper is not built'
        : File(_riseFontPath).existsSync()
        ? null
        : 'the rise test font is missing',
  );
}

/// גופן מוטמע שיש בו הזזה אנכית אמיתית לסימן.
const String _riseFontPath = 'fonts/NotoSerifHebrew-VariableFont_wdth,wght.ttf';

extension on Directory {
  File childFile(String name) => File('$path${Platform.pathSeparator}$name');
}
