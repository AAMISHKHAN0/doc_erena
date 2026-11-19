import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:docerena/core/errors/result.dart';
import 'package:docerena/core/interfaces/i_document_repository.dart';
import 'package:docerena/core/interfaces/i_pdf_generator.dart';
import 'package:docerena/core/interfaces/i_pdf_manipulation_service.dart';
import 'package:docerena/domain/entities/document.dart';
import 'package:docerena/domain/entities/export_result.dart';
import 'package:docerena/domain/entities/page_entity.dart';
import 'package:docerena/core/geometry/crop_polygon.dart';
import 'package:docerena/services/pdf/pdf_generator_service.dart';
import 'package:docerena/services/pdf/pdf_manipulation_service.dart';

/// In-memory fake repository for end-to-end PDF manipulation service testing.
class FakeDocumentRepository implements IDocumentRepository {
  final Map<String, DocumentEntity> _docs = {};
  final Map<String, List<PageEntity>> _pages = {};

  void seed(DocumentEntity doc, List<PageEntity> pages) {
    _docs[doc.id] = doc;
    _pages[doc.id] = pages;
  }

  @override
  Future<Result<List<DocumentEntity>, StorageError>> getAllDocuments() async =>
      Success(_docs.values.toList());

  @override
  Future<Result<DocumentEntity?, StorageError>> getDocumentById(String id) async =>
      Success(_docs[id]);

  @override
  Future<Result<List<PageEntity>, StorageError>> getPagesForDocument(String documentId) async =>
      Success(_pages[documentId] ?? []);

  @override
  Future<Result<DocumentEntity, StorageError>> saveDocumentAtomic({
    required DocumentEntity document,
    required List<PageEntity> pages,
  }) async {
    _docs[document.id] = document.copyWith(pageCount: pages.length);
    _pages[document.id] = pages;
    return Success(_docs[document.id]!);
  }

  @override
  Future<Result<void, StorageError>> deleteDocument(String id) async {
    _docs.remove(id);
    _pages.remove(id);
    return const Success(null);
  }

  @override
  Future<Result<void, StorageError>> renameDocument(String id, String newTitle) async {
    if (_docs.containsKey(id)) {
      _docs[id] = _docs[id]!.copyWith(title: newTitle);
    }
    return const Success(null);
  }

