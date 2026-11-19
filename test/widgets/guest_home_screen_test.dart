import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:camscanner/core/interfaces/i_document_repository.dart';
import 'package:camscanner/core/interfaces/i_file_storage_service.dart';
import 'package:camscanner/core/storage/file_storage_service.dart';
import 'package:camscanner/data/database/database_helper.dart';
import 'package:camscanner/data/repositories/document_repository.dart';
import 'package:camscanner/domain/entities/document.dart';
import 'package:camscanner/domain/entities/page_entity.dart';
import 'package:camscanner/presentation/screens/s02_home/guest_home_screen.dart';

/// In-memory mock repository for testing GuestHomeScreen
class MockGuestDocumentRepository implements IDocumentRepository {
  List<DocumentEntity> docs = [];

  @override
  Future<Result<List<DocumentEntity>>> getAllDocuments() async => Result.success(docs);

  @override
  Future<Result<DocumentEntity?>> getDocumentById(String id) async {
    final match = docs.where((d) => d.id == id).firstOrNull;
    return Result.success(match);
  }

  @override
  Future<Result<DocumentEntity>> createDocument({required String title}) async {
    final newDoc = DocumentEntity(
      id: 'doc_${docs.length + 1}',
      title: title,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      pageCount: 0,
      fileSizeBytes: 0,
    );
    docs.add(newDoc);
    return Result.success(newDoc);
  }

  @override
  Future<Result<void>> renameDocument(String id, String newTitle) async {
    final idx = docs.indexWhere((d) => d.id == id);
    if (idx != -1) {
      docs[idx] = docs[idx].copyWith(title: newTitle);
    }
    return Result.success(null);
  }

  @override
  Future<Result<void>> deleteDocument(String id) async {
    docs.removeWhere((d) => d.id == id);
    return Result.success(null);
  }

  @override
  Future<Result<List<PageEntity>>> getPagesForDocument(String documentId) async => Result.success([]);

  @override
  Future<Result<PageEntity>> addPageToDocument(String documentId, ScannedImage scannedImage) async {
    throw UnimplementedError();
  }

  @override
  Future<Result<void>> reorderPages(String documentId, List<String> pageIdsInOrder) async => Result.success(null);

  @override
  Future<Result<void>> deletePage(String pageId) async => Result.success(null);

  @override
  Future<Result<void>> updatePageCropAndFilters(String pageId, {dynamic cropPolygon, dynamic filterType, int? rotationDegrees}) async => Result.success(null);

  @override
  Future<Result<DocumentEntity?>> getActiveDraft() async => Result.success(null);

  @override
  Future<Result<void>> saveActiveDraft(DocumentEntity draft) async => Result.success(null);

  @override
  Future<Result<void>> discardDraft(String draftId) async => Result.success(null);
}

void main() {
  group('GuestHomeScreen Widget Tests (media_1794214879715_005de41f.jpg)', () {
    late MockGuestDocumentRepository mockRepo;

    setUp(() {
      mockRepo = MockGuestDocumentRepository();
    });

    testWidgets('Configures real Android system bars & SafeArea', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GuestHomeScreen(repository: mockRepo),
        ),
      );
      await tester.pumpAndSettle();

      final annotatedRegion = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
      );
      expect(annotatedRegion.value.statusBarColor, Colors.transparent);
      expect(annotatedRegion.value.statusBarIconBrightness, Brightness.dark);
      expect(find.byType(SafeArea), findsAtLeastNWidgets(1));
    });

    testWidgets('Shows exact empty state when 0 documents exist in repository', (tester) async {
      mockRepo.docs = [];

      await tester.pumpWidget(
        MaterialApp(
          home: GuestHomeScreen(repository: mockRepo),
        ),
      );
      await tester.pumpAndSettle();

      // Heading and Subheading
      expect(find.text('Your documents'), findsOneWidget);
      expect(find.text('Ready when you are.'), findsOneWidget);

      // Empty State elements
      expect(find.text('No documents yet'), findsOneWidget);
      expect(find.text('Your scans will appear here.'), findsOneWidget);
    });

    testWidgets('Shows real documents when repository has saved files (no mock files)', (tester) async {
      mockRepo.docs = [
        DocumentEntity(
          id: 'doc_1',
          title: 'Invoice_April_2026.pdf',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          pageCount: 3,
          fileSizeBytes: 1024 * 450,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: GuestHomeScreen(repository: mockRepo),
        ),
      );
      await tester.pumpAndSettle();

      // Empty state is hidden
      expect(find.text('No documents yet'), findsNothing);

      // Real document is rendered
      expect(find.text('Invoice_April_2026.pdf'), findsOneWidget);
      expect(find.byKey(const Key('guest_doc_card_doc_1')), findsOneWidget);
    });

    testWidgets('Hero banner Scan and Import buttons trigger callbacks', (tester) async {
      bool scanTriggered = false;
      bool importTriggered = false;

      await tester.pumpWidget(
        MaterialApp(
          home: GuestHomeScreen(
            repository: mockRepo,
            onScanNewDocument: () => scanTriggered = true,
            onImportPhotos: () => importTriggered = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('guest_hero_scan_btn')));
      await tester.pumpAndSettle();
      expect(scanTriggered, isTrue);

      await tester.tap(find.byKey(const Key('guest_hero_import_btn')));
      await tester.pumpAndSettle();
      expect(importTriggered, isTrue);
    });

    testWidgets('Sign action card reports pending status without pretending it works', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GuestHomeScreen(repository: mockRepo),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('guest_action_sign_card')), findsOneWidget);
      expect(find.text('Soon'), findsOneWidget);

      await tester.tap(find.byKey(const Key('guest_action_sign_card')));
      await tester.pump();

      expect(find.text('Digital Signatures will be available in a future update.'), findsOneWidget);
    });

    testWidgets('App Bottom Navigation Bar contains Home, Documents, Tools, Settings', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GuestHomeScreen(repository: mockRepo),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Documents'), findsOneWidget);
      expect(find.text('Tools'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });
  });
}
