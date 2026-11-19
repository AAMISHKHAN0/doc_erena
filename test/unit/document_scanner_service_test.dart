import 'dart:io' as io;
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
  late Uint8List sampleValidImageBytes;

  setUp(() async {
    tempDir = await io.Directory.systemTemp.createTemp('doc_scanner_test_');
    storageService = FileStorageService(basePath: tempDir.path);
    transformService = const ImageTransformService();

    scannerService = DocumentScannerService(
      fileStorageService: storageService,
      transformService: transformService,
    );

    // Create a 120x100 sample image
    final sampleImg = img.Image(width: 120, height: 100);
    img.fill(sampleImg, color: img.ColorRgba8(240, 240, 240, 255));
    sampleValidImageBytes = Uint8List.fromList(img.encodeJpg(sampleImg, quality: 85));
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('DocumentScannerService - Camera Capture', () {
    test('captures page using default simulated camera and saves to app-private storage', () async {
      final result = await scannerService.capturePage(flashMode: CameraFlashMode.auto);

      expect(result.isSuccess, isTrue);
      final scannedImage = result.dataOrNull!;
      expect(scannedImage.imagePath.isNotEmpty, isTrue);
      expect(scannedImage.pixelWidth, equals(800));
      expect(scannedImage.pixelHeight, equals(1050));
      expect(await io.File(scannedImage.imagePath).exists(), isTrue);
    });

    test('captures page using custom camera adapter', () async {
      var adapterCalled = false;
      CameraFlashMode? capturedFlashMode;

      final customScanner = DocumentScannerService(
        fileStorageService: storageService,
        cameraCaptureAdapter: (flashMode) async {
          adapterCalled = true;
          capturedFlashMode = flashMode;
          return sampleValidImageBytes;
        },
      );

      final result = await customScanner.capturePage(flashMode: CameraFlashMode.on);

      expect(result.isSuccess, isTrue);
      expect(adapterCalled, isTrue);
      expect(capturedFlashMode, equals(CameraFlashMode.on));

      final scannedImage = result.dataOrNull!;
      expect(scannedImage.pixelWidth, equals(120));
      expect(scannedImage.pixelHeight, equals(100));
      expect(await io.File(scannedImage.imagePath).exists(), isTrue);
    });

    test('returns failure if adapter returns empty bytes', () async {
      final customScanner = DocumentScannerService(
        fileStorageService: storageService,
        cameraCaptureAdapter: (_) async => Uint8List(0),
      );

      final result = await customScanner.capturePage(flashMode: CameraFlashMode.off);

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.message, contains('empty'));
    });
  });

  group('DocumentScannerService - Gallery Import', () {
    test('imports multiple images preserving selected input order', () async {
      // Create 3 temporary source files
      final file1 = io.File('${tempDir.path}/photo_1.jpg');
      final file2 = io.File('${tempDir.path}/photo_2.jpg');
      final file3 = io.File('${tempDir.path}/photo_3.jpg');

      await file1.writeAsBytes(sampleValidImageBytes);
      await file2.writeAsBytes(sampleValidImageBytes);
      await file3.writeAsBytes(sampleValidImageBytes);

      final sourcePaths = [file1.path, file2.path, file3.path];

      final result = await scannerService.importFromGallery(
        explicitSourcePaths: sourcePaths,
      );

      expect(result.isSuccess, isTrue);
      final imported = result.dataOrNull!;
      expect(imported.length, equals(3));

      // Each imported image must be stored under app-private storage, not the original external path
      for (int i = 0; i < 3; i++) {
        expect(imported[i].imagePath, isNot(equals(sourcePaths[i])));
        expect(await io.File(imported[i].imagePath).exists(), isTrue);
        expect(imported[i].pixelWidth, equals(120));
        expect(imported[i].pixelHeight, equals(100));
      }
    });

    test('skips corrupted files in batch and imports valid files', () async {
      final validFile = io.File('${tempDir.path}/valid.jpg');
      final corruptedFile = io.File('${tempDir.path}/corrupt.jpg');

      await validFile.writeAsBytes(sampleValidImageBytes);
      await corruptedFile.writeAsBytes(Uint8List.fromList([0, 1, 2, 3])); // Non-image

      final result = await scannerService.importFromGallery(
        explicitSourcePaths: [validFile.path, corruptedFile.path],
      );

      expect(result.isSuccess, isTrue);
      final imported = result.dataOrNull!;
      expect(imported.length, equals(1));
      expect(await io.File(imported.first.imagePath).exists(), isTrue);
    });

    test('returns failure if all selected files are invalid or empty', () async {
      final corruptedFile = io.File('${tempDir.path}/corrupt_only.jpg');
      await corruptedFile.writeAsBytes(Uint8List.fromList([99, 100]));

      final result = await scannerService.importFromGallery(
        explicitSourcePaths: [corruptedFile.path],
      );

      expect(result.isFailure, isTrue);
    });

    test('returns cancelled if selection is empty', () async {
      final customScanner = DocumentScannerService(
        fileStorageService: storageService,
        photoPickerAdapter: () async => <String>[],
      );

      final result = await customScanner.importFromGallery();

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.code, equals(ScannerErrorCode.cancelled));
    });
  });

  group('DocumentScannerService - Boundary Corner Detection', () {
    test('returns fullFrame fallback if image does not exist', () async {
      final result = await scannerService.detectDocumentCorners('/non/existent/img.jpg');

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull, equals(CropPolygon.fullFrame()));
    });

    test('detects corners on valid document image', () async {
      final testFile = io.File('${tempDir.path}/doc_capture.jpg');
      final captureResult = await scannerService.capturePage(flashMode: CameraFlashMode.auto);
      expect(captureResult.isSuccess, isTrue);

      final detectResult = await scannerService.detectDocumentCorners(captureResult.dataOrNull!.imagePath);

      expect(detectResult.isSuccess, isTrue);
      final polygon = detectResult.dataOrNull!;
      expect(polygon.isValid, isTrue);
    });

    test('uses custom corner detection adapter when provided', () async {
      const customPoly = CropPolygon(
        topLeft: Point2D(0.05, 0.05),
        topRight: Point2D(0.95, 0.05),
        bottomRight: Point2D(0.95, 0.95),
        bottomLeft: Point2D(0.05, 0.95),
      );

      final customScanner = DocumentScannerService(
        fileStorageService: storageService,
        cornerDetectionAdapter: (_) async => customPoly,
      );

      final result = await customScanner.detectDocumentCorners('any_path.jpg');

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull, equals(customPoly));
    });
  });

  group('DocumentScannerService - Crop and Perspective Delegation', () {
    test('applies crop and perspective saving to target path', () async {
      final srcFile = io.File('${tempDir.path}/orig.jpg');
      final dstFile = io.File('${tempDir.path}/cropped.jpg');
      await srcFile.writeAsBytes(sampleValidImageBytes);

      final result = await scannerService.applyCropAndPerspective(
        originalImagePath: srcFile.path,
        polygon: CropPolygon.fullFrame(),
        targetPath: dstFile.path,
      );

      expect(result.isSuccess, isTrue);
      expect(await dstFile.exists(), isTrue);
    });
  });
}
