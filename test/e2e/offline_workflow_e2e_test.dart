import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:docerena/core/errors/result.dart';
import 'package:docerena/core/geometry/crop_polygon.dart';
import 'package:docerena/core/interfaces/i_pdf_generator.dart';
import 'package:docerena/core/interfaces/i_share_service.dart';
import 'package:docerena/core/storage/file_storage_service.dart';
import 'package:docerena/data/database/database_helper.dart';
import 'package:docerena/data/repositories/document_repository.dart';
import 'package:docerena/domain/entities/document.dart';
import 'package:docerena/domain/entities/page_entity.dart';

import 'pdf_export_integrity_test.dart';

/// Test implementation of IShareService verifying parameters passed to Android FileProvider
class TestShareService implements IShareService {
  String? lastSharedPath;
  String? lastMimeType;
  String? lastSubject;
  bool shareCalled = false;

  @override
  Future<Result<void, ShareError>> sharePdf({
    required String pdfCachePath,
    required String mimeType,
    required String subject,
  }) async {
    shareCalled = true;
    lastSharedPath = pdfCachePath;
    lastMimeType = mimeType;
    lastSubject = subject;

    final file = File(pdfCachePath);
    if (!await file.exists()) {
      return const Failure(
        ShareError(
          message: 'Target share file does not exist',
          code: ShareErrorCode.fileNotFound,
        ),
      );
    }

    // Verify privacy: never allow sharing docerena.db
    if (pdfCachePath.endsWith('.db')) {
      return const Failure(
        ShareError(
          message: 'Forbidden attempt to share internal database file',
          code: ShareErrorCode.shareFailed,
        ),
      );
    }

    return const Success(null);
  }

  @override
  Future<Result<String, ShareError>> saveCopyViaPicker({
    required String sourceCachePath,
    required String suggestedFileName,
  }) async {
    return Success('/storage/emulated/0/Documents/$suggestedFileName');
  }
}

