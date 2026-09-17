import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/utils/pdf_font_fallback.dart';
import 'package:pdfrx/pdfrx.dart';

/// PDF עם טקסט עברי גלוי בגופן TrueType שאינו מוטמע — כמו מסכתות הבבלי
/// (ABBYY) וקובצי PDF אישיים רבים.
List<int> _nonEmbeddedHebrewPdf(String fontName) {
  final letters = [for (var i = 0; i < 27; i++) 0x05D0 + i];
  final diffs = letters
      .map((u) => '/uni${u.toRadixString(16).toUpperCase().padLeft(4, '0')}')
      .join(' ');
  final word = 'שלום';
  final codes = word.runes.map((r) => letters.indexOf(r) + 1);
  final content = StringBuffer('BT /F1 36 Tf\n');
  var x = 400.0;
  for (final code in codes) {
    x -= 20;
    content.write(
      '1 0 0 1 $x 700 Tm (\\${code.toRadixString(8).padLeft(3, '0')}) Tj\n',
    );
  }
  content.write('ET');

  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R '
        '/Resources << /Font << /F1 5 0 R >> >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /TrueType /BaseFont /$fontName /FirstChar 0 '
        '/LastChar 255 /Widths [${List.filled(256, '500').join(' ')}] '
        '/Encoding << /Type /Encoding /BaseEncoding /WinAnsiEncoding '
        '/Differences [1 $diffs] >> /FontDescriptor 6 0 R >>',
    '<< /Type /FontDescriptor /FontName /$fontName /Flags 32 '
        '/FontBBox [0 -250 1000 850] /ItalicAngle 0 /Ascent 750 '
        '/Descent -250 /CapHeight 700 /StemV 80 >>',
  ];

  final out = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = out.length;
  out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    out.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
    'startxref\n$xref\n%%EOF\n',
  );
  return latin1.encode(out.toString());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('otzaria-pdf-font-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProviderChannel,
          (call) async => switch (call.method) {
            'getTemporaryDirectory' => tempDir.path,
            _ => null,
          },
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('familyFromPdfFace מסיר קידומת subset וסיומת סגנון', () {
    expect(PdfFontFallback.familyFromPdfFace('David'), 'David');
    expect(PdfFontFallback.familyFromPdfFace('David-Bold'), 'David');
    expect(
      PdfFontFallback.familyFromPdfFace('ABCDEF+Narkisim,Bold'),
      'Narkisim',
    );
  });

  testWidgets(
    'גופן עברי שאינו מוטמע: בלי גופן חלופי האותיות נעלמות, ואיתו הן נחלצות',
    (tester) async {
      await tester.runAsync(() async {
        await pdfrxFlutterInitialize();
        final path = '${tempDir.path}/non_embedded.pdf';
        File(path).writeAsBytesSync(
          _nonEmbeddedHebrewPdf('OtzariaTestHebrewFace'),
        );

        final plain = await PdfDocument.openFile(path);
        final plainText = (await plain.pages[0].loadStructuredText()).fullText;
        await plain.dispose();
        expect(plainText, isNot(contains('שלום')));

        final fixed = await PdfFontFallback.openFile(path);
        final fixedText = (await fixed.pages[0].loadStructuredText()).fullText;
        await fixed.dispose();
        expect(fixedText, contains('שלום'));
      });
    },
  );
}
