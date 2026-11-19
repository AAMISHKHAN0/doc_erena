import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:docerena/core/geometry/crop_polygon.dart';
import 'package:docerena/presentation/screens/s04_crop/crop_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List testImageBytes;

  setUp(() {
    final sampleImg = img.Image(width: 200, height: 150);
    img.fill(sampleImg, color: img.ColorRgba8(220, 220, 220, 255));
    testImageBytes = Uint8List.fromList(img.encodeJpg(sampleImg, quality: 90));
  });

  Widget buildTestWidget({
    CropPolygon? initialPolygon,
    int initialRotation = 0,
    OnCropConfirmed? onConfirm,
    VoidCallback? onCancel,
    VoidCallback? onRetake,
  }) {
    return MaterialApp(
      home: CropScreen(
        imageBytes: testImageBytes,
        initialPolygon: initialPolygon,
        initialRotation: initialRotation,
        onConfirm: onConfirm,
        onCancel: onCancel,
        onRetake: onRetake,
      ),
    );
  }

  group('Adjust Edges (CropScreen) Widget Tests', () {
    testWidgets('renders all toolbar buttons with proper touch targets and labels', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Adjust edges'), findsOneWidget);
      expect(find.text('Drag the corners to fit the page.'), findsOneWidget);

      // Rotate Button (>= 48x48 dp)
      final rotRightFinder = find.bySemanticsLabel('Rotate 90 degrees right');
      expect(rotRightFinder, findsOneWidget);
      final rotRightSize = tester.getSize(rotRightFinder);
      expect(rotRightSize.width, greaterThanOrEqualTo(48.0));
      expect(rotRightSize.height, greaterThanOrEqualTo(48.0));

      // Retake Button (>= 48x48 dp)
      final retakeFinder = find.bySemanticsLabel('Retake photo');
      expect(retakeFinder, findsOneWidget);
      final retakeSize = tester.getSize(retakeFinder);
      expect(retakeSize.width, greaterThanOrEqualTo(48.0));
      expect(retakeSize.height, greaterThanOrEqualTo(48.0));

      // Reset button
      expect(find.text('Reset'), findsOneWidget);

      // Apply crop button
      expect(find.text('Apply crop'), findsOneWidget);
    });

    testWidgets('apply crop emits valid polygon and rotation', (tester) async {
      CropPolygon? confirmedPolygon;
      int? confirmedRotation;

      await tester.pumpWidget(
        buildTestWidget(
          onConfirm: (polygon, rotation) {
            confirmedPolygon = polygon;
            confirmedRotation = rotation;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Apply crop'));
      await tester.pumpAndSettle();

      expect(confirmedPolygon, isNotNull);
      expect(confirmedPolygon!.isValid, isTrue);
      expect(confirmedRotation, equals(0));
    });

    testWidgets('rotation button updates rotation angle', (tester) async {
      CropPolygon? confirmedPolygon;
      int? confirmedRotation;

      await tester.pumpWidget(
        buildTestWidget(
          onConfirm: (polygon, rotation) {
            confirmedPolygon = polygon;
            confirmedRotation = rotation;
          },
        ),
      );
      await tester.pumpAndSettle();

      // Tap rotate twice (0 -> 90 -> 180)
      await tester.tap(find.bySemanticsLabel('Rotate 90 degrees right'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Rotate 90 degrees right'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Apply crop'));
      await tester.pumpAndSettle();

      expect(confirmedRotation, equals(180));
    });

    testWidgets('resets to full frame on button tap', (tester) async {
      // Inset polygon
      const customPoly = CropPolygon(
        topLeft: Point2D(0.2, 0.2),
        topRight: Point2D(0.8, 0.2),
        bottomRight: Point2D(0.8, 0.8),
        bottomLeft: Point2D(0.2, 0.8),
      );

      CropPolygon? confirmedPolygon;

      await tester.pumpWidget(
        buildTestWidget(
          initialPolygon: customPoly,
          onConfirm: (polygon, _) {
            confirmedPolygon = polygon;
          },
        ),
      );
      await tester.pumpAndSettle();

      // Tap Reset
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Apply crop'));
      await tester.pumpAndSettle();

      expect(confirmedPolygon, equals(CropPolygon.fullFrame()));
    });

    testWidgets('retake button triggers callback without applying crop', (tester) async {
      bool retakeCalled = false;
      bool cropConfirmed = false;

      await tester.pumpWidget(
        buildTestWidget(
          onRetake: () => retakeCalled = true,
          onConfirm: (_, __) => cropConfirmed = true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Retake'));
      await tester.pumpAndSettle();

      expect(retakeCalled, isTrue);
      expect(cropConfirmed, isFalse);
    });

    testWidgets('bowtie / invalid polygon displays warning banner and disables Apply crop', (tester) async {
      // Create self-intersecting bowtie quad
      const bowtiePoly = CropPolygon(
        topLeft: Point2D(0.1, 0.1),
        topRight: Point2D(0.9, 0.9), // crossed
        bottomRight: Point2D(0.9, 0.1), // crossed
        bottomLeft: Point2D(0.1, 0.9),
      );

      await tester.pumpWidget(
        buildTestWidget(initialPolygon: bowtiePoly),
      );
      await tester.pumpAndSettle();

      // Warning banner must be visible
      expect(find.textContaining('Invalid crop boundary'), findsOneWidget);

      // Apply crop button must be disabled
      final applyButtonFinder = find.widgetWithText(ElevatedButton, 'Apply crop');
      final applyButton = tester.widget<ElevatedButton>(applyButtonFinder);
      expect(applyButton.onPressed, isNull);
    });
  });
}
