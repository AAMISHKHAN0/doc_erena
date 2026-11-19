import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:docerena/core/errors/result.dart';
import 'package:docerena/core/interfaces/i_pdf_generator.dart';
import 'package:docerena/services/pdf/pdf_generator_service.dart';

void main() {
  late Directory tempDir;
  late PdfGeneratorService pdfGenerator;
  late String sampleImagePath1;
  late String sampleImagePath2;
  late String sampleImagePath3;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('docerena_pdf_unit_');
    pdfGenerator = PdfGeneratorService(baseOutputDirectory: tempDir.path);

    // Create genuine test images using pure Dart image package
    Uint8List createTestImage(int r, int g, int b, int width, int height) {
      final image = img.Image(width: width, height: height);
      img.fill(image, color: img.ColorRgb8(r, g, b));
      // Draw simple pattern
      img.drawLine(image, x1: 0, y1: 0, x2: width, y2: height, color: const img.ColorRgb8(255, 255, 255));
      return Uint8List.fromList(img.encodePng(image));
    }

    final f1 = File('${tempDir.path}/test_page_1.png');
    await f1.writeAsBytes(createTestImage(220, 50, 50, 200, 300));
    sampleImagePath1 = f1.path;

    final f2 = File('${tempDir.path}/test_page_2.png');
    await f2.writeAsBytes(createTestImage(50, 200, 50, 300, 400));
    sampleImagePath2 = f2.path;

    final f3 = File('${tempDir.path}/test_page_3.png');
    await f3.writeAsBytes(createTestImage(50, 50, 220, 250, 350));
    sampleImagePath3 = f3.path;
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('PdfGeneratorService - PDF Generation Core Requirements', () {
    test('verifies %PDF- magic prefix and %%EOF trailer marker', () async {
      final pages = [
        PdfPageSpec(
          imagePath: sampleImagePath1,
          rotationDegrees: 0,
          position: 0,
          pixelWidth: 200,
          pixelHeight: 300,
        ),
      ];

      final result = await pdfGenerator.generateMultipagePdf(
        documentTitle: 'MagicHeaderVerification',
        pages: pages,
        pageFormat: PdfPageFormat.a4,
        quality: PdfQualityPreset.high,
      );

      expect(result.isSuccess, isTrue);
      final pdfInfo = result.dataOrNull!;
      expect(pdfInfo.pageCount, equals(1));
      expect(pdfInfo.fileSizeBytes, greaterThan(0));

      final file = File(pdfInfo.filePath);
      expect(await file.exists(), isTrue);

      final bytes = await file.readAsBytes();
      // ISO 32000 verification
      final header = String.fromCharCodes(bytes.sublist(0, 5));
      expect(header, equals('%PDF-'));

      final content = String.fromCharCodes(bytes);
      expect(content, contains('%%EOF'));
    });

    test('generates multipage PDF with exact sequential page count (3 pages)', () async {
      final pages = [
        PdfPageSpec(
          imagePath: sampleImagePath1,
          rotationDegrees: 0,
          position: 0,
          pixelWidth: 200,
          pixelHeight: 300,
        ),
        PdfPageSpec(
          imagePath: sampleImagePath2,
          rotationDegrees: 90,
          position: 1,
          pixelWidth: 300,
          pixelHeight: 400,
        ),
        PdfPageSpec(
          imagePath: sampleImagePath3,
          rotationDegrees: 180,
          position: 2,
          pixelWidth: 250,
          pixelHeight: 350,
        ),
      ];

      final result = await pdfGenerator.generateMultipagePdf(
        documentTitle: 'ThreePageContract',
        pages: pages,
        pageFormat: PdfPageFormat.a4,
        quality: PdfQualityPreset.medium,
      );

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull?.pageCount, equals(3));

      // Validate through validation service
      final validation = await pdfGenerator.validatePdfFile(result.dataOrNull!.filePath);
      expect(validation.isSuccess, isTrue);
      expect(validation.dataOrNull?.isValid, isTrue);
      expect(validation.dataOrNull?.pageCount, equals(3));
      expect(validation.dataOrNull?.errorReason, isNull);
    });

    test('supports all page formats: A4, Letter, and FitToImage', () async {
      final testSpecs = [
        PdfPageSpec(
          imagePath: sampleImagePath1,
          rotationDegrees: 0,
          position: 0,
          pixelWidth: 200,
          pixelHeight: 300,
        ),
      ];

      for (final format in [
        PdfPageFormat.a4,
        PdfPageFormat.letter,
        PdfPageFormat.fitToImage,
      ]) {
        final result = await pdfGenerator.generateMultipagePdf(
          documentTitle: 'Format_${format.name}',
          pages: testSpecs,
          pageFormat: format,
          quality: PdfQualityPreset.high,
        );

        expect(result.isSuccess, isTrue, reason: 'Failed for format ${format.name}');
        final val = await pdfGenerator.validatePdfFile(result.dataOrNull!.filePath);
        expect(val.dataOrNull?.isValid, isTrue);
        expect(val.dataOrNull?.pageCount, equals(1));
      }
    });

    test('supports all quality presets: High, Medium, and Low', () async {
      final testSpecs = [
        PdfPageSpec(
          imagePath: sampleImagePath2,
          rotationDegrees: 0,
          position: 0,
          pixelWidth: 300,
          pixelHeight: 400,
        ),
      ];

      for (final quality in [
        PdfQualityPreset.high,
        PdfQualityPreset.medium,
        PdfQualityPreset.low,
      ]) {
        final result = await pdfGenerator.generateMultipagePdf(
          documentTitle: 'Quality_${quality.name}',
          pages: testSpecs,
          pageFormat: PdfPageFormat.a4,
          quality: quality,
        );

        expect(result.isSuccess, isTrue, reason: 'Failed for quality ${quality.name}');
        final fileBytes = await File(result.dataOrNull!.filePath).readAsBytes();
        expect(fileBytes.length, greaterThan(100));
      }
    });

    test('rotations 90, 180, and 270 degrees compile cleanly', () async {
      final rotatedPages = [
        PdfPageSpec(
          imagePath: sampleImagePath1,
          rotationDegrees: 90,
          position: 0,
          pixelWidth: 200,
          pixelHeight: 300,
        ),
        PdfPageSpec(
          imagePath: sampleImagePath2,
          rotationDegrees: 270,
          position: 1,
          pixelWidth: 300,
          pixelHeight: 400,
        ),
      ];

      final result = await pdfGenerator.generateMultipagePdf(
        documentTitle: 'RotatedPagesDocument',
        pages: rotatedPages,
        pageFormat: PdfPageFormat.letter,
        quality: PdfQualityPreset.high,
      );

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull?.pageCount, equals(2));
    });
  });

  group('PdfGeneratorService - Validation and Edge Cases', () {
    test('returns emptyDocument failure when pages sequence is empty', () async {
      final result = await pdfGenerator.generateMultipagePdf(
        documentTitle: 'EmptyDoc',
        pages: [],
        pageFormat: PdfPageFormat.a4,
        quality: PdfQualityPreset.medium,
      );

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.code, equals(PdfExportErrorCode.emptyDocument));
    });

    test('returns ioError failure when source page image does not exist', () async {
      final missingPage = [
        const PdfPageSpec(
          imagePath: '/non_existent_path_to_image_9999.png',
          rotationDegrees: 0,
          position: 0,
          pixelWidth: 100,
          pixelHeight: 100,
        ),
      ];

      final result = await pdfGenerator.generateMultipagePdf(
        documentTitle: 'MissingImageDoc',
        pages: missingPage,
        pageFormat: PdfPageFormat.a4,
        quality: PdfQualityPreset.medium,
      );

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.code, equals(PdfExportErrorCode.ioError));
    });

    test('validatePdfFile returns ioError when file does not exist', () async {
      final valResult = await pdfGenerator.validatePdfFile('${tempDir.path}/does_not_exist.pdf');
      expect(valResult.isFailure, isTrue);
      expect(valResult.errorOrNull?.code, equals(PdfExportErrorCode.ioError));
    });

    test('validatePdfFile detects invalid non-PDF header', () async {
      final corruptFile = File('${tempDir.path}/corrupt.pdf');
      await corruptFile.writeAsString('NOT_A_PDF_FILE_HEADER_1234567890%%EOF');

      final valResult = await pdfGenerator.validatePdfFile(corruptFile.path);
      expect(valResult.isSuccess, isTrue);
      final info = valResult.dataOrNull!;
      expect(info.isValid, isFalse);
      expect(info.errorReason, contains('Invalid PDF header'));
    });

    test('validatePdfFile detects missing %%EOF marker', () async {
      final incompleteFile = File('${tempDir.path}/incomplete.pdf');
      await incompleteFile.writeAsString('%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\n');

      final valResult = await pdfGenerator.validatePdfFile(incompleteFile.path);
      expect(valResult.isSuccess, isTrue);
      final info = valResult.dataOrNull!;
      expect(info.isValid, isFalse);
      expect(info.errorReason, contains('Missing %%EOF'));
    });

    test('validatePdfFile detects file too small', () async {
      final tinyFile = File('${tempDir.path}/tiny.pdf');
      await tinyFile.writeAsBytes([37, 80, 68]); // 3 bytes

      final valResult = await pdfGenerator.validatePdfFile(tinyFile.path);
      expect(valResult.isSuccess, isTrue);
      final info = valResult.dataOrNull!;
      expect(info.isValid, isFalse);
      expect(info.errorReason, contains('File too small'));
    });
  });
}
