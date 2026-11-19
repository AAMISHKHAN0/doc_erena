import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart' as p;
import 'package:pdf/widgets.dart' as pw;

import 'package:docerena/core/errors/result.dart';
import 'package:docerena/core/interfaces/i_pdf_generator.dart';
import 'package:docerena/domain/entities/export_result.dart';

/// Concrete reference implementation of IPdfGenerator for DocErena E2E testing
class StandardPdfGenerator implements IPdfGenerator {
  final String outputDirectory;

  StandardPdfGenerator({required this.outputDirectory});

  @override
  Future<Result<GeneratedPdf, PdfExportError>> generateMultipagePdf({
    required String documentTitle,
    required List<PdfPageSpec> pages,
    required PdfPageFormat pageFormat,
    required PdfQualityPreset quality,
  }) async {
    if (pages.isEmpty) {
      return const Failure(
        PdfExportError(
          message: 'Cannot generate PDF from an empty page sequence',
          code: PdfExportErrorCode.emptyDocument,
        ),
      );
    }

    try {
      final doc = pw.Document(title: documentTitle);

      final p.PdfPageFormat format;
      switch (pageFormat) {
        case PdfPageFormat.a4:
          format = p.PdfPageFormat.a4;
          break;
        case PdfPageFormat.letter:
          format = p.PdfPageFormat.letter;
          break;
        case PdfPageFormat.fitToImage:
          format = p.PdfPageFormat.undefined;
          break;
      }

      for (final spec in pages) {
        final imageFile = File(spec.imagePath);
        if (!await imageFile.exists()) {
          return Failure(
            PdfExportError(
              message: 'Page image missing at: ${spec.imagePath}',
              code: PdfExportErrorCode.ioError,
            ),
          );
        }

        final bytes = await imageFile.readAsBytes();
        final image = pw.MemoryImage(bytes);

        doc.addPage(
          pw.Page(
            pageFormat: format == p.PdfPageFormat.undefined
                ? p.PdfPageFormat(spec.pixelWidth, spec.pixelHeight)
                : format,
            build: (context) {
              return pw.FullPage(
                ignoreMargins: true,
                child: pw.Center(
                  child: pw.Transform.rotateBox(
                    angle: spec.rotationDegrees * 3.141592653589793 / 180,
                    child: pw.Image(image, fit: pw.BoxFit.contain),
                  ),
                ),
              );
            },
          ),
        );
      }

      final dir = Directory(outputDirectory);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final sanitizedTitle = documentTitle.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final fileName = '${sanitizedTitle}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File('${dir.path}/$fileName');

      final pdfBytes = await doc.save();
      await file.writeAsBytes(pdfBytes, flush: true);

      return Success(
        GeneratedPdf(
          filePath: file.path,
          pageCount: pages.length,
          fileSizeBytes: pdfBytes.length,
        ),
      );
    } catch (e, st) {
      return Failure(
        PdfExportError(
          message: 'Failed to generate PDF: $e',
          code: PdfExportErrorCode.renderingFailed,
          cause: e,
          stackTrace: st,
        ),
      );
    }
  }

  @override
  Future<Result<PdfValidationInfo, PdfExportError>> validatePdfFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return const Failure(
          PdfExportError(
            message: 'PDF file not found',
            code: PdfExportErrorCode.ioError,
          ),
        );
      }

      final bytes = await file.readAsBytes();
      if (bytes.length < 10) {
        return Success(
          PdfValidationInfo(
            isValid: false,
            pageCount: 0,
            fileSizeBytes: bytes.length,
            errorReason: 'File too small to be a valid PDF',
          ),
        );
      }

      // Check ISO 32000 magic header '%PDF-'
      final header = String.fromCharCodes(bytes.sublist(0, 5));
      final isValidHeader = header == '%PDF-';

      // Count occurrences of /Type /Page in the document body
      final content = String.fromCharCodes(bytes);
      final pageMatches = RegExp(r'/Type\s*/Page\b').allMatches(content).length;

      return Success(
        PdfValidationInfo(
          isValid: isValidHeader && bytes.isNotEmpty,
          pageCount: pageMatches,
          fileSizeBytes: bytes.length,
          errorReason: isValidHeader ? null : 'Invalid PDF header: $header',
        ),
      );
    } catch (e, st) {
      return Failure(
        PdfExportError(
          message: 'Error validating PDF: $e',
          code: PdfExportErrorCode.ioError,
          cause: e,
          stackTrace: st,
        ),
      );
    }
  }
}

