import 'package:flutter_test/flutter_test.dart';
import 'package:docerena/core/geometry/crop_polygon.dart';
import 'package:docerena/domain/entities/page_entity.dart';

/// Pure page reordering and deletion helper functions reflecting S06 Organizer logic
List<PageEntity> reorderPages(List<PageEntity> pages, int oldIndex, int newIndex) {
  if (oldIndex < 0 || oldIndex >= pages.length || newIndex < 0 || newIndex >= pages.length) {
    return List<PageEntity>.from(pages);
  }
  final list = List<PageEntity>.from(pages);
  final item = list.removeAt(oldIndex);
  list.insert(newIndex, item);
  return List.generate(list.length, (i) => list[i].copyWith(position: i));
}

List<PageEntity> movePageUp(List<PageEntity> pages, int index) {
  if (index <= 0 || index >= pages.length) {
    return List<PageEntity>.from(pages);
  }
  return reorderPages(pages, index, index - 1);
}

List<PageEntity> movePageDown(List<PageEntity> pages, int index) {
  if (index < 0 || index >= pages.length - 1) {
    return List<PageEntity>.from(pages);
  }
  return reorderPages(pages, index, index + 1);
}

List<PageEntity> deletePageAndReindex(List<PageEntity> pages, int index) {
  if (index < 0 || index >= pages.length) {
    return List<PageEntity>.from(pages);
  }
  final list = List<PageEntity>.from(pages);
  list.removeAt(index);
  return List.generate(list.length, (i) => list[i].copyWith(position: i));
}

PageEntity createTestPage({
  required String id,
  required String docId,
  required int position,
  int rotation = 0,
  PageFilter filter = PageFilter.original,
  CropPolygon? crop,
}) {
  return PageEntity(
    id: id,
    documentId: docId,
    position: position,
    originalFileKey: 'documents/$docId/pages/${id}_orig.jpg',
    cropPolygon: crop ?? CropPolygon.fullFrame(),
    rotationDegrees: rotation,
    filter: filter,
    brightness: 0.0,
    contrast: 1.0,
    pixelWidth: 1920,
    pixelHeight: 1080,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000 + position * 1000),
  );
}

