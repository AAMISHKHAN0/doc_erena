import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:docerena/core/errors/result.dart';
import 'package:docerena/core/geometry/crop_polygon.dart';
import 'package:docerena/core/interfaces/i_document_scanner.dart';
import 'package:docerena/presentation/screens/s03_camera/camera_screen.dart';

class _MockDocumentScanner implements IDocumentScanner {
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
          message: 'Hardware capture failure',
          code: ScannerErrorCode.captureFailed,
        ),
      );
    }

    return Success(
      ScannedImage(
        imagePath: '/mock/path/page_$captureCallCount.jpg',
        pixelWidth: 800,
        pixelHeight: 1100,
        capturedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<Result<List<ScannedImage>, ScannerError>> importFromGallery() async {
    galleryCallCount++;
    return Success([
      ScannedImage(
        imagePath: '/mock/path/imported_1.jpg',
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

  late _MockDocumentScanner mockScanner;

  setUp(() {
    mockScanner = _MockDocumentScanner();
  });

  Widget createWidget({
    ValueChanged<List<ScannedImage>>? onPagesCompleted,
    VoidCallback? onCancel,
    List<ScannedImage>? initialPages,
  }) {
    return MaterialApp(
      home: CameraScreen(
        scanner: mockScanner,
        onPagesCompleted: onPagesCompleted,
        onCancel: onCancel,
        initialPages: initialPages,
      ),
    );
  }

  group('Scan Document Screen Widget Tests (Design Pack Match)', () {
    testWidgets('Renders real Android SystemUiOverlayStyle and SafeArea', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      final overlayFinder = find.byType(AnnotatedRegion<SystemUiOverlayStyle>);
      expect(overlayFinder, findsOneWidget);

      final overlay = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(overlayFinder);
      expect(overlay.value.statusBarColor, Colors.transparent);
      expect(overlay.value.statusBarIconBrightness, Brightness.dark);

      expect(find.byType(SafeArea), findsOneWidget);
    });

    testWidgets('Renders top bar with Back, "Scan document" title, and lavender Flash button', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.text('Scan document'), findsOneWidget);
      expect(find.bySemanticsLabel('Back, return to previous screen'), findsOneWidget);
      expect(find.bySemanticsLabel('Flash mode: Auto'), findsOneWidget);
    });

    testWidgets('Cycles flash mode on tap', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      final flashFinder = find.bySemanticsLabel('Flash mode: Auto');
      await tester.tap(flashFinder);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Flash mode: On'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Flash mode: On'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Flash mode: Off'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Flash mode: Off'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Flash mode: Auto'), findsOneWidget);
    });

    testWidgets('Renders mode selector pills (Document, ID, Book) and handles switching', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(find.text('Document'), findsOneWidget);
      expect(find.text('ID'), findsOneWidget);
      expect(find.text('Book'), findsOneWidget);

      // Tap ID mode
      await tester.tap(find.text('ID'));
      await tester.pumpAndSettle();

      // Verify guidance SnackBar appears
      expect(find.text('ID Card mode: Capture front side then back side.'), findsOneWidget);

      // Tap Book mode
      await tester.tap(find.text('Book'));
      await tester.pumpAndSettle();

      expect(find.text('Book mode: Dual-page split scanning active.'), findsOneWidget);
    });

    testWidgets('Shutter tap captures frame, increments badge, and displays "Review >" button', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      expect(mockScanner.captureCallCount, 0);

      // Tap shutter
      await tester.tap(find.bySemanticsLabel('Take photo'));
      await tester.pumpAndSettle();

      expect(mockScanner.captureCallCount, 1);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('Review'), findsOneWidget);
      expect(find.bySemanticsLabel('1 pages captured. Tap to review'), findsOneWidget);
    });

    testWidgets('Tapping Review finishes session and emits captured pages', (tester) async {
      List<ScannedImage>? completed;

      await tester.pumpWidget(
        createWidget(
          onPagesCompleted: (pages) => completed = pages,
        ),
      );
      await tester.pumpAndSettle();

      // Capture 1 page
      await tester.tap(find.bySemanticsLabel('Take photo'));
      await tester.pumpAndSettle();

      // Tap Review
      await tester.tap(find.bySemanticsLabel('1 pages captured. Tap to review'));
      await tester.pumpAndSettle();

      expect(completed, isNotNull);
      expect(completed!.length, 1);
    });

    testWidgets('Gallery import button triggers scanner import', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Import photos from gallery'));
      await tester.pumpAndSettle();

      expect(mockScanner.galleryCallCount, 1);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('Review'), findsOneWidget);
    });

    testWidgets('Safe back confirms discard when unsaved pages exist', (tester) async {
      await tester.pumpWidget(
        createWidget(
          initialPages: [
            ScannedImage(
              imagePath: '/test/page.jpg',
              pixelWidth: 600,
              pixelHeight: 800,
              capturedAt: DateTime.now(),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Back, return to previous screen'));
      await tester.pumpAndSettle();

      expect(find.text('Unsaved Scans'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);
      expect(find.text('Keep Draft'), findsOneWidget);
      expect(find.text('Continue Scanning'), findsOneWidget);
    });
  });
}
