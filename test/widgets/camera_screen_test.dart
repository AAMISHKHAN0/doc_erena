import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:docerena/core/errors/result.dart';
import 'package:docerena/core/geometry/crop_polygon.dart';
import 'package:docerena/core/interfaces/i_document_scanner.dart';
import 'package:docerena/presentation/screens/s03_camera/camera_screen.dart';

class _FakeDocumentScanner implements IDocumentScanner {
  int captureCallCount = 0;
  int galleryCallCount = 0;
  CameraFlashMode? lastFlashMode;
  bool shouldFailCapture = false;

  @override
  Future<Result<ScannedImage, ScannerError>> capturePage({
    required CameraFlashMode flashMode,
  }) async {
    captureCallCount++;
    lastFlashMode = flashMode;

    if (shouldFailCapture) {
      return const Failure(
        ScannerError(
          message: 'Simulated hardware capture failure',
          code: ScannerErrorCode.captureFailed,
        ),
      );
    }

    return Success(
      ScannedImage(
        imagePath: '/fake/storage/page_$captureCallCount.jpg',
        pixelWidth: 800,
        pixelHeight: 1050,
        capturedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<Result<List<ScannedImage>, ScannerError>> importFromGallery() async {
    galleryCallCount++;
    return Success([
      ScannedImage(
        imagePath: '/fake/storage/gallery_1.jpg',
        pixelWidth: 600,
        pixelHeight: 800,
        capturedAt: DateTime.now(),
      ),
      ScannedImage(
        imagePath: '/fake/storage/gallery_2.jpg',
        pixelWidth: 600,
        pixelHeight: 800,
        capturedAt: DateTime.now(),
      ),
    ]);
  }

  @override
  Future<Result<CropPolygon, ScannerError>> detectDocumentCorners(String imagePath) async {
    return Success(CropPolygon.fullFrame());
  }

  @override
  Future<Result<String, ScannerError>> applyCropAndPerspective({
    required String originalImagePath,
    required CropPolygon polygon,
    required String targetPath,
  }) async {
    return Success(targetPath);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeDocumentScanner fakeScanner;

  setUp(() {
    fakeScanner = _FakeDocumentScanner();
  });

  Widget buildTestWidget({
    ValueChanged<List<ScannedImage>>? onPagesCompleted,
    VoidCallback? onCancel,
    List<ScannedImage>? initialPages,
  }) {
    return MaterialApp(
      home: CameraScreen(
        scanner: fakeScanner,
        onPagesCompleted: onPagesCompleted,
        onCancel: onCancel,
        initialPages: initialPages,
      ),
    );
  }

  group('CameraScreen Widget Tests', () {
    testWidgets('renders all essential camera controls with proper touch targets', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Shutter button (>= 72 dp)
      final shutterFinder = find.bySemanticsLabel('Take photo');
      expect(shutterFinder, findsOneWidget);
      final shutterSize = tester.getSize(shutterFinder);
      expect(shutterSize.width, greaterThanOrEqualTo(72.0));
      expect(shutterSize.height, greaterThanOrEqualTo(72.0));

      // Flash toggle button (>= 48x48 dp)
      final flashFinder = find.bySemanticsLabel('Flash mode: Auto');
      expect(flashFinder, findsOneWidget);
      final flashSize = tester.getSize(flashFinder);
      expect(flashSize.width, greaterThanOrEqualTo(48.0));
      expect(flashSize.height, greaterThanOrEqualTo(48.0));

      // Gallery import button (>= 48x48 dp)
      final galleryFinder = find.bySemanticsLabel('Import photos from gallery');
      expect(galleryFinder, findsOneWidget);
      final gallerySize = tester.getSize(galleryFinder);
      expect(gallerySize.width, greaterThanOrEqualTo(48.0));
      expect(gallerySize.height, greaterThanOrEqualTo(48.0));

      // Viewfinder guidance text
      expect(find.text('Align document inside the frame'), findsOneWidget);
    });

    testWidgets('cycles flash mode on tap', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Flash mode: Auto'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Flash mode: Auto'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Flash mode: On'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Flash mode: On'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Flash mode: Off'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Flash mode: Off'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Flash mode: Auto'), findsOneWidget);
    });

    testWidgets('shutter tap captures page and increments counter badge', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(fakeScanner.captureCallCount, equals(0));

      // Tap shutter
      await tester.tap(find.bySemanticsLabel('Take photo'));
      await tester.pump(); // animation frame
      await tester.pumpAndSettle();

      expect(fakeScanner.captureCallCount, equals(1));
      expect(fakeScanner.lastFlashMode, equals(CameraFlashMode.auto));

      // Counter badge shows "1"
      expect(find.text('1'), findsOneWidget);
      expect(find.bySemanticsLabel('1 pages captured. Tap to review'), findsOneWidget);

      // Tap shutter again
      await tester.tap(find.bySemanticsLabel('Take photo'));
      await tester.pumpAndSettle();

      expect(fakeScanner.captureCallCount, equals(2));
      expect(find.text('2'), findsOneWidget);
      expect(find.bySemanticsLabel('2 pages captured. Tap to review'), findsOneWidget);
    });

    testWidgets('gallery tap imports multiple images and updates counter badge', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Import photos from gallery'));
      await tester.pumpAndSettle();

      expect(fakeScanner.galleryCallCount, equals(1));
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('tapping counter badge finishes session and emits captured pages', (tester) async {
      List<ScannedImage>? completedPages;

      await tester.pumpWidget(
        buildTestWidget(
          onPagesCompleted: (pages) {
            completedPages = pages;
          },
        ),
      );
      await tester.pumpAndSettle();

      // Capture 2 pages
      await tester.tap(find.bySemanticsLabel('Take photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Take photo'));
      await tester.pumpAndSettle();

      // Tap counter badge to complete
      await tester.tap(find.bySemanticsLabel('2 pages captured. Tap to review'));
      await tester.pumpAndSettle();

      expect(completedPages, isNotNull);
      expect(completedPages!.length, equals(2));
    });

    testWidgets('safe back navigation prompts discard/keep draft dialog when pages exist', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          initialPages: [
            ScannedImage(
              imagePath: '/path/doc_1.jpg',
              pixelWidth: 500,
              pixelHeight: 700,
              capturedAt: DateTime.now(),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Tap back button
      await tester.tap(find.bySemanticsLabel('Back, return to previous screen'));
      await tester.pumpAndSettle();

      // Dialog should appear
      expect(find.text('Unsaved Scans'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);
      expect(find.text('Keep Draft'), findsOneWidget);
      expect(find.text('Continue Scanning'), findsOneWidget);

      // Tap Continue Scanning cancels dialog
      await tester.tap(find.text('Continue Scanning'));
      await tester.pumpAndSettle();

      expect(find.text('Unsaved Scans'), findsNothing);
    });

    testWidgets('displays error message when capture fails', (tester) async {
      fakeScanner.shouldFailCapture = true;

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Take photo'));
      await tester.pumpAndSettle();

      expect(find.text('Simulated hardware capture failure'), findsWidgets);
      expect(find.text('Import from Gallery Instead'), findsOneWidget);
    });
  });
}