void main() {
  const docId = 'doc-test-123';

  group('Page Reordering - Tier 1: Primary Happy Paths', () {
    test('Tier 1: should forward reorder page from index 0 to index 2 and re-index', () {
      final p0 = createTestPage(id: 'p0', docId: docId, position: 0);
      final p1 = createTestPage(id: 'p1', docId: docId, position: 1);
      final p2 = createTestPage(id: 'p2', docId: docId, position: 2);

      final reordered = reorderPages([p0, p1, p2], 0, 2);

      expect(reordered.length, equals(3));
      expect(reordered[0].id, equals('p1'));
      expect(reordered[0].position, equals(0));

      expect(reordered[1].id, equals('p2'));
      expect(reordered[1].position, equals(1));

      expect(reordered[2].id, equals('p0'));
      expect(reordered[2].position, equals(2));
    });

    test('Tier 1: should backward reorder page from index 2 to index 0 and re-index', () {
      final p0 = createTestPage(id: 'p0', docId: docId, position: 0);
      final p1 = createTestPage(id: 'p1', docId: docId, position: 1);
      final p2 = createTestPage(id: 'p2', docId: docId, position: 2);

      final reordered = reorderPages([p0, p1, p2], 2, 0);

      expect(reordered[0].id, equals('p2'));
      expect(reordered[0].position, equals(0));

      expect(reordered[1].id, equals('p0'));
      expect(reordered[1].position, equals(1));

      expect(reordered[2].id, equals('p1'));
      expect(reordered[2].position, equals(2));
    });

    test('Tier 1: accessible moveUp should swap with predecessor', () {
      final p0 = createTestPage(id: 'p0', docId: docId, position: 0);
      final p1 = createTestPage(id: 'p1', docId: docId, position: 1);
      final p2 = createTestPage(id: 'p2', docId: docId, position: 2);

      final result = movePageUp([p0, p1, p2], 1);

      expect(result[0].id, equals('p1'));
      expect(result[0].position, equals(0));
      expect(result[1].id, equals('p0'));
      expect(result[1].position, equals(1));
      expect(result[2].id, equals('p2'));
      expect(result[2].position, equals(2));
    });

    test('Tier 1: accessible moveDown should swap with successor', () {
      final p0 = createTestPage(id: 'p0', docId: docId, position: 0);
      final p1 = createTestPage(id: 'p1', docId: docId, position: 1);
      final p2 = createTestPage(id: 'p2', docId: docId, position: 2);

      final result = movePageDown([p0, p1, p2], 1);

      expect(result[0].id, equals('p0'));
      expect(result[0].position, equals(0));
      expect(result[1].id, equals('p2'));
      expect(result[1].position, equals(1));
      expect(result[2].id, equals('p1'));
      expect(result[2].position, equals(2));
    });

    test('Tier 1: delete middle page reindexes remainder strictly from 0 to N-1', () {
      final p0 = createTestPage(id: 'p0', docId: docId, position: 0);
      final p1 = createTestPage(id: 'p1', docId: docId, position: 1);
      final p2 = createTestPage(id: 'p2', docId: docId, position: 2);

      final result = deletePageAndReindex([p0, p1, p2], 1);

      expect(result.length, equals(2));
      expect(result[0].id, equals('p0'));
      expect(result[0].position, equals(0));

      expect(result[1].id, equals('p2'));
      expect(result[1].position, equals(1));
    });
  });

  group('Page Reordering - Tier 2: Boundary & Corner Cases', () {
    test('Tier 2: moveUp on the first page (index 0) is a safe no-op', () {
      final p0 = createTestPage(id: 'p0', docId: docId, position: 0);
      final p1 = createTestPage(id: 'p1', docId: docId, position: 1);

      final result = movePageUp([p0, p1], 0);

      expect(result[0].id, equals('p0'));
      expect(result[0].position, equals(0));
      expect(result[1].id, equals('p1'));
      expect(result[1].position, equals(1));
    });

    test('Tier 2: moveDown on the last page is a safe no-op', () {
      final p0 = createTestPage(id: 'p0', docId: docId, position: 0);
      final p1 = createTestPage(id: 'p1', docId: docId, position: 1);

      final result = movePageDown([p0, p1], 1);

      expect(result[0].id, equals('p0'));
      expect(result[0].position, equals(0));
      expect(result[1].id, equals('p1'));
      expect(result[1].position, equals(1));
    });

    test('Tier 2: out-of-range index reordering returns untouched list without exception', () {
      final p0 = createTestPage(id: 'p0', docId: docId, position: 0);
      final p1 = createTestPage(id: 'p1', docId: docId, position: 1);

      final negResult = reorderPages([p0, p1], -1, 1);
      expect(negResult.length, equals(2));
      expect(negResult[0].id, equals('p0'));

      final excessiveResult = reorderPages([p0, p1], 0, 99);
      expect(excessiveResult.length, equals(2));
      expect(excessiveResult[0].id, equals('p0'));
    });

    test('Tier 2: deleting the sole remaining page results in an empty list', () {
      final p0 = createTestPage(id: 'p0', docId: docId, position: 0);

      final result = deletePageAndReindex([p0], 0);

      expect(result, isEmpty);
    });

    test('Tier 2: deleting the first page (index 0) cleanly shifts all pages forward', () {
      final p0 = createTestPage(id: 'p0', docId: docId, position: 0);
      final p1 = createTestPage(id: 'p1', docId: docId, position: 1);
      final p2 = createTestPage(id: 'p2', docId: docId, position: 2);

      final result = deletePageAndReindex([p0, p1, p2], 0);

      expect(result.length, equals(2));
      expect(result[0].id, equals('p1'));
      expect(result[0].position, equals(0));
      expect(result[1].id, equals('p2'));
      expect(result[1].position, equals(1));
    });

    test('Tier 2: deleting with invalid negative or excessive index is safe no-op', () {
      final p0 = createTestPage(id: 'p0', docId: docId, position: 0);
      final p1 = createTestPage(id: 'p1', docId: docId, position: 1);

      final negDel = deletePageAndReindex([p0, p1], -1);
      expect(negDel.length, equals(2));

      final bigDel = deletePageAndReindex([p0, p1], 5);
      expect(bigDel.length, equals(2));
    });
  });

  group('Page Reordering - Tier 3: Cross-Feature Combinations', () {
    test('Tier 3: reorder then delete preserves non-destructive metadata on surviving pages', () {
      const customCrop = CropPolygon(
        topLeft: Point2D(0.1, 0.1),
        topRight: Point2D(0.9, 0.1),
        bottomRight: Point2D(0.9, 0.9),
        bottomLeft: Point2D(0.1, 0.9),
      );

      final p0 = createTestPage(id: 'p0', docId: docId, position: 0, rotation: 90, filter: PageFilter.grayscale);
      final p1 = createTestPage(id: 'p1', docId: docId, position: 1, crop: customCrop);
      final p2 = createTestPage(id: 'p2', docId: docId, position: 2, rotation: 180, filter: PageFilter.blackAndWhite);
      final p3 = createTestPage(id: 'p3', docId: docId, position: 3);

      // Step 1: Reorder index 3 to 0 -> [p3, p0, p1, p2]
      final reordered = reorderPages([p0, p1, p2, p3], 3, 0);
      expect(reordered[0].id, equals('p3'));
      expect(reordered[1].id, equals('p0'));
      expect(reordered[2].id, equals('p1'));
      expect(reordered[3].id, equals('p2'));

      // Step 2: Delete page at current index 1 (which is p0)
      final afterDelete = deletePageAndReindex(reordered, 1);
      expect(afterDelete.length, equals(3));

      // p3 is at 0
      expect(afterDelete[0].id, equals('p3'));
      expect(afterDelete[0].position, equals(0));

      // p1 is now at 1, crop is fully preserved
      expect(afterDelete[1].id, equals('p1'));
      expect(afterDelete[1].position, equals(1));
      expect(afterDelete[1].cropPolygon, equals(customCrop));

      // p2 is now at 2, rotation 180 and filter blackAndWhite preserved
      expect(afterDelete[2].id, equals('p2'));
      expect(afterDelete[2].position, equals(2));
      expect(afterDelete[2].rotationDegrees, equals(180));
      expect(afterDelete[2].filter, equals(PageFilter.blackAndWhite));
    });

    test('Tier 3: rotation cycle on reordered page rotates correctly', () {
      final p0 = createTestPage(id: 'p0', docId: docId, position: 0, rotation: 0);
      final p1 = createTestPage(id: 'p1', docId: docId, position: 1, rotation: 270);

      // Rotate p0 clockwise: 0 -> 90
      final rotatedP0 = p0.rotate90Clockwise();
      expect(rotatedP0.rotationDegrees, equals(90));

      // Rotate p1 clockwise: 270 -> 0
      final rotatedP1 = p1.rotate90Clockwise();
      expect(rotatedP1.rotationDegrees, equals(0));

      // Reorder rotated pages
      final reordered = reorderPages([rotatedP0, rotatedP1], 1, 0);
      expect(reordered[0].id, equals('p1'));
      expect(reordered[0].rotationDegrees, equals(0));
      expect(reordered[1].id, equals('p0'));
      expect(reordered[1].rotationDegrees, equals(90));
    });

    test('Tier 3: retake page flow preserves position while updating original file key and resetting crop', () {
      const initialCrop = CropPolygon(
        topLeft: Point2D(0.2, 0.2),
        topRight: Point2D(0.8, 0.2),
        bottomRight: Point2D(0.8, 0.8),
        bottomLeft: Point2D(0.2, 0.8),
      );

      final p0 = createTestPage(id: 'p0', docId: docId, position: 0);
      final p1 = createTestPage(id: 'p1', docId: docId, position: 1, crop: initialCrop, rotation: 90);
      final p2 = createTestPage(id: 'p2', docId: docId, position: 2);

      // Retake p1: replace with new image key, reset crop to fullFrame, reset rotation to 0
      final retakenP1 = p1.copyWith(
        originalFileKey: 'documents/$docId/pages/p1_retaken_orig.jpg',
        cropPolygon: CropPolygon.fullFrame(),
        rotationDegrees: 0,
      );

      final list = [p0, retakenP1, p2];

      expect(list[1].position, equals(1));
      expect(list[1].originalFileKey, contains('p1_retaken_orig.jpg'));
      expect(list[1].cropPolygon, equals(CropPolygon.fullFrame()));
      expect(list[1].rotationDegrees, equals(0));
    });
  });
}
