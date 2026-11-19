import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:docerena/core/geometry/crop_polygon.dart';

void main() {
  group('Point2D Geometry Tests', () {
    test('Tier 1: should correctly instantiate coordinates and check normalization', () {
      const p1 = Point2D(0.25, 0.75);
      expect(p1.x, equals(0.25));
      expect(p1.y, equals(0.75));
      expect(p1.isNormalized, isTrue);

      const pOrigin = Point2D(0.0, 0.0);
      expect(pOrigin.isNormalized, isTrue);

      const pMax = Point2D(1.0, 1.0);
      expect(pMax.isNormalized, isTrue);
    });

    test('Tier 2: should detect out-of-bounds coordinates in normalization check', () {
      const pNegativeX = Point2D(-0.1, 0.5);
      expect(pNegativeX.isNormalized, isFalse);

      const pNegativeY = Point2D(0.5, -0.05);
      expect(pNegativeY.isNormalized, isFalse);

      const pLargeX = Point2D(1.1, 0.5);
      expect(pLargeX.isNormalized, isFalse);

      const pLargeY = Point2D(0.5, 1.05);
      expect(pLargeY.isNormalized, isFalse);
    });

    test('Tier 2: should clamp out-of-bounds coordinates strictly to [0.0, 1.0]', () {
      const pNegative = Point2D(-0.5, -0.2);
      final clampedNeg = pNegative.clampNormalized();
      expect(clampedNeg.x, equals(0.0));
      expect(clampedNeg.y, equals(0.0));
      expect(clampedNeg.isNormalized, isTrue);

      const pExcess = Point2D(1.8, 2.5);
      final clampedExcess = pExcess.clampNormalized();
      expect(clampedExcess.x, equals(1.0));
      expect(clampedExcess.y, equals(1.0));
      expect(clampedExcess.isNormalized, isTrue);
    });

    test('Tier 1: vector operations - subtraction, addition, and cross product', () {
      const a = Point2D(1.0, 0.0);
      const b = Point2D(0.0, 1.0);

      final diff = b - a;
      expect(diff.x, equals(-1.0));
      expect(diff.y, equals(1.0));

      final sum = a + b;
      expect(sum.x, equals(1.0));
      expect(sum.y, equals(1.0));

      // cross product: a.x * b.y - a.y * b.x = 1*1 - 0*0 = 1.0
      expect(a.crossProduct(b), equals(1.0));
      // reverse cross product: b.x * a.y - b.y * a.x = 0*0 - 1*1 = -1.0
      expect(b.crossProduct(a), equals(-1.0));
    });

    test('Tier 1: serialization to and from List', () {
      const p = Point2D(0.42, 0.88);
      final list = p.toList();
      expect(list, equals([0.42, 0.88]));

      final reconstructed = Point2D.fromList([0.42, 0.88]);
      expect(reconstructed, equals(p));
    });

    test('Tier 2: fromList with insufficient elements throws ArgumentError', () {
      expect(() => Point2D.fromList([0.5]), throwsArgumentError);
      expect(() => Point2D.fromList([]), throwsArgumentError);
    });
  });

  group('CropPolygon Geometry Tests', () {
    test('Tier 1: default fullFrame covers normalized unit square with valid convexity', () {
      final quad = CropPolygon.fullFrame();

      expect(quad.topLeft, equals(const Point2D(0.0, 0.0)));
      expect(quad.topRight, equals(const Point2D(1.0, 0.0)));
      expect(quad.bottomRight, equals(const Point2D(1.0, 1.0)));
      expect(quad.bottomLeft, equals(const Point2D(0.0, 1.0)));

      expect(quad.arePointsNormalized, isTrue);
      expect(quad.isClockwise, isTrue);
      expect(quad.signedArea, closeTo(1.0, 1e-6));
      expect(quad.area, closeTo(1.0, 1e-6));
      expect(quad.isConvex, isTrue);
      expect(quad.isValid, isTrue);
    });

    test('Tier 1: valid custom trapezoid crop within image bounds', () {
      const quad = CropPolygon(
        topLeft: Point2D(0.1, 0.1),
        topRight: Point2D(0.9, 0.15),
        bottomRight: Point2D(0.85, 0.95),
        bottomLeft: Point2D(0.15, 0.9),
      );

      expect(quad.arePointsNormalized, isTrue);
      expect(quad.isClockwise, isTrue);
      expect(quad.area, greaterThan(0.5));
      expect(quad.isConvex, isTrue);
      expect(quad.isValid, isTrue);
    });

    test('Tier 2: bowtie / self-intersecting quadrilateral is rejected', () {
      // Swapping top-right and bottom-right crosses the right edge over the bottom edge, forming an hourglass / bowtie
      const bowtie = CropPolygon(
        topLeft: Point2D(0.0, 0.0),
        topRight: Point2D(1.0, 1.0), // crossed
        bottomRight: Point2D(1.0, 0.0), // crossed
        bottomLeft: Point2D(0.0, 1.0),
      );

      expect(bowtie.isConvex, isFalse);
      expect(bowtie.isValid, isFalse);
      expect(bowtie.sanitizeOrFallback(), equals(CropPolygon.fullFrame()));
    });

    test('Tier 2: counter-clockwise vertex winding is marked invalid', () {
      // Reversing the vertex order to TL -> BL -> BR -> TR (counter-clockwise in Y-down coordinates)
      const ccw = CropPolygon(
        topLeft: Point2D(0.0, 0.0),
        topRight: Point2D(0.0, 1.0),
        bottomRight: Point2D(1.0, 1.0),
        bottomLeft: Point2D(1.0, 0.0),
      );

      expect(ccw.isClockwise, isFalse);
      expect(ccw.signedArea, lessThan(0.0));
      expect(ccw.isValid, isFalse);
      expect(ccw.sanitizeOrFallback(), equals(CropPolygon.fullFrame()));
    });

    test('Tier 2: collinear points forming 0-area line are rejected', () {
      // 4 points collapsed onto the horizontal line y = 0.5
      const collinear = CropPolygon(
        topLeft: Point2D(0.1, 0.5),
        topRight: Point2D(0.4, 0.5),
        bottomRight: Point2D(0.7, 0.5),
        bottomLeft: Point2D(0.2, 0.5),
      );

      expect(collinear.area, closeTo(0.0, 1e-6));
      expect(collinear.isValid, isFalse);
      expect(collinear.sanitizeOrFallback(), equals(CropPolygon.fullFrame()));
    });

    test('Tier 2: micro-quadrilateral below threshold area (<0.001) is rejected', () {
      const tiny = CropPolygon(
        topLeft: Point2D(0.5, 0.5),
        topRight: Point2D(0.51, 0.5),
        bottomRight: Point2D(0.51, 0.51),
        bottomLeft: Point2D(0.5, 0.51),
      );

      // Area is 0.01 * 0.01 = 0.0001 < 0.001
      expect(tiny.area, lessThan(0.001));
      expect(tiny.isValid, isFalse);
      expect(tiny.sanitizeOrFallback(), equals(CropPolygon.fullFrame()));
    });

    test('Tier 2: un-normalized points trigger full-frame fallback in sanitizeOrFallback', () {
      const outOfBounds = CropPolygon(
        topLeft: Point2D(-0.5, 0.0),
        topRight: Point2D(1.5, 0.0),
        bottomRight: Point2D(1.0, 1.0),
        bottomLeft: Point2D(0.0, 1.0),
      );

      expect(outOfBounds.arePointsNormalized, isFalse);
      expect(outOfBounds.isValid, isFalse);
      expect(outOfBounds.sanitizeOrFallback(), equals(CropPolygon.fullFrame()));
    });

    test('Tier 1: JSON serialization and deserialization roundtrip', () {
      const original = CropPolygon(
        topLeft: Point2D(0.12, 0.15),
        topRight: Point2D(0.85, 0.18),
        bottomRight: Point2D(0.88, 0.92),
        bottomLeft: Point2D(0.14, 0.89),
      );

      final jsonStr = original.toJsonString();
      final decodedList = jsonDecode(jsonStr) as List<dynamic>;
      expect(decodedList.length, equals(4));

      final restored = CropPolygon.fromJsonString(jsonStr);
      expect(restored.topLeft.x, closeTo(0.12, 1e-5));
      expect(restored.topLeft.y, closeTo(0.15, 1e-5));
      expect(restored.topRight.x, closeTo(0.85, 1e-5));
      expect(restored.topRight.y, closeTo(0.18, 1e-5));
      expect(restored.bottomRight.x, closeTo(0.88, 1e-5));
      expect(restored.bottomRight.y, closeTo(0.92, 1e-5));
      expect(restored.bottomLeft.x, closeTo(0.14, 1e-5));
      expect(restored.bottomLeft.y, closeTo(0.89, 1e-5));
      expect(restored, equals(original));
    });

    test('Tier 2: corrupted JSON string safely falls back to full frame', () {
      final invalidJson = CropPolygon.fromJsonString('corrupted {not a json');
      expect(invalidJson, equals(CropPolygon.fullFrame()));

      final emptyListJson = CropPolygon.fromJsonString('[]');
      expect(emptyListJson, equals(CropPolygon.fullFrame()));

      final partialListJson = CropPolygon.fromJsonString('[[0,0], [1,0]]');
      expect(partialListJson, equals(CropPolygon.fullFrame()));
    });
  });
}
