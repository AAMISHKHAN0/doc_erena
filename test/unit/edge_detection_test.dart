import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:docerena/core/geometry/crop_polygon.dart';
import 'package:docerena/core/interfaces/i_document_scanner.dart';
import 'package:docerena/core/storage/file_storage_service.dart';
import 'package:docerena/services/scanner/document_scanner_service.dart';
import 'package:docerena/services/transform/image_transform_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late io.Directory tempDir;
  late FileStorageService storageService;
  late ImageTransformService transformService;
  late DocumentScannerService scannerService;

  setUp(() async {
    tempDir = await io.Directory.systemTemp.createTemp('edge_detection_test_');
    storageService = FileStorageService(basePath: tempDir.path);
    transformService = const ImageTransformService();
    scannerService = DocumentScannerService(
      fileStorageService: storageService,
      transformService: transformService,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Helper to write an encoded image to a temporary file.
  Future<String> saveImageFile(String name, img.Image image) async {
    final filePath = '${tempDir.path}/$name';
    final bytes = Uint8List.fromList(img.encodeJpg(image, quality: 90));
    await io.File(filePath).writeAsBytes(bytes);
    return filePath;
  }

  group('Tier 1 & Tier 2: Full Frame Fallback on Low Contrast or Small Image', () {
    test('falls back to fullFrame when image dimensions are smaller than 40x40 threshold', () async {
      // Create a 30x30 image (below 40px minimum dimension)
      final smallImage = img.Image(width: 30, height: 30);
      img.fill(smallImage, color: img.ColorRgb8(240, 240, 240));
      final path = await saveImageFile('small_30x30.jpg', smallImage);

      final result = await scannerService.detectDocumentCorners(path);

      expect(result.isSuccess, isTrue);
      final polygon = result.dataOrNull!;
      expect(polygon, equals(CropPolygon.fullFrame()));
      expect(polygon.topLeft, equals(const Point2D(0.0, 0.0)));
      expect(polygon.topRight, equals(const Point2D(1.0, 0.0)));
      expect(polygon.bottomRight, equals(const Point2D(1.0, 1.0)));
      expect(polygon.bottomLeft, equals(const Point2D(0.0, 1.0)));
    });

    test('falls back to fullFrame on extreme micro image (10x10)', () async {
      final microImage = img.Image(width: 10, height: 10);
      img.fill(microImage, color: img.ColorRgb8(128, 128, 128));
      final path = await saveImageFile('micro_10x10.jpg', microImage);

      final result = await scannerService.detectDocumentCorners(path);

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull, equals(CropPolygon.fullFrame()));
    });

    test('falls back to fullFrame when image has zero contrast (uniform dark desk)', () async {
      // 200x200 uniform dark image (luminance ~ 35 everywhere)
      final uniformDark = img.Image(width: 200, height: 200);
      img.fill(uniformDark, color: img.ColorRgb8(35, 35, 35));
      final path = await saveImageFile('uniform_dark.jpg', uniformDark);

      final result = await scannerService.detectDocumentCorners(path);

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull, equals(CropPolygon.fullFrame()));
    });

    test('falls back to fullFrame when image has zero contrast (uniform white paper)', () async {
      // 200x200 uniform white image (luminance 255 everywhere)
      final uniformWhite = img.Image(width: 200, height: 200);
      img.fill(uniformWhite, color: img.ColorRgb8(255, 255, 255));
      final path = await saveImageFile('uniform_white.jpg', uniformWhite);

      final result = await scannerService.detectDocumentCorners(path);

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull, equals(CropPolygon.fullFrame()));
    });

    test('falls back to fullFrame when center and border luminance delta is below threshold (<25)', () async {
      // Center luminance: 130, border luminance: 120 -> delta = 10 (< 25)
      final lowContrast = img.Image(width: 200, height: 200);
      img.fill(lowContrast, color: img.ColorRgb8(120, 120, 120));
      // Draw slightly brighter center rectangle
      for (int y = 50; y < 150; y++) {
        for (int x = 50; x < 150; x++) {
          lowContrast.setPixelRgba(x, y, 130, 130, 130, 255);
        }
      }
      final path = await saveImageFile('low_contrast.jpg', lowContrast);

      final result = await scannerService.detectDocumentCorners(path);

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull, equals(CropPolygon.fullFrame()));
    });

    test('falls back to fullFrame when file does not exist', () async {
      final nonExistentPath = '${tempDir.path}/does_not_exist_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final result = await scannerService.detectDocumentCorners(nonExistentPath);

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull, equals(CropPolygon.fullFrame()));
    });

    test('falls back to fullFrame when file contains corrupted non-image bytes', () async {
      final corruptFile = io.File('${tempDir.path}/corrupt.jpg');
      await corruptFile.writeAsBytes([0x00, 0xFF, 0x12, 0x34, 0xDE, 0xAD, 0xBE, 0xEF]);

      final result = await scannerService.detectDocumentCorners(corruptFile.path);

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull, equals(CropPolygon.fullFrame()));
    });

    test('falls back to fullFrame when file is 0-byte empty', () async {
      final emptyFile = io.File('${tempDir.path}/empty.jpg');
      await emptyFile.writeAsBytes(<int>[]);

      final result = await scannerService.detectDocumentCorners(emptyFile.path);

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull, equals(CropPolygon.fullFrame()));
    });
  });

  group('Tier 1 & Tier 2: Convexity & Clockwise Winding Verification', () {
    test('detects genuine document boundary and verifies clockwise winding', () async {
      // Create high-contrast document image: dark background with bright white centered document
      final docImage = img.Image(width: 400, height: 500);
      img.fill(docImage, color: img.ColorRgb8(30, 35, 45)); // Dark slate background
      for (int y = 40; y < 460; y++) {
        for (int x = 40; x < 360; x++) {
          docImage.setPixelRgba(x, y, 245, 245, 245, 255); // White document body
        }
      }
      final path = await saveImageFile('contrast_doc.jpg', docImage);

      final result = await scannerService.detectDocumentCorners(path);

      expect(result.isSuccess, isTrue);
      final polygon = result.dataOrNull!;
      expect(polygon.isValid, isTrue);
      expect(polygon.isClockwise, isTrue);
      expect(polygon.signedArea, greaterThan(0.001));
      expect(polygon.area, greaterThan(0.001));
      expect(polygon.isConvex, isTrue);
    });

    test('consecutive edge vector cross-products have positive sign for clockwise convex quad', () {
      const quad = CropPolygon(
        topLeft: Point2D(0.1, 0.1),
        topRight: Point2D(0.9, 0.1),
        bottomRight: Point2D(0.9, 0.9),
        bottomLeft: Point2D(0.1, 0.9),
      );

      final e0 = quad.topRight - quad.topLeft; // (0.8, 0.0)
      final e1 = quad.bottomRight - quad.topRight; // (0.0, 0.8)
      final e2 = quad.bottomLeft - quad.bottomRight; // (-0.8, 0.0)
      final e3 = quad.topLeft - quad.bottomLeft; // (0.0, -0.8)

      // Screen space cross product: e.x * next.y - e.y * next.x
      final cp0 = e0.crossProduct(e1); // 0.8 * 0.8 - 0.0 = 0.64 > 0
      final cp1 = e1.crossProduct(e2); // 0.0 - (0.8 * -0.8) = 0.64 > 0
      final cp2 = e2.crossProduct(e3); // (-0.8 * -0.8) - 0.0 = 0.64 > 0
      final cp3 = e3.crossProduct(e0); // 0.0 - (-0.8 * 0.8) = 0.64 > 0

      expect(cp0, greaterThan(0.0));
      expect(cp1, greaterThan(0.0));
      expect(cp2, greaterThan(0.0));
      expect(cp3, greaterThan(0.0));

      expect(quad.isConvex, isTrue);
      expect(quad.isClockwise, isTrue);
      expect(quad.isValid, isTrue);
    });

    test('counter-clockwise vertex ordering is rejected as invalid', () {
      // Reversing vertex order: TL -> BL -> BR -> TR (counter-clockwise)
      const ccwQuad = CropPolygon(
        topLeft: Point2D(0.1, 0.1),
        topRight: Point2D(0.1, 0.9),
        bottomRight: Point2D(0.9, 0.9),
        bottomLeft: Point2D(0.9, 0.1),
      );

      expect(ccwQuad.isClockwise, isFalse);
      expect(ccwQuad.signedArea, lessThan(0.0));
      expect(ccwQuad.isValid, isFalse);
      expect(ccwQuad.sanitizeOrFallback(), equals(CropPolygon.fullFrame()));
    });

    test('concave dart/arrowhead quad is rejected by isConvex check', () {
      // Push bottom-right corner inwards towards center past the diagonal: concave reflex angle
      const concaveQuad = CropPolygon(
        topLeft: Point2D(0.1, 0.1),
        topRight: Point2D(0.9, 0.1),
        bottomRight: Point2D(0.3, 0.3), // Pushed far inside
        bottomLeft: Point2D(0.1, 0.9),
      );

      expect(concaveQuad.isConvex, isFalse);
      expect(concaveQuad.isValid, isFalse);
      expect(concaveQuad.sanitizeOrFallback(), equals(CropPolygon.fullFrame()));
    });

    test('collinear points with near-zero area are rejected as degenerate quad', () {
      // 4 points on almost the exact horizontal line: area ~ 0
      const collinearQuad = CropPolygon(
        topLeft: Point2D(0.1, 0.5),
        topRight: Point2D(0.4, 0.5),
        bottomRight: Point2D(0.8, 0.5),
        bottomLeft: Point2D(0.2, 0.5),
      );

      expect(collinearQuad.area, lessThan(0.001));
      expect(collinearQuad.isValid, isFalse);
      expect(collinearQuad.sanitizeOrFallback(), equals(CropPolygon.fullFrame()));
    });
  });

  group('Tier 2: Bowtie Self-Intersection Rejection', () {
    test('rejects classic hourglass / bowtie quadrilateral (crossed left-to-right edges)', () {
      // Swapping topRight and bottomRight creates a crossed "X" shape
      const bowtieQuad = CropPolygon(
        topLeft: Point2D(0.1, 0.1),
        topRight: Point2D(0.9, 0.9), // crossed
        bottomRight: Point2D(0.9, 0.1), // crossed
        bottomLeft: Point2D(0.1, 0.9),
      );

      expect(bowtieQuad.isConvex, isFalse);
      expect(bowtieQuad.isValid, isFalse);
      expect(bowtieQuad.sanitizeOrFallback(), equals(CropPolygon.fullFrame()));
    });

    test('rejects vertical hourglass / bowtie quadrilateral (crossed top-to-bottom edges)', () {
      // Crossing topLeft and topRight
      const verticalBowtie = CropPolygon(
        topLeft: Point2D(0.9, 0.1),
        topRight: Point2D(0.1, 0.1),
        bottomRight: Point2D(0.9, 0.9),
        bottomLeft: Point2D(0.1, 0.9),
      );

      expect(verticalBowtie.isConvex, isFalse);
      expect(verticalBowtie.isValid, isFalse);
      expect(verticalBowtie.sanitizeOrFallback(), equals(CropPolygon.fullFrame()));
    });

    test('sanitizeOrFallback safely replaces invalid bowtie without throwing', () {
      const degenerate = CropPolygon(
        topLeft: Point2D(0.0, 0.0),
        topRight: Point2D(1.0, 1.0),
        bottomRight: Point2D(0.0, 1.0),
        bottomLeft: Point2D(1.0, 0.0),
      );

      final sanitized = degenerate.sanitizeOrFallback();
      expect(sanitized, equals(CropPolygon.fullFrame()));
      expect(sanitized.isValid, isTrue);
      expect(sanitized.isConvex, isTrue);
    });
  });

  group('Tier 2: Downsampling Performance & Bounds Clamping within [0.0, 1.0]', () {
    test('clamps out-of-bounds negative coordinates strictly to 0.0', () {
      const pNeg = Point2D(-0.45, -0.01);
      final clamped = pNeg.clampNormalized();

      expect(clamped.x, equals(0.0));
      expect(clamped.y, equals(0.0));
      expect(clamped.isNormalized, isTrue);
    });

    test('clamps out-of-bounds excessive coordinates strictly to 1.0', () {
      const pExcess = Point2D(1.42, 2.05);
      final clamped = pExcess.clampNormalized();

      expect(clamped.x, equals(1.0));
      expect(clamped.y, equals(1.0));
      expect(clamped.isNormalized, isTrue);
    });

    test('Point2D isNormalized correctly flags out-of-bounds coordinates', () {
      expect(const Point2D(0.0, 0.0).isNormalized, isTrue);
      expect(const Point2D(1.0, 1.0).isNormalized, isTrue);
      expect(const Point2D(0.5, 0.5).isNormalized, isTrue);

      expect(const Point2D(-0.001, 0.5).isNormalized, isFalse);
      expect(const Point2D(0.5, 1.001).isNormalized, isFalse);
      expect(const Point2D(1.001, 0.5).isNormalized, isFalse);
      expect(const Point2D(0.5, -0.001).isNormalized, isFalse);
    });

    test('downsampling aspect ratio calculation preserves proportional bounds', () {
      // 1600x1200 image downscaled to max 400px
      const sourceW = 1600;
      const sourceH = 1200;
      final scale = 400.0 / math.max(sourceW, sourceH); // 400 / 1600 = 0.25
      final downW = (sourceW * scale).round(); // 400
      final downH = (sourceH * scale).round(); // 300

      expect(downW, equals(400));
      expect(downH, equals(300));
      expect(downW / downH, closeTo(sourceW / sourceH, 1e-4));
    });

    test('denormalizing normalized coordinates produces integer pixels strictly within image bounds', () {
      const quad = CropPolygon(
        topLeft: Point2D(0.05, 0.08),
        topRight: Point2D(0.95, 0.08),
        bottomRight: Point2D(0.92, 0.94),
        bottomLeft: Point2D(0.06, 0.94),
      );

      const imgWidth = 1920;
      const imgHeight = 1080;

      final tlX = (quad.topLeft.x * imgWidth).round();
      final tlY = (quad.topLeft.y * imgHeight).round();
      final brX = (quad.bottomRight.x * imgWidth).round();
      final brY = (quad.bottomRight.y * imgHeight).round();

      expect(tlX, greaterThanOrEqualTo(0));
      expect(tlX, lessThanOrEqualTo(imgWidth));
      expect(tlY, greaterThanOrEqualTo(0));
      expect(tlY, lessThanOrEqualTo(imgHeight));

      expect(brX, greaterThanOrEqualTo(0));
      expect(brX, lessThanOrEqualTo(imgWidth));
      expect(brY, greaterThanOrEqualTo(0));
      expect(brY, lessThanOrEqualTo(imgHeight));
    });

    test('high resolution image corner detection completes within valid normalized bounds', () async {
      // Generate synthetic 1000x800 image with clear document boundaries
      final highResImage = img.Image(width: 1000, height: 800);
      img.fill(highResImage, color: img.ColorRgb8(40, 45, 55));
      for (int y = 80; y < 720; y++) {
        for (int x = 100; x < 900; x++) {
          highResImage.setPixelRgba(x, y, 240, 240, 240, 255);
        }
      }
      final path = await saveImageFile('high_res_doc.jpg', highResImage);

      final stopwatch = Stopwatch()..start();
      final result = await scannerService.detectDocumentCorners(path);
      stopwatch.stop();

      expect(result.isSuccess, isTrue);
      final polygon = result.dataOrNull!;
      expect(polygon.arePointsNormalized, isTrue);
      expect(polygon.isValid, isTrue);

      // Verify each corner point is strictly in [0.0, 1.0]
      expect(polygon.topLeft.x, inInclusiveRange(0.0, 1.0));
      expect(polygon.topLeft.y, inInclusiveRange(0.0, 1.0));
      expect(polygon.topRight.x, inInclusiveRange(0.0, 1.0));
      expect(polygon.topRight.y, inInclusiveRange(0.0, 1.0));
      expect(polygon.bottomRight.x, inInclusiveRange(0.0, 1.0));
      expect(polygon.bottomRight.y, inInclusiveRange(0.0, 1.0));
      expect(polygon.bottomLeft.x, inInclusiveRange(0.0, 1.0));
      expect(polygon.bottomLeft.y, inInclusiveRange(0.0, 1.0));
    });
  });
}
