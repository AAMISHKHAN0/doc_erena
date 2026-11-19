import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:docerena/core/geometry/crop_polygon.dart';
import 'package:docerena/core/interfaces/i_document_scanner.dart';
import 'package:docerena/data/database/database_helper.dart';
import 'package:docerena/data/repositories/document_repository.dart';
import 'package:docerena/domain/entities/batch_scan_session.dart';
import 'package:docerena/domain/entities/document.dart';
import 'package:docerena/domain/entities/page_entity.dart';

void main() {
  // Initialize FFI for headless desktop/test SQLite execution
  sqfliteFfiInit();

  late Directory tempDir;
  late String dbPath;
  late DatabaseHelper dbHelper;
  late DocumentRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('batch_session_test_');
    dbPath = '${tempDir.path}/batch_scan.db';
    dbHelper = DatabaseHelper(
      databaseFactory: databaseFactoryFfi,
      databasePath: dbPath,
    );
    repository = DocumentRepository(databaseHelper: dbHelper);
  });

  tearDown(() async {
    await dbHelper.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  PageEntity createSamplePage(String docId, int pos, {String? pageId, int rot = 0}) {
    final pid = pageId ?? 'page_${docId}_$pos';
    return PageEntity(
      id: pid,
      documentId: docId,
      position: pos,
      originalFileKey: 'documents/$docId/pages/$pid.jpg',
      cropPolygon: CropPolygon.fullFrame(),
      rotationDegrees: rot,
      filter: PageFilter.original,
      pixelWidth: 1080,
      pixelHeight: 1920,
      createdAt: DateTime.now(),
    );
  }

  group('Tier 1: BatchScanSession State Accumulation', () {
    test('startNew creates an empty session with default auto flash and dirty=false', () {
      final session = BatchScanSession.startNew(
        documentId: 'draft_session_001',
        suggestedTitle: 'Invoice_Batch',
      );

      expect(session.documentId, equals('draft_session_001'));
      expect(session.suggestedTitle, equals('Invoice_Batch'));
      expect(session.pageCount, equals(0));
      expect(session.isEmpty, isTrue);
      expect(session.isNotEmpty, isFalse);
      expect(session.isDirty, isFalse);
      expect(session.flashMode, equals(CameraFlashMode.auto));
      expect(session.latestPage, isNull);
    });

    test('addPage appends pages in sequence and normalizes contiguous positions', () {
      var session = BatchScanSession.startNew(documentId: 'draft_seq_1');

      final p1 = createSamplePage('draft_seq_1', 99, pageId: 'p1'); // position should normalize to 0
      session = session.addPage(p1);

      expect(session.pageCount, equals(1));
      expect(session.isDirty, isTrue);
      expect(session.pages.first.position, equals(0));
      expect(session.latestPage?.id, equals('p1'));

      final p2 = createSamplePage('draft_seq_1', 88, pageId: 'p2'); // should normalize to 1
      session = session.addPage(p2);

      expect(session.pageCount, equals(2));
      expect(session.pages[1].position, equals(1));
      expect(session.latestPage?.id, equals('p2'));

      final p3 = createSamplePage('draft_seq_1', 77, pageId: 'p3'); // should normalize to 2
      session = session.addPage(p3);

      expect(session.pageCount, equals(3));
      expect(session.pages[2].position, equals(2));
      expect(session.latestPage?.id, equals('p3'));
    });

    test('rapid multi-page capture simulation accumulates 10 pages in exact order', () {
      var session = BatchScanSession.startNew(documentId: 'rapid_batch_10');

      for (int i = 0; i < 10; i++) {
        final newPage = createSamplePage('rapid_batch_10', i, pageId: 'rapid_page_$i');
        session = session.addPage(newPage);
        expect(session.pageCount, equals(i + 1));
        expect(session.latestPage?.id, equals('rapid_page_$i'));
      }

      expect(session.pageCount, equals(10));
      for (int i = 0; i < 10; i++) {
        expect(session.pages[i].id, equals('rapid_page_$i'));
        expect(session.pages[i].position, equals(i));
      }
    });

    test('removePage removes target page and re-indexes remaining pages strictly contiguous', () {
      var session = BatchScanSession.startNew(documentId: 'remove_test');
      session = session.addPage(createSamplePage('remove_test', 0, pageId: 'A'));
      session = session.addPage(createSamplePage('remove_test', 1, pageId: 'B'));
      session = session.addPage(createSamplePage('remove_test', 2, pageId: 'C'));
      session = session.addPage(createSamplePage('remove_test', 3, pageId: 'D'));

      expect(session.pageCount, equals(4));

      // Remove middle page B
      session = session.removePage('B');

      expect(session.pageCount, equals(3));
      expect(session.pages.map((p) => p.id).toList(), equals(['A', 'C', 'D']));

      // Contiguous re-indexing verification
      expect(session.pages[0].position, equals(0));
      expect(session.pages[1].position, equals(1));
      expect(session.pages[2].position, equals(2));
    });

    test('reorderPages cleanly re-indexes positions for arbitrary permutation', () {
      var session = BatchScanSession.startNew(documentId: 'reorder_test');
      final pageA = createSamplePage('reorder_test', 0, pageId: 'A');
      final pageB = createSamplePage('reorder_test', 1, pageId: 'B');
      final pageC = createSamplePage('reorder_test', 2, pageId: 'C');
      session = session.addPage(pageA).addPage(pageB).addPage(pageC);

      // Reorder to [C, A, B]
      session = session.reorderPages([pageC, pageA, pageB]);

      expect(session.pageCount, equals(3));
      expect(session.pages[0].id, equals('C'));
      expect(session.pages[0].position, equals(0));
      expect(session.pages[1].id, equals('A'));
      expect(session.pages[1].position, equals(1));
      expect(session.pages[2].id, equals('B'));
      expect(session.pages[2].position, equals(2));
    });

    test('updatePage replaces page metadata while maintaining session order', () {
      var session = BatchScanSession.startNew(documentId: 'update_test');
      final p1 = createSamplePage('update_test', 0, pageId: 'page_1', rot: 0);
      final p2 = createSamplePage('update_test', 1, pageId: 'page_2', rot: 0);
      session = session.addPage(p1).addPage(p2);

      // Rotate page 1 by 90 degrees
      final rotatedP1 = p1.rotate90Clockwise();
      session = session.updatePage(rotatedP1);

      expect(session.pageCount, equals(2));
      expect(session.pages[0].rotationDegrees, equals(90));
      expect(session.pages[1].rotationDegrees, equals(0));
    });

    test('toDraftDocument and toSavedDocument transition document status correctly', () {
      var session = BatchScanSession.startNew(
        documentId: 'transition_doc_1',
        suggestedTitle: 'Contract_2026',
      );
      session = session.addPage(createSamplePage('transition_doc_1', 0));

      final draftDoc = session.toDraftDocument();
      expect(draftDoc.id, equals('transition_doc_1'));
      expect(draftDoc.status, equals(DocumentStatus.draft));
      expect(draftDoc.pageCount, equals(1));

      final savedDoc = session.toSavedDocument(confirmedTitle: 'Official_Contract');
      expect(savedDoc.id, equals('transition_doc_1'));
      expect(savedDoc.title, equals('Official_Contract'));
      expect(savedDoc.status, equals(DocumentStatus.saved));
      expect(savedDoc.pageCount, equals(1));
    });

    test('markCommitted resets dirty flag', () {
      var session = BatchScanSession.startNew(documentId: 'dirty_test');
      session = session.addPage(createSamplePage('dirty_test', 0));
      expect(session.isDirty, isTrue);

      session = session.markCommitted();
      expect(session.isDirty, isFalse);
    });

    test('serialization round-trip toMap and fromMap preserves session state', () {
      var session = BatchScanSession.startNew(
        documentId: 'serde_session',
        suggestedTitle: 'Receipts_May',
        flashMode: CameraFlashMode.on,
      );
      session = session.addPage(createSamplePage('serde_session', 0, pageId: 'p1'));
      session = session.addPage(createSamplePage('serde_session', 1, pageId: 'p2'));

      final map = session.toMap();
      final reconstructed = BatchScanSession.fromMap(map);

      expect(reconstructed.documentId, equals(session.documentId));
      expect(reconstructed.suggestedTitle, equals(session.suggestedTitle));
      expect(reconstructed.flashMode, equals(CameraFlashMode.on));
      expect(reconstructed.pageCount, equals(2));
      expect(reconstructed.pages[0].id, equals('p1'));
      expect(reconstructed.pages[1].id, equals('p2'));
    });
  });

  group('Tier 3: Atomic Draft Persistence & Simulated App Interruption', () {
    test('incremental atomic draft persistence preserves drafts upon simulated app termination', () async {
      const draftDocId = 'draft_interruption_001';
      var session = BatchScanSession.startNew(
        documentId: draftDocId,
        suggestedTitle: 'Scanned_Tax_Forms',
      );

      // --- Capture Page 1 & Persist Atomic Draft ---
      session = session.addPage(createSamplePage(draftDocId, 0, pageId: 'page_tax_1', rot: 0));
      final save1Result = await repository.saveDocumentAtomic(
        document: session.toDraftDocument(),
        pages: session.pages,
      );
      expect(save1Result.isSuccess, isTrue);
      session = session.markCommitted();

      // --- Capture Page 2 & Persist Atomic Draft ---
      session = session.addPage(createSamplePage(draftDocId, 1, pageId: 'page_tax_2', rot: 90));
      final save2Result = await repository.saveDocumentAtomic(
        document: session.toDraftDocument(),
        pages: session.pages,
      );
      expect(save2Result.isSuccess, isTrue);
      session = session.markCommitted();

      // --- Capture Page 3 & Persist Atomic Draft ---
      session = session.addPage(createSamplePage(draftDocId, 2, pageId: 'page_tax_3', rot: 180));
      final save3Result = await repository.saveDocumentAtomic(
        document: session.toDraftDocument(),
        pages: session.pages,
      );
      expect(save3Result.isSuccess, isTrue);
      session = session.markCommitted();

      // =======================================================================
      // SIMULATE APP INTERRUPTION / SUDDEN PROCESS KILL
      // =======================================================================
      // Close existing repository and dbHelper, simulating process termination
      await dbHelper.close();

      // Re-instantiate fresh cold-started repository pointing to the same SQLite database
      final freshDbHelper = DatabaseHelper(
        databaseFactory: databaseFactoryFfi,
        databasePath: dbPath,
      );
      final coldStartRepository = DocumentRepository(databaseHelper: freshDbHelper);

      // Verify active draft is detected on app launch
      final draftResult = await coldStartRepository.getActiveDraft();
      expect(draftResult.isSuccess, isTrue);
      final activeDraft = draftResult.dataOrNull;
      expect(activeDraft, isNotNull);
      expect(activeDraft!.id, equals(draftDocId));
      expect(activeDraft.title, equals('Scanned_Tax_Forms'));
      expect(activeDraft.status, equals(DocumentStatus.draft));
      expect(activeDraft.pageCount, equals(3));

      // Query persisted pages from SQLite to verify complete integrity
      final pagesResult = await coldStartRepository.getPagesForDocument(draftDocId);
      expect(pagesResult.isSuccess, isTrue);
      final draftPages = pagesResult.dataOrNull!;
      expect(draftPages.length, equals(3));

      expect(draftPages[0].id, equals('page_tax_1'));
      expect(draftPages[0].position, equals(0));
      expect(draftPages[0].rotationDegrees, equals(0));

      expect(draftPages[1].id, equals('page_tax_2'));
      expect(draftPages[1].position, equals(1));
      expect(draftPages[1].rotationDegrees, equals(90));

      expect(draftPages[2].id, equals('page_tax_3'));
      expect(draftPages[2].position, equals(2));
      expect(draftPages[2].rotationDegrees, equals(180));

      // User resumes session and commits document as SAVED
      final finalSavedDoc = activeDraft.copyWith(status: DocumentStatus.saved);
      final commitResult = await coldStartRepository.saveDocumentAtomic(
        document: finalSavedDoc,
        pages: draftPages,
      );
      expect(commitResult.isSuccess, isTrue);

      // Now active draft should be null (since status is now saved)
      final postCommitDraft = await coldStartRepository.getActiveDraft();
      expect(postCommitDraft.dataOrNull, isNull);

      await freshDbHelper.close();
    });

    test('discarding draft completely removes draft and all associated pages from SQLite', () async {
      const draftDocId = 'draft_to_discard';
      var session = BatchScanSession.startNew(documentId: draftDocId);
      session = session.addPage(createSamplePage(draftDocId, 0, pageId: 'p_disc_1'));
      session = session.addPage(createSamplePage(draftDocId, 1, pageId: 'p_disc_2'));

      await repository.saveDocumentAtomic(
        document: session.toDraftDocument(),
        pages: session.pages,
      );

      final activeBefore = await repository.getActiveDraft();
      expect(activeBefore.dataOrNull?.id, equals(draftDocId));

      // User discards draft
      final discardResult = await repository.discardDraft(draftDocId);
      expect(discardResult.isSuccess, isTrue);

      final activeAfter = await repository.getActiveDraft();
      expect(activeAfter.dataOrNull, isNull);

      final pagesAfter = await repository.getPagesForDocument(draftDocId);
      expect(pagesAfter.dataOrNull?.isEmpty, isTrue);
    });
  });
}