  @override
  Future<Result<List<DocumentEntity>, StorageError>> searchDocuments(String query) async {
    final matches = _docs.values
        .where((d) => d.title.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return Success(matches);
  }

  @override
  Future<Result<DocumentEntity?, StorageError>> getActiveDraft() async =>
      Success(_docs.values.cast<DocumentEntity?>().firstWhere(
            (d) => d?.status == DocumentStatus.draft,
            orElse: () => null,
          ));

  @override
  Future<Result<void, StorageError>> discardDraft(String draftId) async {
    _docs.remove(draftId);
    _pages.remove(draftId);
    return const Success(null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late io.Directory tempDir;
  late PdfGeneratorService pdfGenerator;
  late FakeDocumentRepository fakeRepo;
  late PdfManipulationService manipulationService;

  late String sampleImg1;
  late String sampleImg2;
  late String sampleImg3;
  late String sampleImg4;
  late String sampleImg5;

  setUpAll(() async {
    tempDir = await io.Directory.systemTemp.createTemp('pdf_manip_unit_');
    pdfGenerator = PdfGeneratorService(baseOutputDirectory: tempDir.path);
    fakeRepo = FakeDocumentRepository();
    manipulationService = PdfManipulationService(
      pdfGenerator: pdfGenerator,
      documentRepository: fakeRepo,
    );

    // Create 5 genuine test images with distinct colors and patterns
    Uint8List makeImage(int r, int g, int b, int w, int h) {
      final imgObj = img.Image(width: w, height: h);
      img.fill(imgObj, color: img.ColorRgb8(r, g, b));
      img.drawLine(imgObj, x1: 0, y1: 0, x2: w, y2: h, color: const img.ColorRgb8(255, 255, 255));
      return Uint8List.fromList(img.encodeJpg(imgObj, quality: 85));
    }

    Future<String> writeSample(String name, int r, int g, int b) async {
      final file = io.File('${tempDir.path}/$name');
      await file.writeAsBytes(makeImage(r, g, b, 200, 300));
      return file.path;
    }

    sampleImg1 = await writeSample('page_red.jpg', 220, 50, 50);
    sampleImg2 = await writeSample('page_green.jpg', 50, 200, 50);
    sampleImg3 = await writeSample('page_blue.jpg', 50, 50, 220);
    sampleImg4 = await writeSample('page_yellow.jpg', 220, 220, 50);
    sampleImg5 = await writeSample('page_cyan.jpg', 50, 220, 220);

    // Seed Doc A (2 pages: red, green)
    final docA = DocumentEntity(
      id: 'doc_A',
      title: 'Invoice_Alpha',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      pageCount: 2,
    );
    final pagesA = [
      PageEntity(
        id: 'p_A1',
        documentId: 'doc_A',
        position: 0,
        originalFileKey: sampleImg1,
        cropPolygon: CropPolygon.fullFrame(),
        pixelWidth: 200,
        pixelHeight: 300,
        createdAt: DateTime.now(),
      ),
      PageEntity(
        id: 'p_A2',
        documentId: 'doc_A',
        position: 1,
        originalFileKey: sampleImg2,
        cropPolygon: CropPolygon.fullFrame(),
        pixelWidth: 200,
        pixelHeight: 300,
        createdAt: DateTime.now(),
      ),
    ];
    fakeRepo.seed(docA, pagesA);

    // Seed Doc B (3 pages: blue, yellow, cyan)
    final docB = DocumentEntity(
      id: 'doc_B',
      title: 'Invoice_Beta',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      pageCount: 3,
    );
    final pagesB = [
      PageEntity(
        id: 'p_B1',
        documentId: 'doc_B',
        position: 0,
        originalFileKey: sampleImg3,
        cropPolygon: CropPolygon.fullFrame(),
        pixelWidth: 200,
        pixelHeight: 300,
        createdAt: DateTime.now(),
      ),
      PageEntity(
        id: 'p_B2',
        documentId: 'doc_B',
        position: 1,
        originalFileKey: sampleImg4,
        cropPolygon: CropPolygon.fullFrame(),
        pixelWidth: 200,
        pixelHeight: 300,
        createdAt: DateTime.now(),
      ),
      PageEntity(
        id: 'p_B3',
        documentId: 'doc_B',
        position: 2,
        originalFileKey: sampleImg5,
        cropPolygon: CropPolygon.fullFrame(),
        pixelWidth: 200,
        pixelHeight: 300,
        createdAt: DateTime.now(),
      ),
    ];
    fakeRepo.seed(docB, pagesB);
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Tier 1: Offline PDF Merge', () {
    test('combines multiple documents into unified ISO 32000 PDF with cumulative page count', () async {
      final mergeResult = await manipulationService.mergeDocuments(
        sourceDocumentIds: ['doc_A', 'doc_B'],
        mergedTitle: 'Merged_Invoices_AB',
        pageFormat: PdfPageFormat.a4,
        quality: PdfQualityPreset.high,
      );

      expect(mergeResult.isSuccess, isTrue);
      final mergedPdf = mergeResult.dataOrNull!;
      expect(mergedPdf.pageCount, equals(5)); // 2 + 3 = 5 cumulative pages
      expect(mergedPdf.fileSizeBytes, greaterThan(0));

      final file = io.File(mergedPdf.filePath);
      expect(await file.exists(), isTrue);

      // Validate ISO 32000 structure using validatePdfFile
      final valResult = await pdfGenerator.validatePdfFile(mergedPdf.filePath);
      expect(valResult.isSuccess, isTrue);
      final valInfo = valResult.dataOrNull!;
      expect(valInfo.isValid, isTrue);
      expect(valInfo.pageCount, equals(5));

      // Validate %PDF- header and %%EOF marker in raw bytes
      final bytes = await file.readAsBytes();
      final header = String.fromCharCodes(bytes.sublist(0, 5));
      expect(header, equals('%PDF-'));

      final content = String.fromCharCodes(bytes);
      expect(content.contains('%%EOF'), isTrue);
    });

    test('refuses merge when document ID list is empty', () async {
      final result = await manipulationService.mergeDocuments(
        sourceDocumentIds: [],
        mergedTitle: 'Empty_Merge',
      );

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.code, equals(PdfExportErrorCode.emptyDocument));
    });
  });

  group('Tier 1: Offline PDF Split', () {
    test('divides document by page ranges into independent valid PDF streams', () async {
      // Split Doc B (3 pages: indices 0, 1, 2) into Part 1 (Pages 0-1) and Part 2 (Page 2)
      final splitResult = await manipulationService.splitDocument(
        sourceDocumentId: 'doc_B',
        pageIndexRanges: [
          [0, 1], // Part 1: 2 pages
          [2],    // Part 2: 1 page
        ],
        baseTitle: 'Split_Beta',
      );

      expect(splitResult.isSuccess, isTrue);
      final splitPdfs = splitResult.dataOrNull!;
      expect(splitPdfs.length, equals(2));

      // Part 1 Verification
      final part1 = splitPdfs[0];
      expect(part1.pageCount, equals(2));
      final val1 = await pdfGenerator.validatePdfFile(part1.filePath);
      expect(val1.isSuccess, isTrue);
      expect(val1.dataOrNull!.isValid, isTrue);
      expect(val1.dataOrNull!.pageCount, equals(2));

      final bytes1 = await io.File(part1.filePath).readAsBytes();
      expect(String.fromCharCodes(bytes1.sublist(0, 5)), equals('%PDF-'));
      expect(String.fromCharCodes(bytes1).contains('%%EOF'), isTrue);

      // Part 2 Verification
      final part2 = splitPdfs[1];
      expect(part2.pageCount, equals(1));
      final val2 = await pdfGenerator.validatePdfFile(part2.filePath);
      expect(val2.isSuccess, isTrue);
      expect(val2.dataOrNull!.isValid, isTrue);
      expect(val2.dataOrNull!.pageCount, equals(1));

      final bytes2 = await io.File(part2.filePath).readAsBytes();
      expect(String.fromCharCodes(bytes2.sublist(0, 5)), equals('%PDF-'));
      expect(String.fromCharCodes(bytes2).contains('%%EOF'), isTrue);
    });

    test('split returns failure when page index exceeds total page count', () async {
      final invalidSplit = await manipulationService.splitDocument(
        sourceDocumentId: 'doc_A', // 2 pages (indices 0, 1)
        pageIndexRanges: [
          [0, 5], // index 5 is out of range
        ],
        baseTitle: 'Invalid_Split',
      );

      expect(invalidSplit.isFailure, isTrue);
      expect(invalidSplit.errorOrNull?.message, contains('out of range'));
    });
  });

  group('Tier 1: 90-Degree Page Rotation in PDF', () {
    test('renders 90, 180, and 270 degree page rotations cleanly in PDF export', () async {
      final rotatedSpecs = [
        PdfPageSpec(
          imagePath: sampleImg1,
          rotationDegrees: 0,
          position: 0,
          pixelWidth: 200,
          pixelHeight: 300,
        ),
        PdfPageSpec(
          imagePath: sampleImg2,
          rotationDegrees: 90,
          position: 1,
          pixelWidth: 200,
          pixelHeight: 300,
        ),
        PdfPageSpec(
          imagePath: sampleImg3,
          rotationDegrees: 180,
          position: 2,
          pixelWidth: 200,
          pixelHeight: 300,
        ),
        PdfPageSpec(
          imagePath: sampleImg4,
          rotationDegrees: 270,
          position: 3,
          pixelWidth: 200,
          pixelHeight: 300,
        ),
      ];

      final result = await pdfGenerator.generateMultipagePdf(
        documentTitle: 'Rotated_Angles_Test',
        pages: rotatedSpecs,
        pageFormat: PdfPageFormat.fitToImage,
        quality: PdfQualityPreset.high,
      );

      expect(result.isSuccess, isTrue);
      final pdfInfo = result.dataOrNull!;
      expect(pdfInfo.pageCount, equals(4));

      final val = await pdfGenerator.validatePdfFile(pdfInfo.filePath);
      expect(val.isSuccess, isTrue);
      expect(val.dataOrNull!.isValid, isTrue);
      expect(val.dataOrNull!.pageCount, equals(4));

      final bytes = await io.File(pdfInfo.filePath).readAsBytes();
      expect(String.fromCharCodes(bytes.sublist(0, 5)), equals('%PDF-'));
      expect(String.fromCharCodes(bytes).contains('%%EOF'), isTrue);
    });

    test('quadruple 90-degree rotations cycle 360 degrees back to 0 orientation', () {
      final page = PageEntity(
        id: 'rot_cycle',
        documentId: 'doc_rot',
        position: 0,
        originalFileKey: sampleImg1,
        cropPolygon: CropPolygon.fullFrame(),
        pixelWidth: 200,
        pixelHeight: 300,
        createdAt: DateTime.now(),
      );

      expect(page.rotationDegrees, equals(0));
      final rot90 = page.rotate90Clockwise();
      expect(rot90.rotationDegrees, equals(90));
      final rot180 = rot90.rotate90Clockwise();
      expect(rot180.rotationDegrees, equals(180));
      final rot270 = rot180.rotate90Clockwise();
      expect(rot270.rotationDegrees, equals(270));
      final rot360 = rot270.rotate90Clockwise();
      expect(rot360.rotationDegrees, equals(0)); // Normalized back to original
    });

    test('rotateDocumentPages applies rotation map and compiles valid PDF', () async {
      final rotateResult = await manipulationService.rotateDocumentPages(
        documentId: 'doc_A',
        pageIndexToRotationDegrees: {0: 90, 1: 180},
        targetTitle: 'Rotated_Doc_A',
      );

      expect(rotateResult.isSuccess, isTrue);
      final rotatedPdf = rotateResult.dataOrNull!;
      expect(rotatedPdf.pageCount, equals(2));

      final val = await pdfGenerator.validatePdfFile(rotatedPdf.filePath);
      expect(val.isSuccess, isTrue);
      expect(val.dataOrNull!.isValid, isTrue);
      expect(val.dataOrNull!.pageCount, equals(2));
    });

    test('rotateDocumentPages rejects non-orthogonal rotation angles', () async {
      final invalidRotate = await manipulationService.rotateDocumentPages(
        documentId: 'doc_A',
        pageIndexToRotationDegrees: {0: 45},
        targetTitle: 'Invalid_Rotate',
      );

      expect(invalidRotate.isFailure, isTrue);
      expect(invalidRotate.errorOrNull?.code, equals(PdfExportErrorCode.invalidPageSequence));
    });
  });

  group('Tier 1: Page Extraction & Deletion', () {
    test('extracts selected subset of pages into independent standalone PDF', () async {
      // Extract page index 1 from Doc B (yellow invoice)
      final extractResult = await manipulationService.extractPages(
        sourceDocumentId: 'doc_B',
        selectedPageIndices: [1],
        newDocumentTitle: 'Extracted_Yellow_Invoice',
      );

      expect(extractResult.isSuccess, isTrue);
      final extractedPdf = extractResult.dataOrNull!;
      expect(extractedPdf.pageCount, equals(1));

      final val = await pdfGenerator.validatePdfFile(extractedPdf.filePath);
      expect(val.isSuccess, isTrue);
      expect(val.dataOrNull!.isValid, isTrue);
      expect(val.dataOrNull!.pageCount, equals(1));
    });

    test('deletes selected page and cleanly re-indexes remaining pages in repository', () async {
      // Create dedicated doc with 3 pages to test deletion
      final docToMutate = DocumentEntity(
        id: 'doc_delete_test',
        title: 'Delete_Doc',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        pageCount: 3,
      );
      final pagesToMutate = [
        PageEntity(
          id: 'del_p0',
          documentId: 'doc_delete_test',
          position: 0,
          originalFileKey: sampleImg1,
          cropPolygon: CropPolygon.fullFrame(),
          pixelWidth: 200,
          pixelHeight: 300,
          createdAt: DateTime.now(),
        ),
        PageEntity(
          id: 'del_p1',
          documentId: 'doc_delete_test',
          position: 1,
          originalFileKey: sampleImg2,
          cropPolygon: CropPolygon.fullFrame(),
          pixelWidth: 200,
          pixelHeight: 300,
          createdAt: DateTime.now(),
        ),
        PageEntity(
          id: 'del_p2',
          documentId: 'doc_delete_test',
          position: 2,
          originalFileKey: sampleImg3,
          cropPolygon: CropPolygon.fullFrame(),
          pixelWidth: 200,
          pixelHeight: 300,
          createdAt: DateTime.now(),
        ),
      ];
      fakeRepo.seed(docToMutate, pagesToMutate);

      // Delete middle page at index 1
      final deleteResult = await manipulationService.deletePages(
        documentId: 'doc_delete_test',
        pageIndicesToDelete: [1],
      );

      expect(deleteResult.isSuccess, isTrue);

      final remaining = (await fakeRepo.getPagesForDocument('doc_delete_test')).dataOrNull!;
      expect(remaining.length, equals(2));
      expect(remaining[0].id, equals('del_p0'));
      expect(remaining[0].position, equals(0));
      expect(remaining[1].id, equals('del_p2'));
      expect(remaining[1].position, equals(1)); // Re-indexed to 1
    });

    test('refuses to delete all pages from a document (must retain >= 1 page)', () async {
      final deleteAllResult = await manipulationService.deletePages(
        documentId: 'doc_A',
        pageIndicesToDelete: [0, 1], // Both pages
      );

      expect(deleteAllResult.isFailure, isTrue);
      expect(deleteAllResult.errorOrNull?.code, equals(PdfExportErrorCode.emptyDocument));
    });

    test('extractDocumentPages extracts selected subset adhering to PROJECT.md contract', () async {
      final extractResult = await manipulationService.extractDocumentPages(
        sourceDocumentId: 'doc_B',
        pageIndicesToExtract: [0, 2],
        extractedTitle: 'Extracted_B_Subset',
      );

      expect(extractResult.isSuccess, isTrue);
      final extractedPdf = extractResult.dataOrNull!;
      expect(extractedPdf.pageCount, equals(2));

      final val = await pdfGenerator.validatePdfFile(extractedPdf.filePath);
      expect(val.isSuccess, isTrue);
      expect(val.dataOrNull!.isValid, isTrue);
      expect(val.dataOrNull!.pageCount, equals(2));
    });

    test('deleteDocumentPages aliases deletePages and re-indexes properly', () async {
      final docToMutate = DocumentEntity(
        id: 'doc_del_contract',
        title: 'Delete_Contract',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        pageCount: 2,
      );
      final pagesToMutate = [
        PageEntity(
          id: 'dc_p0',
          documentId: 'doc_del_contract',
          position: 0,
          originalFileKey: sampleImg1,
          cropPolygon: CropPolygon.fullFrame(),
          pixelWidth: 200,
          pixelHeight: 300,
          createdAt: DateTime.now(),
        ),
        PageEntity(
          id: 'dc_p1',
          documentId: 'doc_del_contract',
          position: 1,
          originalFileKey: sampleImg2,
          cropPolygon: CropPolygon.fullFrame(),
          pixelWidth: 200,
          pixelHeight: 300,
          createdAt: DateTime.now(),
        ),
      ];
      fakeRepo.seed(docToMutate, pagesToMutate);

      final deleteResult = await manipulationService.deleteDocumentPages(
        documentId: 'doc_del_contract',
        pageIndicesToDelete: [0],
      );

      expect(deleteResult.isSuccess, isTrue);
      final remaining = (await fakeRepo.getPagesForDocument('doc_del_contract')).dataOrNull!;
      expect(remaining.length, equals(1));
      expect(remaining[0].id, equals('dc_p1'));
      expect(remaining[0].position, equals(0));
    });
  });

  group('Tier 1: UI Range Syntax Parser (PdfRangeParser)', () {
    test('parses 1-indexed human strings into 0-indexed integer ranges', () {
      final result = PdfRangeParser.parseRanges('1-2, 3', totalPages: 5);
      expect(result.isSuccess, isTrue);
      expect(
        result.dataOrNull,
        equals([
          [0, 1],
          [2],
        ]),
      );
    });

    test('parses comma-separated single pages and multi-page intervals', () {
      final result = PdfRangeParser.parseRanges('1, 3-5, 8', totalPages: 10);
      expect(result.isSuccess, isTrue);
      expect(
        result.dataOrNull,
        equals([
          [0],
          [2, 3, 4],
          [7],
        ]),
      );
    });

    test('rejects out-of-bounds ranges and inverted intervals', () {
      final outOfBounds = PdfRangeParser.parseRanges('1-12', totalPages: 5);
      expect(outOfBounds.isFailure, isTrue);

      final inverted = PdfRangeParser.parseRanges('5-2', totalPages: 5);
      expect(inverted.isFailure, isTrue);

      final emptyInput = PdfRangeParser.parseRanges('   ', totalPages: 5);
      expect(emptyInput.isFailure, isTrue);

      final malformed = PdfRangeParser.parseRanges('1-abc', totalPages: 5);
      expect(malformed.isFailure, isTrue);
    });

    test('formats 0-indexed ranges into human-readable 1-indexed string', () {
      final str = PdfRangeParser.formatRanges([0, 1, 2, 4]);
      expect(str, equals('1-3, 5'));
    });
  });
}
