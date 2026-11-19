import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:docerena/core/errors/result.dart';
import 'package:docerena/core/geometry/crop_polygon.dart';
import 'package:docerena/core/interfaces/i_document_repository.dart';
import 'package:docerena/domain/entities/document.dart';
import 'package:docerena/domain/entities/page_entity.dart';
import 'package:docerena/presentation/screens/s02_home/home_screen.dart';
import 'package:docerena/presentation/screens/s06_organizer/page_organizer_screen.dart';
import 'package:docerena/presentation/widgets/docerena_empty_state.dart';
import 'package:docerena/presentation/widgets/document_card.dart';

class FakeDocumentRepository implements IDocumentRepository {
  final Map<String, DocumentEntity> documents = {};
  final Map<String, List<PageEntity>> pages = {};

  @override
  Future<Result<List<DocumentEntity>, StorageError>> getAllDocuments() async {
    return Result.ok(documents.values.where((d) => !d.isDeleted).toList());
  }

  @override
  Future<Result<DocumentEntity?, StorageError>> getDocumentById(String id) async {
    return Result.ok(documents[id]);
  }

  @override
  Future<Result<List<PageEntity>, StorageError>> getPagesForDocument(String documentId) async {
    return Result.ok(pages[documentId] ?? []);
  }

  @override
  Future<Result<DocumentEntity, StorageError>> saveDocumentAtomic({
    required DocumentEntity document,
    required List<PageEntity> pages,
  }) async {
    documents[document.id] = document;
    this.pages[document.id] = pages;
    return Result.ok(document);
  }

  @override
  Future<Result<void, StorageError>> deleteDocument(String id) async {
    documents.remove(id);
    pages.remove(id);
    return const Result.ok(null);
  }

  @override
  Future<Result<void, StorageError>> renameDocument(String id, String newTitle) async {
    if (documents.containsKey(id)) {
      documents[id] = documents[id]!.copyWith(title: newTitle);
    }
    return const Result.ok(null);
  }

  @override
  Future<Result<List<DocumentEntity>, StorageError>> searchDocuments(String query) async {
    return Result.ok(
      documents.values
          .where((d) => !d.isDeleted && d.title.toLowerCase().contains(query.toLowerCase()))
          .toList(),
    );
  }

  @override
  Future<Result<DocumentEntity?, StorageError>> getActiveDraft() async {
    return const Result.ok(null);
  }

  @override
  Future<Result<void, StorageError>> discardDraft(String draftId) async {
    return const Result.ok(null);
  }
}