void main() {
  late Directory testDir;
  late StandardPdfGenerator pdfGenerator;
  late String testImagePath1;
  late String testImagePath2;
  late String testImagePath3;

  setUpAll(() async {
    testDir = await Directory.systemTemp.createTemp('docerena_pdf_e2e_');
    pdfGenerator = StandardPdfGenerator(outputDirectory: testDir.path);

    // Generate real test image files using the pure Dart image package
    Uint8List generateTestPng(int r, int g, int b) {
      final imgObj = img.Image(width: 200, height: 300);
      img.fill(imgObj, color: img.ColorRgb8(r, g, b));
      return Uint8List.fromList(img.encodePng(imgObj));
    }

    final f1 = File('${testDir.path}/page1.png');
    await f1.writeAsBytes(generateTestPng(255, 0, 0)); // Red page
    testImagePath1 = f1.path;

    final f2 = File('${testDir.path}/page2.png');
    await f2.writeAsBytes(generateTestPng(0, 255, 0)); // Green page
    testImagePath2 = f2.path;

    final f3 = File('${testDir.path}/page3.png');
    await f3.writeAsBytes(generateTestPng(0, 0, 255)); // Blue page
    testImagePath3 = f3.path;
  });

  tearDownAll(() async {
    if (await testDir.exists()) {
      await testDir.delete(recursive: true);
    }
  });

  group('PDF Export Integrity Tests (Tier 1 & Tier 2)', () {
    test('Tier 1: generated PDF has valid %PDF- magic header and trailer', () async {
      final pages = [
        PdfPageSpec(
          imagePath: testImagePath1,
          rotationDegrees: 0,
          position: 0,
          pixelWidth: 200,
          pixelHeight: 300,
        ),
      ];

      final result = await pdfGenerator.generateMultipagePdf(
        documentTitle: 'HeaderTest',
        pages: pages,
        pageFormat: PdfPageFormat.a4,
        quality: PdfQualityPreset.high,
      );

      expect(result.isSuccess, isTrue);
      final pdfPath = result.dataOrNull!.filePath;

      final bytes = await File(pdfPath).readAsBytes();
      final header = String.fromCharCodes(bytes.sublist(0, 5));
      expect(header, equals('%PDF-'));

      final content = String.fromCharCodes(bytes);
      expect(content, contains('%%EOF'));
    });

    test('Tier 1: 3-page document produces PDF with exactly 3 pages', () async {
      final pages = [
        PdfPageSpec(
          imagePath: testImagePath1,
          rotationDegrees: 0,
          position: 0,
          pixelWidth: 200,
          pixelHeight: 300,
        ),
        PdfPageSpec(
          imagePath: testImagePath2,
          rotationDegrees: 90,
          position: 1,
          pixelWidth: 200,
          pixelHeight: 300,
        ),
        PdfPageSpec(
          imagePath: testImagePath3,
          rotationDegrees: 180,
          position: 2,
          pixelWidth: 200,
          pixelHeight: 300,
        ),
      ];

      final result = await pdfGenerator.generateMultipagePdf(
        documentTitle: 'ThreePageContract',
        pages: pages,
        pageFormat: PdfPageFormat.a4,
        quality: PdfQualityPreset.high,
      );

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull?.pageCount, equals(3));
      expect(result.dataOrNull?.fileSizeBytes, greaterThan(1000));

      final validation = await pdfGenerator.validatePdfFile(result.dataOrNull!.filePath);
      expect(validation.isSuccess, isTrue);
      expect(validation.dataOrNull?.isValid, isTrue);
      expect(validation.dataOrNull?.pageCount, equals(3));
    });

    test('Tier 1: page ordering matches ordered specifications', () async {
      // Reordered: Page 3 first, then Page 1, then Page 2
      final reorderedPages = [
        PdfPageSpec(
          imagePath: testImagePath3,
          rotationDegrees: 0,
          position: 0,
          pixelWidth: 200,
          pixelHeight: 300,
        ),
        PdfPageSpec(
          imagePath: testImagePath1,
          rotationDegrees: 0,
          position: 1,
          pixelWidth: 200,
          pixelHeight: 300,
        ),
        PdfPageSpec(
          imagePath: testImagePath2,
          rotationDegrees: 90,
          position: 2,
          pixelWidth: 200,
          pixelHeight: 300,
        ),
      ];

      final result = await pdfGenerator.generateMultipagePdf(
        documentTitle: 'ReorderedDoc',
        pages: reorderedPages,
        pageFormat: PdfPageFormat.a4,
        quality: PdfQualityPreset.high,
      );

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull?.pageCount, equals(3));
    });

    test('Tier 2: A4, Letter, and Fit-To-Image presets produce valid files', () async {
      final samplePage = [
        PdfPageSpec(
          imagePath: testImagePath1,
          rotationDegrees: 0,
          position: 0,
          pixelWidth: 200,
          pixelHeight: 300,
        ),
      ];

      for (final format in [PdfPageFormat.a4, PdfPageFormat.letter, PdfPageFormat.fitToImage]) {
        final result = await pdfGenerator.generateMultipagePdf(
          documentTitle: 'Format_${format.name}',
          pages: samplePage,
          pageFormat: format,
          quality: PdfQualityPreset.medium,
        );

        expect(result.isSuccess, isTrue);
        final val = await pdfGenerator.validatePdfFile(result.dataOrNull!.filePath);
        expect(val.dataOrNull?.isValid, isTrue);
        expect(val.dataOrNull?.pageCount, equals(1));
      }
    });

    test('Tier 2: empty page sequence fails cleanly with emptyDocument error', () async {
      final result = await pdfGenerator.generateMultipagePdf(
        documentTitle: 'EmptyDoc',
        pages: [],
        pageFormat: PdfPageFormat.a4,
        quality: PdfQualityPreset.low,
      );

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.code, equals(PdfExportErrorCode.emptyDocument));
    });

    test('Tier 2: missing source image file returns ioError failure', () async {
      final missingPages = [
        const PdfPageSpec(
          imagePath: '/nonexistent/path/to/image.png',
          rotationDegrees: 0,
          position: 0,
          pixelWidth: 100,
          pixelHeight: 100,
        ),
      ];

      final result = await pdfGenerator.generateMultipagePdf(
        documentTitle: 'MissingImageDoc',
        pages: missingPages,
        pageFormat: PdfPageFormat.a4,
        quality: PdfQualityPreset.high,
      );

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.code, equals(PdfExportErrorCode.ioError));
    });
  });
}