void main() {
  sqfliteFfiInit();

  late Directory workspaceDir;
  late FileStorageService storageService;
  late DatabaseHelper dbHelper;
  late DocumentRepository repository;
  late StandardPdfGenerator pdfGenerator;
  late TestShareService shareService;

  setUp(() async {
    workspaceDir = await Directory.systemTemp.createTemp('docerena_offline_workflow_');
    storageService = FileStorageService(basePath: workspaceDir.path);
    dbHelper = DatabaseHelper(
      databaseFactory: databaseFactoryFfi,
      databasePath: '${workspaceDir.path}/docerena.db',
    );
    repository = DocumentRepository(databaseHelper: dbHelper);
    pdfGenerator = StandardPdfGenerator(outputDirectory: '${workspaceDir.path}/cache/exports');
    shareService = TestShareService();
  });

  tearDown(() async {
    await dbHelper.close();
    if (await workspaceDir.exists()) {
      await workspaceDir.delete(recursive: true);
    }
  });

  Uint8List createSampleImageBytes(int r, int g, int b) {
    final image = img.Image(width: 300, height: 400);
    img.fill(image, color: img.ColorRgb8(r, g, b));
    return Uint8List.fromList(img.encodePng(image));
  }

  group('Offline Workflow End-to-End Tests (Tier 4 Real-World Scenarios)', () {
    test('Scenario 1: Complete 3-page scan -> crop -> rotate -> reorder -> draft recovery -> save -> PDF export -> share', () async {
      final docId = 'contract-doc-2026';

      // ---------------------------------------------------------
      // Step 1: Capture / Ingest 3 document pages into app-private storage
      // ---------------------------------------------------------
      final page1Key = storageService.createOriginalKey(docId, 'page-1');
      final page2Key = storageService.createOriginalKey(docId, 'page-2');
      final page3Key = storageService.createOriginalKey(docId, 'page-3');

      final rawBytes1 = createSampleImageBytes(200, 50, 50); // Reddish sheet
      final rawBytes2 = createSampleImageBytes(50, 200, 50); // Greenish sheet
      final rawBytes3 = createSampleImageBytes(50, 50, 200); // Blueish sheet

      final writeRes1 = await storageService.writeAtomic(page1Key, rawBytes1);
      final writeRes2 = await storageService.writeAtomic(page2Key, rawBytes2);
      final writeRes3 = await storageService.writeAtomic(page3Key, rawBytes3);

      expect(writeRes1.isSuccess, isTrue);
      expect(writeRes2.isSuccess, isTrue);
      expect(writeRes3.isSuccess, isTrue);

      // ---------------------------------------------------------
      // Step 2: Non-destructive manual crop adjustment on Page 1
      // ---------------------------------------------------------
      const customCrop = CropPolygon(
        topLeft: Point2D(0.08, 0.1),
        topRight: Point2D(0.92, 0.12),
        bottomRight: Point2D(0.9, 0.95),
        bottomLeft: Point2D(0.1, 0.92),
      );
      expect(customCrop.isValid, isTrue);

      var p1 = PageEntity(
        id: 'page-1',
        documentId: docId,
        position: 0,
        originalFileKey: page1Key,
        cropPolygon: customCrop,
        pixelWidth: 300,
        pixelHeight: 400,
        createdAt: DateTime.now(),
      );

      // Verify original file on disk remains untouched
      final p1OriginalBytes = await storageService.readFile(page1Key);
      expect(p1OriginalBytes.dataOrNull, equals(rawBytes1));

      // ---------------------------------------------------------
      // Step 3: Rotate Page 2 by 90 degrees clockwise
      // ---------------------------------------------------------
      var p2 = PageEntity(
        id: 'page-2',
        documentId: docId,
        position: 1,
        originalFileKey: page2Key,
        cropPolygon: CropPolygon.fullFrame(),
        pixelWidth: 300,
        pixelHeight: 400,
        createdAt: DateTime.now(),
      );

      p2 = p2.rotate90Clockwise();
      expect(p2.rotationDegrees, equals(90));

      var p3 = PageEntity(
        id: 'page-3',
        documentId: docId,
        position: 2,
        originalFileKey: page3Key,
        cropPolygon: CropPolygon.fullFrame(),
        pixelWidth: 300,
        pixelHeight: 400,
        createdAt: DateTime.now(),
      );

      // ---------------------------------------------------------
      // Step 4: Page Reordering in S06 Organizer (Page 3 moved to index 0)
      // Initial: [p1, p2, p3] -> Desired: [p3, p1, p2]
      // ---------------------------------------------------------
      final initialPages = [p1, p2, p3];
      final item = initialPages.removeAt(2); // remove p3
      initialPages.insert(0, item); // insert at front
      final reorderedPages = List.generate(
        initialPages.length,
        (i) => initialPages[i].copyWith(position: i),
      );

      expect(reorderedPages[0].id, equals('page-3'));
      expect(reorderedPages[0].position, equals(0));
      expect(reorderedPages[1].id, equals('page-1'));
      expect(reorderedPages[1].position, equals(1));
      expect(reorderedPages[2].id, equals('page-2'));
      expect(reorderedPages[2].position, equals(2));

      // ---------------------------------------------------------
      // Step 5: Save as active draft in SQLite
      // ---------------------------------------------------------
      final draftDoc = DocumentEntity(
        id: docId,
        title: 'Draft Contract',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        status: DocumentStatus.draft,
      );

      final saveDraftResult = await repository.saveDocumentAtomic(
        document: draftDoc,
        pages: reorderedPages,
      );
      expect(saveDraftResult.isSuccess, isTrue);

      // ---------------------------------------------------------
      // Step 6: Simulate App Cold Restart & Active Draft Recovery
      // ---------------------------------------------------------
      final freshRepository = DocumentRepository(databaseHelper: dbHelper);
      final activeDraftResult = await freshRepository.getActiveDraft();

      expect(activeDraftResult.isSuccess, isTrue);
      expect(activeDraftResult.dataOrNull, isNotNull);
      final recoveredDraft = activeDraftResult.dataOrNull!;
      expect(recoveredDraft.id, equals(docId));
      expect(recoveredDraft.isDraft, isTrue);

      final recoveredPages = await freshRepository.getPagesForDocument(docId);
      expect(recoveredPages.isSuccess, isTrue);
      final pageList = recoveredPages.dataOrNull!;
      expect(pageList.length, equals(3));

      // Verify sequence and metadata preserved across restart
      expect(pageList[0].id, equals('page-3'));
      expect(pageList[0].position, equals(0));

      expect(pageList[1].id, equals('page-1'));
      expect(pageList[1].position, equals(1));
      expect(pageList[1].cropPolygon.topLeft.x, closeTo(0.08, 1e-5));

      expect(pageList[2].id, equals('page-2'));
      expect(pageList[2].position, equals(2));
      expect(pageList[2].rotationDegrees, equals(90));

      // ---------------------------------------------------------
      // Step 7: Final Save Document Commit ('draft' -> 'saved')
      // ---------------------------------------------------------
      final committedDoc = recoveredDraft.copyWith(
        title: 'Official_Contract_2026',
        status: DocumentStatus.saved,
        updatedAt: DateTime.now(),
      );

      final commitResult = await freshRepository.saveDocumentAtomic(
        document: committedDoc,
        pages: pageList,
      );
      expect(commitResult.isSuccess, isTrue);

      // Verify committed document appears in saved list and no active drafts remain
      final allDocs = await freshRepository.getAllDocuments();
      expect(allDocs.dataOrNull?.length, equals(1));
      expect(allDocs.dataOrNull?.first.title, equals('Official_Contract_2026'));

      final noMoreDraft = await freshRepository.getActiveDraft();
      expect(noMoreDraft.dataOrNull, isNull);

      // ---------------------------------------------------------
      // Step 8: Multipage PDF Export from the ordered pages
      // ---------------------------------------------------------
      final pdfSpecs = pageList.map((p) {
        return PdfPageSpec(
          imagePath: '${workspaceDir.path}/${p.originalFileKey}',
          rotationDegrees: p.rotationDegrees,
          position: p.position,
          pixelWidth: p.pixelWidth.toDouble(),
          pixelHeight: p.pixelHeight.toDouble(),
        );
      }).toList();

      final exportResult = await pdfGenerator.generateMultipagePdf(
        documentTitle: committedDoc.title,
        pages: pdfSpecs,
        pageFormat: PdfPageFormat.a4,
        quality: PdfQualityPreset.high,
      );

      expect(exportResult.isSuccess, isTrue);
      final generatedPdf = exportResult.dataOrNull!;
      expect(generatedPdf.pageCount, equals(3));
      expect(File(generatedPdf.filePath).existsSync(), isTrue);

      // Verify PDF structure
      final validation = await pdfGenerator.validatePdfFile(generatedPdf.filePath);
      expect(validation.isSuccess, isTrue);
      expect(validation.dataOrNull?.isValid, isTrue);
      expect(validation.dataOrNull?.pageCount, equals(3));

      // ---------------------------------------------------------
      // Step 9: Sharing PDF via Android Share Sheet (FileProvider)
      // ---------------------------------------------------------
      final shareResult = await shareService.sharePdf(
        pdfCachePath: generatedPdf.filePath,
        mimeType: 'application/pdf',
        subject: committedDoc.title,
      );

      expect(shareResult.isSuccess, isTrue);
      expect(shareService.shareCalled, isTrue);
      expect(shareService.lastSharedPath, equals(generatedPdf.filePath));
      expect(shareService.lastMimeType, equals('application/pdf'));
      expect(shareService.lastSubject, equals('Official_Contract_2026'));
    });

    test('Scenario 2: Batch import of 4 pages with page deletion and re-indexing', () async {
      const docId = 'receipts-batch';

      // 4 pages created
      final pages = List.generate(4, (i) {
        final key = storageService.createOriginalKey(docId, 'r-$i');
        return PageEntity(
          id: 'r-$i',
          documentId: docId,
          position: i,
          originalFileKey: key,
          cropPolygon: CropPolygon.fullFrame(),
          pixelWidth: 200,
          pixelHeight: 200,
          createdAt: DateTime.now(),
        );
      });

      // Write images to disk
      for (final p in pages) {
        await storageService.writeAtomic(p.originalFileKey, createSampleImageBytes(10, 20, 30));
      }

      // Delete page at index 1 (r-1)
      pages.removeAt(1);
      final reindexed = List.generate(pages.length, (i) => pages[i].copyWith(position: i));

      expect(reindexed.length, equals(3));
      expect(reindexed[0].id, equals('r-0'));
      expect(reindexed[0].position, equals(0));
      expect(reindexed[1].id, equals('r-2'));
      expect(reindexed[1].position, equals(1));
      expect(reindexed[2].id, equals('r-3'));
      expect(reindexed[2].position, equals(2));

      // Save document
      final doc = DocumentEntity(
        id: docId,
        title: 'Batch Receipts',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        status: DocumentStatus.saved,
      );

      final saveRes = await repository.saveDocumentAtomic(document: doc, pages: reindexed);
      expect(saveRes.isSuccess, isTrue);

      final fetchedPages = await repository.getPagesForDocument(docId);
      expect(fetchedPages.dataOrNull?.length, equals(3));
      expect(fetchedPages.dataOrNull?[1].id, equals('r-2'));
    });

    test('Scenario 3: Degenerate crop fallback maintains pipeline stability', () async {
      // Bowtie polygon with self-intersecting edges
      const invalidCrop = CropPolygon(
        topLeft: Point2D(0.0, 0.0),
        topRight: Point2D(1.0, 1.0),
        bottomRight: Point2D(1.0, 0.0),
        bottomLeft: Point2D(0.0, 1.0),
      );

      expect(invalidCrop.isValid, isFalse);
      final sanitized = invalidCrop.sanitizeOrFallback();

      // Sanitization safely falls back to full-frame rectangle
      expect(sanitized, equals(CropPolygon.fullFrame()));
      expect(sanitized.isValid, isTrue);
    });
  });
}
