import 'package:flutter_test/flutter_test.dart';
import 'package:docerena/core/geometry/crop_polygon.dart';
import 'package:docerena/domain/entities/page_entity.dart';

void main() {
  group('PageEntity Tests', () {
    test('rotate90Clockwise cycles through 0 -> 90 -> 180 -> 270 -> 0', () {
      final initial = PageEntity(
        id: 'p1',
        documentId: 'd1',
        position: 0,
        originalFileKey: 'documents/d1/pages/p1_orig.jpg',
        cropPolygon: CropPolygon.fullFrame(),
        rotationDegrees: 0,
        pixelWidth: 1080,
        pixelHeight: 1920,
        createdAt: DateTime.now(),
      );

      final rot90 = initial.rotate90Clockwise();
      expect(rot90.rotationDegrees, equals(90));

      final rot180 = rot90.rotate90Clockwise();
      expect(rot180.rotationDegrees, equals(180));

      final rot270 = rot180.rotate90Clockwise();
      expect(rot270.rotationDegrees, equals(270));

      final rot360 = rot270.rotate90Clockwise();
      expect(rot360.rotationDegrees, equals(0));
    });

    test('Serialization toMap and fromMap preserves all attributes', () {
      final now = DateTime.now();
      final page = PageEntity(
        id: 'page-uuid-1234',
        documentId: 'doc-uuid-5678',
        position: 2,
        originalFileKey: 'documents/doc-uuid-5678/pages/page-uuid-1234_orig.jpg',
        cropPolygon: const CropPolygon(
          topLeft: Point2D(0.05, 0.05),
          topRight: Point2D(0.95, 0.05),
          bottomRight: Point2D(0.95, 0.95),
          bottomLeft: Point2D(0.05, 0.95),
        ),
        rotationDegrees: 180,
        filter: PageFilter.blackAndWhite,
        brightness: 0.25,
        contrast: 1.5,
        processedCacheKey: 'documents/doc-uuid-5678/pages/page-uuid-1234_preview.jpg',
        pixelWidth: 2400,
        pixelHeight: 3200,
        createdAt: now,
      );

      final map = page.toMap();
      final restored = PageEntity.fromMap(map);

      expect(restored.id, equals(page.id));
      expect(restored.documentId, equals(page.documentId));
      expect(restored.position, equals(page.position));
      expect(restored.originalFileKey, equals(page.originalFileKey));
      expect(restored.cropPolygon, equals(page.cropPolygon));
      expect(restored.rotationDegrees, equals(page.rotationDegrees));
      expect(restored.filter, equals(PageFilter.blackAndWhite));
      expect(restored.brightness, closeTo(0.25, 0.001));
      expect(restored.contrast, closeTo(1.5, 0.001));
      expect(restored.processedCacheKey, equals(page.processedCacheKey));
      expect(restored.pixelWidth, equals(page.pixelWidth));
      expect(restored.pixelHeight, equals(page.pixelHeight));
      expect(restored.createdAt.millisecondsSinceEpoch, equals(now.millisecondsSinceEpoch));
    });
  });
}
