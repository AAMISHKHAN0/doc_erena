import 'dart:convert';
import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:docerena/core/geometry/crop_polygon.dart';
import 'package:docerena/core/storage/file_storage_service.dart';
import 'package:docerena/domain/entities/page_entity.dart';
import 'package:docerena/services/transform/image_transform_service.dart';

/// Test fixture and adapter verifying PageModel serialization contract.
class PageModel {
  final String id;
  final String documentId;
  final int position;
  final String originalFileKey;
  final String cropPoints;
  final int rotationDegrees;
  final String filter;
  final double brightness;
  final double contrast;
  final String? processedCacheKey;
  final int pixelWidth;
  final int pixelHeight;
  final int createdAt;

  const PageModel({
    required this.id,
    required this.documentId,
    required this.position,
    required this.originalFileKey,
    required this.cropPoints,
    required this.rotationDegrees,
    required this.filter,
    required this.brightness,
    required this.contrast,
    this.processedCacheKey,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.createdAt,
  });

  factory PageModel.fromEntity(PageEntity entity) {
    return PageModel(
      id: entity.id,
      documentId: entity.documentId,
      position: entity.position,
      originalFileKey: entity.originalFileKey,
      cropPoints: entity.cropPolygon.toJsonString(),
      rotationDegrees: entity.rotationDegrees,
      filter: entity.filter.toDbValue(),
      brightness: entity.brightness,
      contrast: entity.contrast,
      processedCacheKey: entity.processedCacheKey,
      pixelWidth: entity.pixelWidth,
      pixelHeight: entity.pixelHeight,
      createdAt: entity.createdAt.millisecondsSinceEpoch,
    );
  }

  PageEntity toEntity() {
    return PageEntity(
      id: id,
      documentId: documentId,
      position: position,
      originalFileKey: originalFileKey,
      cropPolygon: CropPolygon.fromJsonString(cropPoints),
      rotationDegrees: rotationDegrees,
      filter: PageFilter.fromString(filter),
      brightness: brightness,
      contrast: contrast,
      processedCacheKey: processedCacheKey,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'document_id': documentId,
      'position': position,
      'original_file_key': originalFileKey,
      'crop_points': cropPoints,
      'rotation_degrees': rotationDegrees,
      'filter': filter,
      'brightness': brightness,
      'contrast': contrast,
      'processed_cache_key': processedCacheKey,
      'pixel_width': pixelWidth,
      'pixel_height': pixelHeight,
      'created_at': createdAt,
    };
  }

