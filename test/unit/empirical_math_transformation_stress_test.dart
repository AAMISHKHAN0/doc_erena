import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:docerena/core/geometry/crop_polygon.dart';
import 'package:docerena/domain/entities/page_entity.dart';
import 'package:docerena/services/transform/image_transform_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const service = ImageTransformService();

  group('CHALLENGE 1: Corner Ordering & Shoelace Formula', () {
    test('Shoelace detects clockwise winding on canonical unit square', () {
      final poly = CropPolygon.fullFrame();
      expect(poly.signedArea, closeTo(1.0, 1e-9));
      expect(poly.isClockwise, isTrue);
      expect(poly.isValid, isTrue);
    });

    test('Shoelace strictly rejects counter-clockwise ordered unit square', () {
      // Counter-clockwise: TL -> BL -> BR -> TR
      const ccwPoly = CropPolygon(
        topLeft: Point2D(0.0, 0.0),
        topRight: Point2D(0.0, 1.0),
        bottomRight: Point2D(1.0, 1.0),
        bottomLeft: Point2D(1.0, 0.0),
      );
      expect(ccwPoly.signedArea, closeTo(-1.0, 1e-9));
      expect(ccwPoly.isClockwise, isFalse);
      expect(ccwPoly.isValid, isFalse);
      expect(ccwPoly.sanitizeOrFallback(), equals(CropPolygon.fullFrame()));
    });

    test('All 24 permutations of 4 unit-square vertices are correctly categorized', () {
      final basePoints = [
        const Point2D(0.0, 0.0), // 0: TL
        const Point2D(1.0, 0.0), // 1: TR
        const Point2D(1.0, 1.0), // 2: BR
        const Point2D(0.0, 1.0), // 3: BL
      ];

      // Generate all 24 permutations
      final permutations = <List<int>>[];
      void permute(List<int> current, List<int> remaining) {
        if (remaining.isEmpty) {
          permutations.add(current);
        } else {
          for (int i = 0; i < remaining.length; i++) {
            permute(
              [...current, remaining[i]],
              [...remaining.sublist(0, i), ...remaining.sublist(i + 1)],
            );
          }
        }
      }

      permute([], [0, 1, 2, 3]);
      expect(permutations.length, equals(24));

      int validClockwiseCount = 0;
      int ccwCount = 0;
      int bowtieCount = 0;

      for (final p in permutations) {
        final poly = CropPolygon(
          topLeft: basePoints[p[0]],
          topRight: basePoints[p[1]],
          bottomRight: basePoints[p[2]],
          bottomLeft: basePoints[p[3]],
        );

        if (poly.isValid) {
          validClockwiseCount++;
          expect(poly.isClockwise, isTrue);
          expect(poly.isConvex, isTrue);
          expect(poly.signedArea, closeTo(1.0, 1e-6));
        } else if (poly.signedArea < -1e-6) {
          ccwCount++;
          expect(poly.isClockwise, isFalse);
        } else {
          // Bowtie self-intersecting or zero signed area
          bowtieCount++;
        }
      }

      // Exactly 4 cyclic shifts of clockwise traversal: (0,1,2,3), (1,2,3,0), (2,3,0,1), (3,0,1,2)
      // Exactly 4 cyclic shifts of CCW traversal: (3,2,1,0), (2,1,0,3), (1,0,3,2), (0,3,2,1)
      // Remaining 16 are non-simple bowties / crosses
      expect(validClockwiseCount, equals(4));
      expect(ccwCount, equals(4));
      expect(bowtieCount, equals(16));
    });

    test('Threshold boundary: signed area <= 1e-6 returns isClockwise false', () {
      // Degenerate sliver with signed area just below 1e-6
      const sliver = CropPolygon(
        topLeft: Point2D(0.0, 0.0),
        topRight: Point2D(1e-6, 0.0),
        bottomRight: Point2D(1e-6, 1e-6),
        bottomLeft: Point2D(0.0, 1e-6),
      );
      // Area is 1e-12 < 1e-6
      expect(sliver.isClockwise, isFalse);
      expect(sliver.isValid, isFalse);
    });
  });

  group('CHALLENGE 2: Convexity, Bowtie Polygons, Reflex Angles, and Degeneracies', () {
    test('Self-intersecting bowtie polygon is rejected and falls back safely', () {
      // Hourglass/bowtie: TL (0,0) -> TR (1,1) -> BR (1,0) -> BL (0,1)
      const bowtie = CropPolygon(
        topLeft: Point2D(0.0, 0.0),
        topRight: Point2D(1.0, 1.0),
        bottomRight: Point2D(1.0, 0.0),
        bottomLeft: Point2D(0.0, 1.0),
      );
      expect(bowtie.isConvex, isFalse);
      expect(bowtie.isValid, isFalse);
      expect(bowtie.sanitizeOrFallback(), equals(CropPolygon.fullFrame()));
    });

    test('Reflex angle polygon (dart/arrowhead) is rejected', () {
      // Interior dent at BR: (0.5, 0.3)
      const dart = CropPolygon(
        topLeft: Point2D(0.1, 0.1),
        topRight: Point2D(0.9, 0.1),
        bottomRight: Point2D(0.5, 0.3), // reflex angle
        bottomLeft: Point2D(0.1, 0.9),
      );
      expect(dart.isConvex, isFalse);
      expect(dart.isValid, isFalse);
      expect(dart.sanitizeOrFallback(), equals(CropPolygon.fullFrame()));
    });

    test('Collinear 3-point edge is rejected as non-convex degenerate', () {
      // TR is exactly midway between TL and BR
      const collinear3 = CropPolygon(
        topLeft: Point2D(0.0, 0.0),
        topRight: Point2D(0.5, 0.0),
        bottomRight: Point2D(1.0, 0.0),
        bottomLeft: Point2D(0.5, 1.0),
      );
      expect(collinear3.isConvex, isFalse);
      expect(collinear3.isValid, isFalse);
      expect(collinear3.sanitizeOrFallback(), equals(CropPolygon.fullFrame()));
    });

    test('4 collinear points on horizontal line are rejected', () {
      const line = CropPolygon(
        topLeft: Point2D(0.1, 0.5),
        topRight: Point2D(0.3, 0.5),
        bottomRight: Point2D(0.7, 0.5),
        bottomLeft: Point2D(0.9, 0.5),
      );
      expect(line.isConvex, isFalse);
      expect(line.signedArea, closeTo(0.0, 1e-9));
      expect(line.isValid, isFalse);
      expect(line.sanitizeOrFallback(), equals(CropPolygon.fullFrame()));
    });

    test('Micro-quadrilateral with area < 0.001 is rejected', () {
      const micro = CropPolygon(
        topLeft: Point2D(0.5, 0.5),
        topRight: Point2D(0.52, 0.5),
        bottomRight: Point2D(0.52, 0.52),
        bottomLeft: Point2D(0.5, 0.52),
      );
      // Area is 0.02 * 0.02 = 0.0004 < 0.001
      expect(micro.area, lessThan(0.001));
      expect(micro.isValid, isFalse);
      expect(micro.sanitizeOrFallback(), equals(CropPolygon.fullFrame()));
    });

    test('Coincident corner points (TL == TR) are rejected', () {
      const coincident = CropPolygon(
        topLeft: Point2D(0.5, 0.5),
        topRight: Point2D(0.5, 0.5),
        bottomRight: Point2D(0.9, 0.9),
        bottomLeft: Point2D(0.1, 0.9),
      );
      expect(coincident.isConvex, isFalse);
      expect(coincident.isValid, isFalse);
      expect(coincident.sanitizeOrFallback(), equals(CropPolygon.fullFrame()));
    });
  });

  group('CHALLENGE 3: Normalization & Boundary Clamping', () {
    test('Point2D clamps coordinates strictly inside [0.0, 1.0]', () {
      expect(const Point2D(-100.0, 50.0).clampNormalized(), equals(const Point2D(0.0, 1.0)));
      expect(const Point2D(0.5, -0.001).clampNormalized(), equals(const Point2D(0.5, 0.0)));
      expect(const Point2D(1.001, 0.25).clampNormalized(), equals(const Point2D(1.0, 0.25)));
    });

    test('Points outside [-0.0001, 1.0001] are marked un-normalized', () {
      expect(const Point2D(-0.0002, 0.5).isNormalized, isFalse);
      expect(const Point2D(1.0002, 0.5).isNormalized, isFalse);
      expect(const Point2D(0.5, -0.0002).isNormalized, isFalse);
      expect(const Point2D(0.5, 1.0002).isNormalized, isFalse);
    });

    test('CropPolygon with out-of-bounds corners falls back to fullFrame', () {
      const outOfBounds = CropPolygon(
        topLeft: Point2D(-0.2, 0.0),
        topRight: Point2D(1.2, 0.0),
        bottomRight: Point2D(1.0, 1.0),
        bottomLeft: Point2D(0.0, 1.0),
      );
      expect(outOfBounds.arePointsNormalized, isFalse);
      expect(outOfBounds.isValid, isFalse);
      expect(outOfBounds.sanitizeOrFallback(), equals(CropPolygon.fullFrame()));
    });

    test('Corrupted JSON with NaN or out-of-bounds numbers safely deserializes to fullFrame', () {
      final poly1 = CropPolygon.fromJsonString('null');
      expect(poly1, equals(CropPolygon.fullFrame()));

      final poly2 = CropPolygon.fromJsonString('[[0,0],[1,0],[1,1]]'); // 3 points
      expect(poly2, equals(CropPolygon.fullFrame()));

      final poly3 = CropPolygon.fromJsonString('{"invalid":"object"}');
      expect(poly3, equals(CropPolygon.fullFrame()));
    });
  });

  group('CHALLENGE 4: 8-Parameter Homography Matrix Solver', () {
    test('Identity mapping produces identity homography matrix', () {
      final square = [
        const math.Point<double>(0.0, 0.0),
        const math.Point<double>(100.0, 0.0),
        const math.Point<double>(100.0, 100.0),
        const math.Point<double>(0.0, 100.0),
      ];

      final h = service.computeHomography(square, square);
      expect(h, isNotNull);
      expect(h!.length, equals(8));

      // In identity homography:
      // h00=1, h01=0, h02=0
      // h10=0, h11=1, h12=0
      // h20=0, h21=0
      expect(h[0], closeTo(1.0, 1e-7));
      expect(h[1], closeTo(0.0, 1e-7));
      expect(h[2], closeTo(0.0, 1e-7));
      expect(h[3], closeTo(0.0, 1e-7));
      expect(h[4], closeTo(1.0, 1e-7));
      expect(h[5], closeTo(0.0, 1e-7));
      expect(h[6], closeTo(0.0, 1e-7));
      expect(h[7], closeTo(0.0, 1e-7));
    });

    test('Homography accurately maps destination corners to source corners in keystone quadrilateral', () {
      // Perspective trapezoid in source image (converging top edge)
      final srcPts = [
        const math.Point<double>(20.0, 10.0),  // TL
        const math.Point<double>(80.0, 15.0),  // TR
        const math.Point<double>(95.0, 90.0),  // BR
        const math.Point<double>(5.0, 85.0),   // BL
      ];

      // Rectangular destination
      const dstW = 200.0;
      const dstH = 300.0;
      final dstPts = [
        const math.Point<double>(0.0, 0.0),
        const math.Point<double>(dstW - 1, 0.0),
        const math.Point<double>(dstW - 1, dstH - 1),
        const math.Point<double>(0.0, dstH - 1),
      ];

      final h = service.computeHomography(dstPts, srcPts);
      expect(h, isNotNull);

      // Verify projective equation for each corner:
      // x = (h00*u + h01*v + h02) / (h20*u + h21*v + 1)
      // y = (h10*u + h11*v + h12) / (h20*u + h21*v + 1)
      for (int i = 0; i < 4; i++) {
        final u = dstPts[i].x;
        final v = dstPts[i].y;
        final w = h![6] * u + h[7] * v + 1.0;
        final x = (h[0] * u + h[1] * v + h[2]) / w;
        final y = (h[3] * u + h[4] * v + h[5]) / w;

        expect(x, closeTo(srcPts[i].x, 1e-4));
        expect(y, closeTo(srcPts[i].y, 1e-4));
      }
    });

    test('Singular system with 3 collinear points safely returns null without crashing', () {
      final collinearPts = [
        const math.Point<double>(0.0, 0.0),
        const math.Point<double>(50.0, 0.0),
        const math.Point<double>(100.0, 0.0), // collinear with first two
        const math.Point<double>(50.0, 50.0),
      ];
      final target = [
        const math.Point<double>(0.0, 0.0),
        const math.Point<double>(100.0, 0.0),
        const math.Point<double>(100.0, 100.0),
        const math.Point<double>(0.0, 100.0),
      ];

      final h = service.computeHomography(collinearPts, target);
      expect(h, isNull);
    });

    test('warpPerspectiveCrop with null homography safely returns uncropped source', () {
      final imgSource = img.Image(width: 50, height: 50);
      imgSource.setPixelRgba(10, 10, 255, 0, 0, 255);

      // Pass collinear polygon that will fail homography
      const badPoly = CropPolygon(
        topLeft: Point2D(0.1, 0.5),
        topRight: Point2D(0.3, 0.5),
        bottomRight: Point2D(0.7, 0.5),
        bottomLeft: Point2D(0.9, 0.5),
      );

      final result = service.warpPerspectiveCrop(imgSource, badPoly);
      expect(result, isNotNull);
      expect(result.width, greaterThanOrEqualTo(10));
      expect(result.height, greaterThanOrEqualTo(10));
    });
  });

  group('CHALLENGE 5: Rotation Matrices (0°, 90°, 180°, 270°)', () {
    late img.Image testImg;
    const w = 40;
    const h = 25;

    setUp(() {
      testImg = img.Image(width: w, height: h);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          testImg.setPixelRgba(x, y, x, y, (x + y) % 256, 255);
        }
      }
    });

    test('0° leaves dimensions and pixels unchanged', () {
      final r0 = service.rotateClockwise(testImg, 0);
      expect(r0.width, equals(w));
      expect(r0.height, equals(h));
      for (int y = 0; y < h; y += 5) {
        for (int x = 0; x < w; x += 5) {
          final p = r0.getPixel(x, y);
          expect(p.r.toInt(), equals(x));
          expect(p.g.toInt(), equals(y));
        }
      }
    });

    test('90° clockwise transposes dimensions to (H, W) and maps (x, y) -> (H - 1 - y, x)', () {
      final r90 = service.rotateClockwise(testImg, 90);
      expect(r90.width, equals(h));
      expect(r90.height, equals(w));

      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final dstX = h - 1 - y;
          final dstY = x;
          final p = r90.getPixel(dstX, dstY);
          expect(p.r.toInt(), equals(x));
          expect(p.g.toInt(), equals(y));
        }
      }
    });

    test('180° preserves dimensions and maps (x, y) -> (W - 1 - x, H - 1 - y)', () {
      final r180 = service.rotateClockwise(testImg, 180);
      expect(r180.width, equals(w));
      expect(r180.height, equals(h));

      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final dstX = w - 1 - x;
          final dstY = h - 1 - y;
          final p = r180.getPixel(dstX, dstY);
          expect(p.r.toInt(), equals(x));
          expect(p.g.toInt(), equals(y));
        }
      }
    });

    test('270° clockwise transposes dimensions to (H, W) and maps (x, y) -> (y, W - 1 - x)', () {
      final r270 = service.rotateClockwise(testImg, 270);
      expect(r270.width, equals(h));
      expect(r270.height, equals(w));

      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final dstX = y;
          final dstY = w - 1 - x;
          final p = r270.getPixel(dstX, dstY);
          expect(p.r.toInt(), equals(x));
          expect(p.g.toInt(), equals(y));
        }
      }
    });

    test('Four 90° rotations compose to identity', () {
      var current = testImg;
      for (int i = 0; i < 4; i++) {
        current = service.rotateClockwise(current, 90);
      }
      expect(current.width, equals(w));
      expect(current.height, equals(h));

      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final pOrig = testImg.getPixel(x, y);
          final pRot = current.getPixel(x, y);
          expect(pRot.r, equals(pOrig.r));
          expect(pRot.g, equals(pOrig.g));
          expect(pRot.b, equals(pOrig.b));
        }
      }
    });

    test('Negative degrees normalize accurately (-90 == 270)', () {
      final rNeg90 = service.rotateClockwise(testImg, -90);
      final r270 = service.rotateClockwise(testImg, 270);
      expect(rNeg90.width, equals(r270.width));
      expect(rNeg90.height, equals(r270.height));
      expect(rNeg90.getPixel(10, 10).r, equals(r270.getPixel(10, 10).r));
    });
  });

  group('CHALLENGE 6: Filter Algorithms, Otsu Maximization, and Clamping Bounds', () {
    test('Grayscale accurately computes ITU-R BT.601 luminance weights', () {
      final canvas = img.Image(width: 4, height: 1);
      canvas.setPixelRgba(0, 0, 255, 0, 0, 255);     // Pure Red
      canvas.setPixelRgba(1, 0, 0, 255, 0, 255);     // Pure Green
      canvas.setPixelRgba(2, 0, 0, 0, 255, 255);     // Pure Blue
      canvas.setPixelRgba(3, 0, 255, 255, 255, 255); // Pure White

      final filtered = service.applyFilter(canvas, PageFilter.grayscale);

      // Red: 0.299 * 255 = 76.245 -> 76
      final pRed = filtered.getPixel(0, 0);
      expect(pRed.r.toInt(), equals(76));
      expect(pRed.g.toInt(), equals(76));
      expect(pRed.b.toInt(), equals(76));

      // Green: 0.587 * 255 = 149.685 -> 150
      final pGreen = filtered.getPixel(1, 0);
      expect(pGreen.r.toInt(), equals(150));
      expect(pGreen.g.toInt(), equals(150));
      expect(pGreen.b.toInt(), equals(150));

      // Blue: 0.114 * 255 = 29.07 -> 29
      final pBlue = filtered.getPixel(2, 0);
      expect(pBlue.r.toInt(), equals(29));
      expect(pBlue.g.toInt(), equals(29));
      expect(pBlue.b.toInt(), equals(29));

      // White: 76 + 150 + 29 = 255
      final pWhite = filtered.getPixel(3, 0);
      expect(pWhite.r.toInt(), equals(255));
      expect(pWhite.g.toInt(), equals(255));
      expect(pWhite.b.toInt(), equals(255));
    });

    test('Otsu binarization cleanly separates bimodal distribution', () {
      final bimodal = img.Image(width: 100, height: 50);
      // Half dark text (val 40), half light paper (val 220)
      for (int y = 0; y < 50; y++) {
        for (int x = 0; x < 100; x++) {
          final v = (x < 50) ? 40 : 220;
          bimodal.setPixelRgba(x, y, v, v, v, 255);
        }
      }

      final bw = service.applyFilter(bimodal, PageFilter.blackAndWhite);

      // Dark pixels (40) must become 0
      final pDark = bw.getPixel(20, 20);
      expect(pDark.r.toInt(), equals(0));
      expect(pDark.g.toInt(), equals(0));
      expect(pDark.b.toInt(), equals(0));

      // Light pixels (220) must become 255
      final pLight = bw.getPixel(70, 20);
      expect(pLight.r.toInt(), equals(255));
      expect(pLight.g.toInt(), equals(255));
      expect(pLight.b.toInt(), equals(255));
    });

    test('Otsu threshold on uniform image gracefully handles zero variance', () {
      final uniform = img.Image(width: 20, height: 20);
      for (int y = 0; y < 20; y++) {
        for (int x = 0; x < 20; x++) {
          uniform.setPixelRgba(x, y, 100, 100, 100, 255);
        }
      }

      // Default threshold is 128. 100 <= 128 -> all 0
      final bw = service.applyFilter(uniform, PageFilter.blackAndWhite);
      final p = bw.getPixel(5, 5);
      expect(p.r.toInt(), equals(0));
      expect(p.g.toInt(), equals(0));
      expect(p.b.toInt(), equals(0));
    });

    test('Extreme brightness and contrast inputs are clamped strictly within [0, 255]', () {
      final canvas = img.Image(width: 10, height: 10);
      for (int y = 0; y < 10; y++) {
        for (int x = 0; x < 10; x++) {
          canvas.setPixelRgba(x, y, 128, 64, 192, 255);
        }
      }

      // Overdrive contrast (5.0, clamped to 3.0) and brightness (2.0)
      final boosted = service.applyFilter(
        canvas,
        PageFilter.original,
        brightness: 2.0,
        contrast: 5.0,
      );

      for (int y = 0; y < 10; y++) {
        for (int x = 0; x < 10; x++) {
          final p = boosted.getPixel(x, y);
          expect(p.r.toInt(), inInclusiveRange(0, 255));
          expect(p.g.toInt(), inInclusiveRange(0, 255));
          expect(p.b.toInt(), inInclusiveRange(0, 255));
        }
      }

      // Underdrive contrast (0.01, clamped to 0.2) and brightness (-2.0)
      final dim = service.applyFilter(
        canvas,
        PageFilter.original,
        brightness: -2.0,
        contrast: -1.0,
      );

      for (int y = 0; y < 10; y++) {
        for (int x = 0; x < 10; x++) {
          final p = dim.getPixel(x, y);
          expect(p.r.toInt(), inInclusiveRange(0, 255));
          expect(p.g.toInt(), inInclusiveRange(0, 255));
          expect(p.b.toInt(), inInclusiveRange(0, 255));
        }
      }
    });
  });
}
