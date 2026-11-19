import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:docerena/domain/entities/page_entity.dart';
import 'package:docerena/presentation/screens/s05_enhance/enhance_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List testImageBytes;

  setUp(() {
    final sampleImg = img.Image(width: 150, height: 120);
    img.fill(sampleImg, color: img.ColorRgba8(230, 230, 230, 255));
    testImageBytes = Uint8List.fromList(img.encodeJpg(sampleImg, quality: 90));
  });

  Widget buildTestWidget({
    PageFilter initialFilter = PageFilter.original,
    double initialBrightness = 0.0,
    double initialContrast = 1.0,
    int pageIndex = 0,
    int totalPages = 3,
    ValueChanged<EnhanceResult>? onApply,
    VoidCallback? onCancel,
  }) {
    return MaterialApp(
      home: EnhanceScreen(
        imageBytes: testImageBytes,
        initialFilter: initialFilter,
        initialBrightness: initialBrightness,
        initialContrast: initialContrast,
        pageIndex: pageIndex,
        totalPages: totalPages,
        onApply: onApply,
        onCancel: onCancel,
      ),
    );
  }

  group('EnhanceScreen Widget Tests', () {
    testWidgets('renders top bar, filter preset cards, brightness slider, and action buttons', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Top bar title
      expect(find.text('Enhance scan'), findsOneWidget);

      // Comparison control
      expect(find.text('Hold to see original'), findsOneWidget);

      // 4 Filter preset cards
      expect(find.text('Original'), findsOneWidget);
      expect(find.text('Color'), findsOneWidget);
      expect(find.text('Gray'), findsOneWidget);
      expect(find.text('B&W'), findsOneWidget);

      // Brightness slider and readout
      expect(find.text('Brightness'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);

      // Apply to all toggle
      expect(find.text('Apply to all'), findsOneWidget);

      // Action buttons: Reset & Apply
      expect(find.text('Reset'), findsOneWidget);
      expect(find.text('Apply'), findsOneWidget);
    });

    testWidgets('selecting Gray filter preset updates filter and applies correctly', (tester) async {
      EnhanceResult? appliedResult;

      await tester.pumpWidget(
        buildTestWidget(
          onApply: (res) {
            appliedResult = res;
          },
        ),
      );
      await tester.pumpAndSettle();

      // Tap "Gray"
      await tester.tap(find.text('Gray'));
      await tester.pumpAndSettle();

      // Tap "Apply"
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(appliedResult, isNotNull);
      expect(appliedResult!.filter, equals(PageFilter.grayscale));
      expect(appliedResult!.applyToAllPages, isFalse);
    });

    testWidgets('reset button restores neutral brightness and Original filter', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Select B&W
      await tester.tap(find.text('B&W'));
      await tester.pumpAndSettle();

      // Tap Reset
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();

      // Tap Apply to verify filter is restored to original
      EnhanceResult? appliedResult;
      await tester.pumpWidget(
        buildTestWidget(
          onApply: (res) {
            appliedResult = res;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(appliedResult, isNotNull);
      expect(appliedResult!.filter, equals(PageFilter.original));
      expect(appliedResult!.brightness, equals(0.0));
    });

    testWidgets('apply to all switch toggles batch mode', (tester) async {
      EnhanceResult? appliedResult;

      await tester.pumpWidget(
        buildTestWidget(
          onApply: (res) {
            appliedResult = res;
          },
        ),
      );
      await tester.pumpAndSettle();

      // Tap Switch
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      // Tap Apply
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(appliedResult, isNotNull);
      expect(appliedResult!.applyToAllPages, isTrue);
    });

    testWidgets('holding comparison button toggles SHOWING ORIGINAL indicator', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final compareFinder = find.text('Hold to see original');
      expect(compareFinder, findsOneWidget);

      // Press down
      final gesture = await tester.startGesture(tester.getCenter(compareFinder));
      await tester.pump();

      expect(find.text('SHOWING ORIGINAL'), findsOneWidget);

      // Release
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Hold to see original'), findsOneWidget);
    });
  });
}