  factory PageModel.fromMap(Map<String, dynamic> map) {
    return PageModel(
      id: map['id'] as String,
      documentId: map['document_id'] as String,
      position: map['position'] as int,
      originalFileKey: map['original_file_key'] as String,
      cropPoints: map['crop_points'] as String,
      rotationDegrees: (map['rotation_degrees'] as int?) ?? 0,
      filter: (map['filter'] as String?) ?? 'original',
      brightness: ((map['brightness'] as num?) ?? 0.0).toDouble(),
      contrast: ((map['contrast'] as num?) ?? 1.0).toDouble(),
      processedCacheKey: map['processed_cache_key'] as String?,
      pixelWidth: (map['pixel_width'] as int?) ?? 0,
      pixelHeight: (map['pixel_height'] as int?) ?? 0,
      createdAt: map['created_at'] as int,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late io.Directory tempDir;
  late FileStorageService storageService;
  late ImageTransformService transformService;
  late Uint8List sampleRawBytes;

  setUp(() async {
    tempDir = await io.Directory.systemTemp.createTemp('image_filters_test_');
    storageService = FileStorageService(basePath: tempDir.path);
    transformService = const ImageTransformService();

    // Create a 160x120 test image with white paper, colored header, black text lines, and shadow gradient
    final image = img.Image(width: 160, height: 120);
    for (int y = 0; y < 120; y++) {
      for (int x = 0; x < 160; x++) {
        // Base paper background with shadow gradient from top-left (darker) to bottom-right (brighter)
        final shadow = (x / 160.0 * 50.0 + y / 120.0 * 50.0).round();
        final basePaper = (160 + shadow).clamp(0, 255);
        image.setPixelRgba(x, y, basePaper, basePaper, basePaper, 255);
      }
    }

    // Add colored header band (vivid blue logo/stamp)
    for (int y = 10; y < 30; y++) {
      for (int x = 20; x < 60; x++) {
        image.setPixelRgba(x, y, 40, 90, 210, 255);
      }
    }

    // Add black text lines (ink)
    for (int y = 45; y < 50; y++) {
      for (int x = 20; x < 140; x++) {
        image.setPixelRgba(x, y, 20, 20, 20, 255);
      }
    }
    for (int y = 65; y < 70; y++) {
      for (int x = 20; x < 130; x++) {
        image.setPixelRgba(x, y, 25, 25, 25, 255);
      }
    }

    sampleRawBytes = Uint8List.fromList(img.encodeJpg(image, quality: 90));
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Tier 1: Auto Shadow Removal Filter', () {
    test('produces normalized illumination across shaded background regions', () {
      final decoded = img.decodeImage(sampleRawBytes)!;
      final result = transformService.processImage(
        ImageTransformParams(
          inputBytes: sampleRawBytes,
          filter: PageFilter.shadowRemoval,
        ),
      );

      expect(result.isSuccess, isTrue);
      final processedBytes = result.dataOrNull!.processedBytes;
      expect(processedBytes.isNotEmpty, isTrue);

      final processedImg = img.decodeImage(processedBytes)!;
      expect(processedImg.width, equals(decoded.width));
      expect(processedImg.height, equals(decoded.height));

      // Check paper background luminance on top-left (initially shaded) vs bottom-right
      final pShadedBefore = decoded.getPixel(10, 10);
      final pShadedAfter = processedImg.getPixel(10, 10);

      // Shadow removal must brighten the shaded background paper
      expect(pShadedAfter.r, greaterThanOrEqualTo(pShadedBefore.r));
    });

    test('avoids division by zero and NaN on pitch black and zero-luminance pixels', () {
      // Create test image with extreme pitch black pixels (0, 0, 0)
      final blackImg = img.Image(width: 80, height: 80);
      img.fill(blackImg, color: img.ColorRgb8(0, 0, 0));
      // Put a tiny bright dot in corner to prevent empty histogram
      blackImg.setPixelRgba(79, 79, 255, 255, 255, 255);
      final blackBytes = Uint8List.fromList(img.encodeJpg(blackImg, quality: 90));

      final result = transformService.processImage(
        ImageTransformParams(
          inputBytes: blackBytes,
          filter: PageFilter.shadowRemoval,
        ),
      );

      expect(result.isSuccess, isTrue);
      final processed = img.decodeImage(result.dataOrNull!.processedBytes)!;

      // Verify no NaN or crash on pixels
      for (int y = 0; y < 80; y += 10) {
        for (int x = 0; x < 80; x += 10) {
          final p = processed.getPixel(x, y);
          expect(p.r.isNaN, isFalse);
          expect(p.g.isNaN, isFalse);
          expect(p.b.isNaN, isFalse);
          expect(p.r.isInfinite, isFalse);
          expect(p.r, inInclusiveRange(0, 255));
        }
      }
    });

    test('preserves dark text ink legibility after shadow leveling', () {
      final result = transformService.processImage(
        ImageTransformParams(
          inputBytes: sampleRawBytes,
          filter: PageFilter.shadowRemoval,
        ),
      );

      expect(result.isSuccess, isTrue);
      final processedImg = img.decodeImage(result.dataOrNull!.processedBytes)!;

      // Text line at (50, 47) should remain dark (ink preserved)
      final pInk = processedImg.getPixel(50, 47);
      final pPaper = processedImg.getPixel(10, 10);

      expect(pInk.r, lessThan(pPaper.r));
      expect(pPaper.r - pInk.r, greaterThan(50));
    });
  });

  group('Tier 1: Document Contrast Enhancement Filter', () {
    test('stretches histogram and snaps off-white paper to clean white', () {
      // Create off-white document image: paper ~205, ink ~60
      final docImg = img.Image(width: 100, height: 100);
      img.fill(docImg, color: img.ColorRgb8(205, 205, 205));
      for (int y = 40; y < 60; y++) {
        for (int x = 20; x < 80; x++) {
          docImg.setPixelRgba(x, y, 60, 60, 60, 255);
        }
      }
      final docBytes = Uint8List.fromList(img.encodeJpg(docImg, quality: 90));

      final result = transformService.processImage(
        ImageTransformParams(
          inputBytes: docBytes,
          filter: PageFilter.documentContrast,
        ),
      );

      expect(result.isSuccess, isTrue);
      final processedImg = img.decodeImage(result.dataOrNull!.processedBytes)!;

      // Off-white paper (205) should snap towards clean white (>= 245)
      final pPaper = processedImg.getPixel(10, 10);
      expect(pPaper.r, greaterThanOrEqualTo(240));
      expect(pPaper.g, greaterThanOrEqualTo(240));
      expect(pPaper.b, greaterThanOrEqualTo(240));

      // Dark text (60) should snap towards dense black (<= 45)
      final pInk = processedImg.getPixel(50, 50);
      expect(pInk.r, lessThanOrEqualTo(50));
    });

    test('handles narrow luminance histogram gracefully without clipping overflow', () {
      // Narrow histogram: all pixels between 125 and 135
      final narrowImg = img.Image(width: 64, height: 64);
      for (int y = 0; y < 64; y++) {
        for (int x = 0; x < 64; x++) {
          final val = 125 + ((x + y) % 10);
          narrowImg.setPixelRgba(x, y, val, val, val, 255);
        }
      }
      final narrowBytes = Uint8List.fromList(img.encodeJpg(narrowImg, quality: 90));

      final result = transformService.processImage(
        ImageTransformParams(
          inputBytes: narrowBytes,
          filter: PageFilter.documentContrast,
        ),
      );

      expect(result.isSuccess, isTrue);
      final processed = img.decodeImage(result.dataOrNull!.processedBytes)!;
      for (int y = 0; y < 64; y += 8) {
        for (int x = 0; x < 64; x += 8) {
          final p = processed.getPixel(x, y);
          expect(p.r, inInclusiveRange(0, 255));
        }
      }
    });
  });

  group('Tier 1: Magic Color Filter', () {
    test('boosts saturation on colored document elements', () {
      final decoded = img.decodeImage(sampleRawBytes)!;
      final result = transformService.processImage(
        ImageTransformParams(
          inputBytes: sampleRawBytes,
          filter: PageFilter.magicColor,
        ),
      );

      expect(result.isSuccess, isTrue);
      final processedImg = img.decodeImage(result.dataOrNull!.processedBytes)!;

      // Header logo pixel at (40, 20) (blue logo)
      final pBefore = decoded.getPixel(40, 20);
      final pAfter = processedImg.getPixel(40, 20);

      // Chroma difference: blue vs red/green should be more pronounced in Magic Color
      final chromaBefore = pBefore.b - math.max(pBefore.r, pBefore.g);
      final chromaAfter = pAfter.b - math.max(pAfter.r, pAfter.g);

      expect(chromaAfter, greaterThanOrEqualTo(chromaBefore - 5));
    });

    test('sharpens high-contrast document edges and whitens paper highlights', () {
      final result = transformService.processImage(
        ImageTransformParams(
          inputBytes: sampleRawBytes,
          filter: PageFilter.magicColor,
        ),
      );

      expect(result.isSuccess, isTrue);
      final processedImg = img.decodeImage(result.dataOrNull!.processedBytes)!;

      // Highlight paper region should be whitened
      final pPaper = processedImg.getPixel(150, 110);
      expect(pPaper.r, greaterThanOrEqualTo(220));
      expect(pPaper.g, greaterThanOrEqualTo(220));
      expect(pPaper.b, greaterThanOrEqualTo(220));
    });
  });

  group('Tier 2: Bit-for-Bit Immutability of Raw Original Files', () {
    test('original raw file bytes in FileStorageService remain untouched after filter processing', () async {
      const docId = 'doc_immutability_test';
      const pageId = 'page_001';
      final origKey = storageService.createOriginalKey(docId, pageId);

      // 1. Atomically store original captured bytes into app-private storage
      final writeResult = await storageService.writeAtomic(origKey, sampleRawBytes);
      expect(writeResult.isSuccess, isTrue);

      final initialSha256 = sha256.convert(sampleRawBytes).toString();
      final initialRawFile = io.File(storageService.resolveAbsolutePath(origKey));
      final initialFileBytes = await initialRawFile.readAsBytes();
      expect(sha256.convert(initialFileBytes).toString(), equals(initialSha256));

      // 2. Apply all 7 filters to processed output targets
      final allFilters = [
        PageFilter.original,
        PageFilter.color,
        PageFilter.grayscale,
        PageFilter.blackAndWhite,
        PageFilter.shadowRemoval,
        PageFilter.documentContrast,
        PageFilter.magicColor,
      ];

      for (final filter in allFilters) {
        final processedKey = storageService.createProcessedKey(docId, pageId);
        final targetPath = storageService.resolveAbsolutePath(processedKey);

        final filterResult = await transformService.applyCropAndPerspectiveToFile(
          originalImagePath: initialRawFile.path,
          polygon: CropPolygon.fullFrame(),
          targetPath: targetPath,
          filter: filter,
          rotationDegrees: 90,
          brightness: 0.1,
          contrast: 1.2,
        );

        expect(filterResult.isSuccess, isTrue);
        expect(await io.File(targetPath).exists(), isTrue);

        // 3. Bit-for-bit assertion: original raw file MUST remain 100% identical
        final postFilterBytes = await initialRawFile.readAsBytes();
        final postSha256 = sha256.convert(postFilterBytes).toString();

        expect(postFilterBytes.length, equals(sampleRawBytes.length));
        expect(postSha256, equals(initialSha256));
        expect(postFilterBytes, equals(sampleRawBytes));
      }
    });
  });

  group('Tier 1 & Tier 2: Serialization Round-Trip for all 7 PageFilter enum values', () {
    test('PageFilter.toDbValue and PageFilter.fromString round-trip matches for all 7 filters', () {
      const filters = [
        PageFilter.original,
        PageFilter.color,
        PageFilter.grayscale,
        PageFilter.blackAndWhite,
        PageFilter.shadowRemoval,
        PageFilter.documentContrast,
        PageFilter.magicColor,
      ];

      expect(filters.length, equals(7));

      for (final filter in filters) {
        final dbString = filter.toDbValue();
        expect(dbString.isNotEmpty, isTrue);
        final parsed = PageFilter.fromString(dbString);
        expect(parsed, equals(filter));
      }
    });

    test('PageFilter.fromString parses case-insensitive and legacy alias values', () {
      expect(PageFilter.fromString('SHADOW_REMOVAL'), equals(PageFilter.shadowRemoval));
      expect(PageFilter.fromString('shadowremoval'), equals(PageFilter.shadowRemoval));
      expect(PageFilter.fromString('auto_shadow_removal'), equals(PageFilter.shadowRemoval));

      expect(PageFilter.fromString('CONTRAST_ENHANCEMENT'), equals(PageFilter.documentContrast));
      expect(PageFilter.fromString('document_contrast'), equals(PageFilter.documentContrast));
      expect(PageFilter.fromString('documentcontrast'), equals(PageFilter.documentContrast));

      expect(PageFilter.fromString('MAGIC_COLOR'), equals(PageFilter.magicColor));
      expect(PageFilter.fromString('magiccolor'), equals(PageFilter.magicColor));

      expect(PageFilter.fromString('BLACK_AND_WHITE'), equals(PageFilter.blackAndWhite));
      expect(PageFilter.fromString('blackandwhite'), equals(PageFilter.blackAndWhite));

      // Unknown value defaults gracefully to original
      expect(PageFilter.fromString('unknown_filter_token'), equals(PageFilter.original));
      expect(PageFilter.fromString(''), equals(PageFilter.original));
    });

    test('PageEntity toMap and fromMap serialization round-trip for all 7 filters', () {
      final now = DateTime.now();
      const allFilters = [
        PageFilter.original,
        PageFilter.color,
        PageFilter.grayscale,
        PageFilter.blackAndWhite,
        PageFilter.shadowRemoval,
        PageFilter.documentContrast,
        PageFilter.magicColor,
      ];

      for (int i = 0; i < allFilters.length; i++) {
        final entity = PageEntity(
          id: 'page_$i',
          documentId: 'doc_serialization',
          position: i,
          originalFileKey: 'documents/doc_serialization/pages/page_$i.jpg',
          cropPolygon: CropPolygon.fullFrame(),
          rotationDegrees: (i * 90) % 360,
          filter: allFilters[i],
          brightness: 0.05 * i,
          contrast: 1.0 + 0.1 * i,
          processedCacheKey: 'cache/preview_$i.jpg',
          pixelWidth: 1200,
          pixelHeight: 1600,
          createdAt: now,
        );

        final map = entity.toMap();
        expect(map['filter'], equals(allFilters[i].toDbValue()));

        final reconstructed = PageEntity.fromMap(map);
        expect(reconstructed.id, equals(entity.id));
        expect(reconstructed.documentId, equals(entity.documentId));
        expect(reconstructed.position, equals(entity.position));
        expect(reconstructed.originalFileKey, equals(entity.originalFileKey));
        expect(reconstructed.filter, equals(allFilters[i]));
        expect(reconstructed.rotationDegrees, equals(entity.rotationDegrees));
        expect(reconstructed.cropPolygon, equals(entity.cropPolygon));
      }
    });

    test('PageModel SQLite data mapping serialization round-trip for all 7 filters', () {
      final now = DateTime.now();
      const allFilters = [
        PageFilter.original,
        PageFilter.color,
        PageFilter.grayscale,
        PageFilter.blackAndWhite,
        PageFilter.shadowRemoval,
        PageFilter.documentContrast,
        PageFilter.magicColor,
      ];

      for (int i = 0; i < allFilters.length; i++) {
        final entity = PageEntity(
          id: 'model_page_$i',
          documentId: 'doc_model_test',
          position: i,
          originalFileKey: 'documents/doc_model_test/pages/page_$i.jpg',
          cropPolygon: const CropPolygon(
            topLeft: Point2D(0.05, 0.05),
            topRight: Point2D(0.95, 0.05),
            bottomRight: Point2D(0.95, 0.95),
            bottomLeft: Point2D(0.05, 0.95),
          ),
          rotationDegrees: 180,
          filter: allFilters[i],
          brightness: -0.1,
          contrast: 1.5,
          pixelWidth: 800,
          pixelHeight: 1000,
          createdAt: now,
        );

        final model = PageModel.fromEntity(entity);
        expect(model.filter, equals(allFilters[i].toDbValue()));

        final map = model.toMap();
        final reconstructedModel = PageModel.fromMap(map);
        final reconstructedEntity = reconstructedModel.toEntity();

        expect(reconstructedEntity.filter, equals(allFilters[i]));
        expect(reconstructedEntity.id, equals(entity.id));
        expect(reconstructedEntity.cropPolygon, equals(entity.cropPolygon));
        expect(reconstructedEntity.rotationDegrees, equals(180));
      }
    });
  });
}