void main() {
  group('Home Screen Widgets & States Tests (S02)', () {
    testWidgets('Tier 1: empty document state displays informative prompt and scan action', (tester) async {
      final repo = FakeDocumentRepository();
      bool scanTriggered = false;

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            repository: repo,
            onScanNewDocument: () {
              scanTriggered = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(DocerenaEmptyState), findsOneWidget);
      expect(find.text('No documents yet'), findsOneWidget);
      expect(
        find.text('Capture pages using your camera or import photos from your device.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('home_scan_fab')), findsOneWidget);

      await tester.tap(find.byKey(const Key('home_scan_fab')));
      await tester.pump();
      expect(scanTriggered, isTrue);
    });

    testWidgets('Tier 1: empty search state informs user when no documents match query', (tester) async {
      final repo = FakeDocumentRepository();
      final doc = DocumentEntity(
        id: 'doc-1',
        title: 'Quarterly Report',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        pageCount: 2,
      );
      repo.documents[doc.id] = doc;

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap search icon in app bar
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();

      // Enter search text
      await tester.enterText(find.byType(TextField), 'NonExistentInvoice');
      await tester.pumpAndSettle();

      expect(find.byType(DocerenaEmptySearchState), findsOneWidget);
      expect(find.text('No documents found for "NonExistentInvoice"'), findsOneWidget);
      expect(find.byIcon(Icons.search_off), findsOneWidget);
    });

    testWidgets('Tier 1: document card displays title, page badge, and updated time', (tester) async {
      bool opened = false;
      final doc = DocumentEntity(
        id: 'doc-1',
        title: 'Quarterly Report 2026',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now().subtract(const Duration(minutes: 5)),
        pageCount: 4,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentCard(
              document: doc,
              onTap: () {
                opened = true;
              },
            ),
          ),
        ),
      );

      expect(find.byType(DocumentCard), findsOneWidget);
      expect(find.text('Quarterly Report 2026'), findsOneWidget);
      expect(find.text('4 Pages'), findsOneWidget);
      expect(find.text('5m ago'), findsOneWidget);

      await tester.tap(find.byType(DocumentCard));
      await tester.pump();
      expect(opened, isTrue);
    });
  });

  group('Page Organizer Widgets & Actions Tests (S06)', () {
    testWidgets('Tier 1: page thumbnail card displays position badge and action buttons', (tester) async {
      final repo = FakeDocumentRepository();
      final pages = [
        const PageEntity(
          id: 'page-1',
          documentId: 'doc-1',
          position: 0,
          originalFileKey: '/test/page1.jpg',
          cropPolygon: CropPolygon.fullFrame(),
          rotationDegrees: 0,
          filter: PageFilter.original,
          brightness: 0.0,
          contrast: 0.0,
          pixelWidth: 1080,
          pixelHeight: 1920,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: PageOrganizerScreen(
            initialPages: pages,
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PageOrganizerScreen), findsOneWidget);
      expect(find.byKey(const Key('page_badge_0')), findsOneWidget);
      expect(find.text('1'), findsWidgets);

      // Rotate page
      final rotateBtn = find.byKey(const Key('rotate_page_btn_0'));
      expect(rotateBtn, findsOneWidget);
      await tester.tap(rotateBtn);
      await tester.pumpAndSettle();
    });

    testWidgets('Tier 1 & Tier 2: delete page triggers confirmation dialog before removal', (tester) async {
      final repo = FakeDocumentRepository();
      final pages = [
        const PageEntity(
          id: 'page-1',
          documentId: 'doc-1',
          position: 0,
          originalFileKey: '/test/page1.jpg',
          cropPolygon: CropPolygon.fullFrame(),
          rotationDegrees: 0,
          filter: PageFilter.original,
          brightness: 0.0,
          contrast: 0.0,
          pixelWidth: 1080,
          pixelHeight: 1920,
        ),
        const PageEntity(
          id: 'page-2',
          documentId: 'doc-1',
          position: 1,
          originalFileKey: '/test/page2.jpg',
          cropPolygon: CropPolygon.fullFrame(),
          rotationDegrees: 0,
          filter: PageFilter.original,
          brightness: 0.0,
          contrast: 0.0,
          pixelWidth: 1080,
          pixelHeight: 1920,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: PageOrganizerScreen(
            initialPages: pages,
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Tap delete button on page 0
      final deleteBtn = find.byKey(const Key('delete_page_btn_0'));
      expect(deleteBtn, findsOneWidget);
      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      // Verify dialog appears
      expect(find.byKey(const Key('delete_page_dialog')), findsOneWidget);
      expect(find.text('Delete Page 1?'), findsOneWidget);

      // 2. Tap cancel button
      await tester.tap(find.byKey(const Key('dialog_cancel_btn')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('delete_page_dialog')), findsNothing);
      expect(find.byKey(const Key('page_card_0')), findsOneWidget);
      expect(find.byKey(const Key('page_card_1')), findsOneWidget);

      // 3. Tap delete button again and confirm
      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('dialog_confirm_btn')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('delete_page_dialog')), findsNothing);
      // Only 1 page remains now
      expect(find.byKey(const Key('page_card_0')), findsOneWidget);
      expect(find.byKey(const Key('page_card_1')), findsNothing);
    });
  });
}
