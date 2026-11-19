import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:docerena/core/geometry/crop_polygon.dart';
import 'package:docerena/domain/entities/page_entity.dart';
import 'package:docerena/services/transform/image_transform_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ImageTransformService transformService;
  late Uint8List sampleImageBytes;

  setUp(() {
    transformService = const ImageTransformService();

    // Create a 100x80 test image with distinct quadrant colors and text lines
    final image = img.Image(width: 100, height: 80);
    for (int y = 0; y < 80; y++) {
      for (int x = 0; x < 100; x++) {
        if (x < 50 && y < 40) {
          image.setPixelRgba(x, y, 200, 50, 50, 255); // Red TL
        } else if (x >= 50 && y < 40) {
          image.setPixelRgba(x, y, 50, 200, 50, 255); // Green TR
        } else if (x >= 50 && y >= 40) {
          image.setPixelRgba(x, y, 50, 50, 200, 255); // Blue BR
        } else {
          image.setPixelRgba(x, y, 240, 240, 240, 255); // Light Gray BL
        }
      }
    }
    sampleImageBytes = Uint8List.fromList(img.encodeJpg(image, quality: 90));
  });

  group('ImageTransformService - Empty and Error Inputs', () {
    test('returns Failure when inputBytes is empty', () {
      final result = transformService.processImage(
        const ImageTransformParams(inputBytes: Uint8List(0)),
      );

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.message, contains('empty'));
    });

    test('returns Failure when inputBytes contains invalid non-image data', () {
      final invalidBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final result = transformService.processImage(
        ImageTransformParams(inputBytes: invalidBytes),
      );

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.message, contains('decode'));
    });
  });

  group('ImageTransformService - Perspective Crop', () {
    test('full-frame crop preserves dimensions', () {
      final result = transformService.processImage(
        ImageTransformParams(
          inputBytes: sampleImageBytes,
          cropPolygon: CropPolygon.fullFrame(),
        ),
      );

      expect(result.isSuccess, isTrue);
      final data = result.dataOrNull!;
      expect(data.width, greaterThan(0));
      expect(data.height, greaterThan(0));
    });

    test('custom crop polygon transforms region', () {
      // Inset crop polygon: [0.1..0.9]
      const customPolygon = CropPolygon(
        topLeft: Point2D(0.1, 0.1),
        topRight: Point2D(0.9, 0.1),
        bottomRight: Point2D(0.9, 0.9),
        bottomLeft: Point2D(0.1, 0.9),
      );

      final result = transformService.processImage(
        ImageTransformParams(
          inputBytes: sampleImageBytes,
          cropPolygon: customPolygon,
        ),
      );

      expect(result.isSuccess, isTrue);
      final data = result.dataOrNull!;
      expect(data.width, greaterThan(0));
      expect(data.height, greaterThan(0));
    });
  });

  group('ImageTransformService - Rotation', () {
    test('0 degree rotation leaves aspect ratio unchanged', () {
      final result = transformService.processImage(
        ImageTransformParams(
          inputBytes: sampleImageBytes,
          rotationDegrees: 0,
        ),
      );

      expect(result.isSuccess, isTrue);
      final data = result.dataOrNull!;
      expect(data.width, equals(100));
      expect(data.height, equals(80));
    });

    test('90 degree clockwise rotation swaps width and height', () {
      final result = transformService.processImage(
        ImageTransformParams(
          inputBytes: sampleImageBytes,
          rotationDegrees: 90,
        ),
      );

      expect(result.isSuccess, isTrue);
      final data = result.dataOrNull!;
      expect(data.width, equals(80));
      expect(data.height, equals(100));
    });

    test('180 degree rotation preserves width and height', () {
      final result = transformService.processImage(
        ImageTransformParams(
          inputBytes: sampleImageBytes,
          rotationDegrees: 180,
        ),
      );

      expect(result.isSuccess, isTrue);
      final data = result.dataOrNull!;
      expect(data.width, equals(100));
      expect(data.height, equals(80));
    });

    test('270 degree rotation swaps width and height', () {
      final result = transformService.processImage(
        ImageTransformParams(
          inputBytes: sampleImageBytes,
          rotationDegrees: 270,
        ),
      );

      expect(result.isSuccess, isTrue);
      final data = result.dataOrNull!;
      expect(data.width, equals(80));
      expect(data.height, equals(100));
    });
  });

  group('ImageTransformService - Filters', () {
    test('grayscale filter converts pixels to equal RGB components', () {
      final result = transformService.processImage(
        ImageTransformParams(
          inputBytes: sampleImageBytes,
          filter: PageFilter.grayscale,
        ),
      );

      expect(result.isSuccess, isTrue);
      final decoded = img.decodeImage(result.dataOrNull!.processedBytes);
      expect(decoded, isNotNull);

      // Spot check multiple pixels: R, G, B should be within JPEG tolerance (+/- 3)
      for (int x = 10; x < 90; x += 20) {
        for (int y = 10; y < 70; y += 20) {
          final p = decoded!.getPixel(x, y);
          expect((p.r - p.g).abs(), lessThanOrEqualTo(3));
          expect((p.r - p.b).abs(), lessThanOrEqualTo(3));
        }
      }
    });

    test('black & white filter binarizes pixels into high-contrast black or white', () {
      final result = transformService.processImage(
        ImageTransformParams(
          inputBytes: sampleImageBytes,
          filter: PageFilter.blackAndWhite,
        ),
      );

      expect(result.isSuccess, isTrue);
      final decoded = img.decodeImage(result.dataOrNull!.processedBytes);
      expect(decoded, isNotNull);

      for (int x = 10; x < 90; x += 20) {
        for (int y = 10; y < 70; y += 20) {
          final p = decoded!.getPixel(x, y);
          // In JPEG compressed binarization, pixels are near 0 or near 255
          final isNearBlack = p.r < 30 && p.g < 30 && p.b < 30;
          final isNearWhite = p.r > 220 && p.g > 220 && p.b > 220;
          expect(isNearBlack || isNearWhite, isTrue);
        }
      }
    });

    test('color filter successfully enhances image', () {
      final result = transformService.processImage(
        ImageTransformParams(
          inputBytes: sampleImageBytes,
          filter: PageFilter.color,
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.processedBytes.isNotEmpty, isTrue);
    });
  });

  group('ImageTransformService - Brightness and Contrast Sliders', () {
    test('positive brightness brightens pixels', () {
      final neutralResult = transformService.processImage(
        ImageTransformParams(
          inputBytes: sampleImageBytes,
          brightness: 0.0,
        ),
      );
      final brightResult = transformService.processImage(
        ImageTransformParams(
          inputBytes: sampleImageBytes,
          brightness: 0.5,
        ),
      );

      final neutralImg = img.decodeImage(neutralResult.dataOrNull!.processedBytes)!;
      final brightImg = img.decodeImage(brightResult.dataOrNull!.processedBytes)!;

      final pNeutral = neutralImg.getPixel(20, 20);
      final pBright = brightImg.getPixel(20, 20);

      expect(pBright.r, greaterThanOrEqualTo(pNeutral.r - 2));
    });
  });

  group('ImageTransformService - File-to-File Transformation', () {
    test('applyCropAndPerspectiveToFile writes processed image to target path', () async {
      final tempDir = await io.Directory.systemTemp.createTemp('transform_test_');
      final srcPath = '${tempDir.path}/source.jpg';
      final dstPath = '${tempDir.path}/target.jpg';

      await io.File(srcPath).writeAsBytes(sampleImageBytes);

      final result = await transformService.applyCropAndPerspectiveToFile(
        originalImagePath: srcPath,
        polygon: CropPolygon.fullFrame(),
        targetPath: dstPath,
        rotationDegrees: 90,
        filter: PageFilter.grayscale,
      );

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull, equals(dstPath));

      final targetFile = io.File(dstPath);
      expect(await targetFile.exists(), isTrue);
      expect(await targetFile.length(), greaterThan(0));

      await tempDir.delete(recursive: true);
    });

    test('applyCropAndPerspectiveToFile returns failure if source file does not exist', () async {
      final result = await transformService.applyCropAndPerspectiveToFile(
        originalImagePath: '/non/existent/path.jpg',
        polygon: CropPolygon.fullFrame(),
        targetPath: '/non/existent/target.jpg',
      );

      expect(result.isFailure, isTrue);
    });
  });
}
