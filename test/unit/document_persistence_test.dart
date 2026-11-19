import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:docerena/core/errors/result.dart';
import 'package:docerena/core/geometry/crop_polygon.dart';
import 'package:docerena/core/storage/file_storage_service.dart';
import 'package:docerena/data/database/database_helper.dart';
import 'package:docerena/data/repositories/document_repository.dart';
import 'package:docerena/domain/entities/document.dart';
import 'package:docerena/domain/entities/page_entity.dart';

void main() {
  // Initialize FFI for headless desktop/test SQLite execution
  sqfliteFfiInit();

  late Directory tempDir;
  late FileStorageService storageService;
  late DatabaseHelper dbHelper;
  late DocumentRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('docerena_test_');
    storageService = FileStorageService(basePath: tempDir.path);
    dbHelper = DatabaseHelper(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    repository = DocumentRepository(databaseHelper: dbHelper);
  });

  tearDown(() async {
    await dbHelper.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Atomic File Storage Service Tests', () {
    test('Tier 1: should write bytes atomically via .tmp and flush to disk', () async {
      final key = storageService.createOriginalKey('doc-1', 'page-1');
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);

      final writeResult = await storageService.writeAtomic(key, bytes);
      expect(writeResult.isSuccess, isTrue);

      final exists = await storageService.fileExists(key);
      expect(exists, isTrue);

      final readResult = await storageService.readFile(key);
      expect(readResult.isSuccess, isTrue);
      expect(readResult.dataOrNull, equals(bytes));
    });

    test('Tier 1: should safely copy external file into app-private sandbox', () async {
      final externalFile = File('${tempDir.path}/external_image.jpg');
      await externalFile.writeAsBytes([10, 20, 30, 40]);

      final destKey = storageService.createOriginalKey('doc-2', 'page-1');
      final copyResult = await storageService.copyToPrivateStorage(
        sourcePath: externalFile.path,
        destinationKey: destKey,
      );

      expect(copyResult.isSuccess, isTrue);
      final exists = await storageService.fileExists(destKey);
      expect(exists, isTrue);

      final readResult = await storageService.readFile(destKey);
      expect(readResult.dataOrNull, equals(Uint8List.fromList([10, 20, 30, 40])));
    });

    test('Tier 1: should delete file safely if it exists', () async {
      final key = storageService.createProcessedKey('doc-1', 'page-1');
      await storageService.writeAtomic(key, Uint8List.fromList([42]));

      expect(await storageService.fileExists(key), isTrue);

      final deleteResult = await storageService.deleteFile(key);
      expect(deleteResult.isSuccess, isTrue);
      expect(await storageService.fileExists(key), isFalse);
    });

    test('Tier 2: should refuse to write 0-byte file and return corruptedData error', () async {
      final key = storageService.createOriginalKey('doc-err', 'p-zero');
      final emptyBytes = Uint8List(0);

      final result = await storageService.writeAtomic(key, emptyBytes);
      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.code, equals(StorageErrorCode.corruptedData));
      expect(await storageService.fileExists(key), isFalse);
    });

    test('Tier 2: should throw ArgumentError on directory traversal attack in relative key', () {
      expect(
        () => storageService.resolveKey('../../etc/passwd'),
        throwsArgumentError,
      );
      expect(
        () => storageService.resolveKey('/absolute/path/attempt'),
        throwsArgumentError,
      );
    });

    test('Tier 2: should return fileNotFound error when reading non-existent file', () async {
      final readResult = await storageService.readFile('documents/nonexistent/page.jpg');
      expect(readResult.isFailure, isTrue);
      expect(readResult.errorOrNull?.code, equals(StorageErrorCode.fileNotFound));
    });
  });

  group('SQLite Database & Document Repository Tests', () {
    test('Tier 1: saveDocumentAtomic should commit document and ordered pages in transaction', () async {
      final doc = DocumentEntity(
        id: 'doc-alpha',
        title: 'Alpha Document',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        status: DocumentStatus.saved,
      );

      final pages = [
        PageEntity(
          id: 'p0',
          documentId: doc.id,
          position: 0,
          originalFileKey: 'documents/${doc.id}/pages/p0_orig.jpg',
          cropPolygon: CropPolygon.fullFrame(),
          pixelWidth: 1000,
          pixelHeight: 1500,
          createdAt: DateTime.now(),
        ),
        PageEntity(
          id: 'p1',
          documentId: doc.id,
          position: 1,
          originalFileKey: 'documents/${doc.id}/pages/p1_orig.jpg',
          cropPolygon: CropPolygon.fullFrame(),
          pixelWidth: 1000,
          pixelHeight: 1500,
          createdAt: DateTime.now(),
        ),
      ];

      final saveResult = await repository.saveDocumentAtomic(document: doc, pages: pages);
      expect(saveResult.isSuccess, isTrue);
      expect(saveResult.dataOrNull?.pageCount, equals(2));

      final fetchResult = await repository.getDocumentById(doc.id);
      expect(fetchResult.isSuccess, isTrue);
      expect(fetchResult.dataOrNull?.title, equals('Alpha Document'));
      expect(fetchResult.dataOrNull?.pageCount, equals(2));

      final pagesResult = await repository.getPagesForDocument(doc.id);
      expect(pagesResult.isSuccess, isTrue);
      expect(pagesResult.dataOrNull?.length, equals(2));
      expect(pagesResult.dataOrNull?[0].id, equals('p0'));
      expect(pagesResult.dataOrNull?[1].id, equals('p1'));
    });

    test('Tier 1: getAllDocuments orders documents by updatedAt DESC', () async {
      final docOlder = DocumentEntity(
        id: 'doc-old',
        title: 'Older Doc',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
        status: DocumentStatus.saved,
      );
      final docNewer = DocumentEntity(
        id: 'doc-new',
        title: 'Newer Doc',
        createdAt: DateTime.fromMillisecondsSinceEpoch(2000),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(5000),
        status: DocumentStatus.saved,
      );

      await repository.saveDocumentAtomic(document: docOlder, pages: []);
      await repository.saveDocumentAtomic(document: docNewer, pages: []);

      final listResult = await repository.getAllDocuments();
      expect(listResult.isSuccess, isTrue);
      final docs = listResult.dataOrNull!;
      expect(docs.length, equals(2));
      expect(docs[0].id, equals('doc-new'));
      expect(docs[1].id, equals('doc-old'));
    });

    test('Tier 1: renameDocument updates title and updatedAt timestamp', () async {
      final doc = DocumentEntity(
        id: 'doc-rename-test',
        title: 'Original Title',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        status: DocumentStatus.saved,
      );

      await repository.saveDocumentAtomic(document: doc, pages: []);

      final renameResult = await repository.renameDocument(doc.id, 'Renamed Title');
      expect(renameResult.isSuccess, isTrue);

      final fetched = await repository.getDocumentById(doc.id);
      expect(fetched.dataOrNull?.title, equals('Renamed Title'));
    });

    test('Tier 1: searchDocuments matches partial case-insensitive query', () async {
      final doc1 = DocumentEntity(
        id: 'doc-s1',
        title: 'Medical Invoice 2026',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        status: DocumentStatus.saved,
      );
      final doc2 = DocumentEntity(
        id: 'doc-s2',
        title: 'Apartment Lease Agreement',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        status: DocumentStatus.saved,
      );

      await repository.saveDocumentAtomic(document: doc1, pages: []);
      await repository.saveDocumentAtomic(document: doc2, pages: []);

      final searchResult = await repository.searchDocuments('invoice');
      expect(searchResult.isSuccess, isTrue);
      expect(searchResult.dataOrNull?.length, equals(1));
      expect(searchResult.dataOrNull?.first.id, equals('doc-s1'));

      final uppercaseSearch = await repository.searchDocuments('LEASE');
      expect(uppercaseSearch.isSuccess, isTrue);
      expect(uppercaseSearch.dataOrNull?.length, equals(1));
      expect(uppercaseSearch.dataOrNull?.first.id, equals('doc-s2'));
    });

    test('Tier 2: duplicate titles are disambiguated by unique UUID', () async {
      final docA = DocumentEntity(
        id: 'uuid-1',
        title: 'Receipt',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        status: DocumentStatus.saved,
      );
      final docB = DocumentEntity(
        id: 'uuid-2',
        title: 'Receipt',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now().add(const Duration(seconds: 1)),
        status: DocumentStatus.saved,
      );

      final resA = await repository.saveDocumentAtomic(document: docA, pages: []);
      final resB = await repository.saveDocumentAtomic(document: docB, pages: []);

      expect(resA.isSuccess, isTrue);
      expect(resB.isSuccess, isTrue);

      final allDocs = await repository.getAllDocuments();
      expect(allDocs.dataOrNull?.length, equals(2));
      expect(allDocs.dataOrNull?[0].title, equals('Receipt'));
      expect(allDocs.dataOrNull?[1].title, equals('Receipt'));
      expect(allDocs.dataOrNull?[0].id, isNot(equals(allDocs.dataOrNull?[1].id)));
    });

    test('Tier 2: extreme title characters (Unicode emoji and SQL injection attempts)', () async {
      const maliciousTitle = "Tax 🧾 2026 ' OR '1'='1'; DROP TABLE documents; --";
      final doc = DocumentEntity(
        id: 'doc-sql-test',
        title: maliciousTitle,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        status: DocumentStatus.saved,
      );

      final saveRes = await repository.saveDocumentAtomic(document: doc, pages: []);
      expect(saveRes.isSuccess, isTrue);

      final fetched = await repository.getDocumentById(doc.id);
      expect(fetched.dataOrNull?.title, equals(maliciousTitle));

      // Verify table is intact
      final allDocs = await repository.getAllDocuments();
      expect(allDocs.isSuccess, isTrue);
    });

    test('Tier 2: foreign key cascade deletes associated pages on document deletion', () async {
      final doc = DocumentEntity(
        id: 'doc-cascade',
        title: 'To Be Deleted',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        status: DocumentStatus.saved,
      );

      final page = PageEntity(
        id: 'p-cascade',
        documentId: doc.id,
        position: 0,
        originalFileKey: 'documents/${doc.id}/pages/p_orig.jpg',
        cropPolygon: CropPolygon.fullFrame(),
        pixelWidth: 500,
        pixelHeight: 500,
        createdAt: DateTime.now(),
      );

      await repository.saveDocumentAtomic(document: doc, pages: [page]);

      // Confirm page exists
      final pagesBefore = await repository.getPagesForDocument(doc.id);
      expect(pagesBefore.dataOrNull?.length, equals(1));

      // Delete document
      final delRes = await repository.deleteDocument(doc.id);
      expect(delRes.isSuccess, isTrue);

      // Verify document is gone
      final docAfter = await repository.getDocumentById(doc.id);
      expect(docAfter.dataOrNull, isNull);

      // Verify page was cascade deleted by SQLite
      final pagesAfter = await repository.getPagesForDocument(doc.id);
      expect(pagesAfter.dataOrNull, isEmpty);
    });

    test('Tier 3: draft persistence and cold restart recovery', () async {
      final draftDoc = DocumentEntity(
        id: 'draft-doc-1',
        title: 'Draft Scan',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        status: DocumentStatus.draft,
      );

      final draftPage = PageEntity(
        id: 'dp1',
        documentId: draftDoc.id,
        position: 0,
        originalFileKey: 'documents/${draftDoc.id}/pages/dp1_orig.jpg',
        cropPolygon: const CropPolygon(
          topLeft: Point2D(0.1, 0.1),
          topRight: Point2D(0.9, 0.1),
          bottomRight: Point2D(0.9, 0.9),
          bottomLeft: Point2D(0.1, 0.9),
        ),
        pixelWidth: 1080,
        pixelHeight: 1920,
        createdAt: DateTime.now(),
      );

      await repository.saveDocumentAtomic(document: draftDoc, pages: [draftPage]);

      // Draft must not appear in saved document list
      final savedDocs = await repository.getAllDocuments();
      expect(savedDocs.dataOrNull, isEmpty);

      // Draft must be detected by startup draft check
      final activeDraft = await repository.getActiveDraft();
      expect(activeDraft.isSuccess, isTrue);
      expect(activeDraft.dataOrNull?.id, equals('draft-doc-1'));
      expect(activeDraft.dataOrNull?.isDraft, isTrue);

      final draftPages = await repository.getPagesForDocument(draftDoc.id);
      expect(draftPages.dataOrNull?.length, equals(1));
      expect(draftPages.dataOrNull?.first.cropPolygon.topLeft.x, closeTo(0.1, 1e-5));
    });

    test('Tier 3: discard draft cleans up draft and removes it from active draft detection', () async {
      final draftDoc = DocumentEntity(
        id: 'draft-doc-discard',
        title: 'Draft to discard',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        status: DocumentStatus.draft,
      );

      await repository.saveDocumentAtomic(document: draftDoc, pages: []);
      expect((await repository.getActiveDraft()).dataOrNull, isNotNull);

      final discardRes = await repository.discardDraft(draftDoc.id);
      expect(discardRes.isSuccess, isTrue);

      final activeDraftAfter = await repository.getActiveDraft();
      expect(activeDraftAfter.dataOrNull, isNull);
    });
  });
}
