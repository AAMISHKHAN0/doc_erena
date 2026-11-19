import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:docerena/core/errors/result.dart';
import 'package:docerena/core/geometry/crop_polygon.dart';
import 'package:docerena/core/interfaces/i_document_repository.dart';
import 'package:docerena/core/interfaces/i_document_scanner.dart';
import 'package:docerena/domain/entities/document.dart';
import 'package:docerena/domain/entities/page_entity.dart';
import 'package:docerena/presentation/screens/s06_organizer/page_organizer_screen.dart';

class MockDocumentRepository implements IDocumentRepository {
  final Map<String, DocumentEntity> documents = {};
  final Map<String, List<PageEntity>> pages = {};

  @override
  Future<Result<List<DocumentEntity>, StorageError>> getAllDocuments() async {
    return Success(documents.values.toList());
  }

  @override
  Future<Result<DocumentEntity?, StorageError>> getDocumentById(String id) async {
    return Success(documents[id]);
  }

  @override
  Future<Result<List<PageEntity>, StorageError>> getPagesForDocument(String documentId) async {
    return Success(pages[documentId] ?? []);
  }

  @override
  Future<Result<DocumentEntity, StorageError>> saveDocumentAtomic({
    required DocumentEntity document,
    required List<PageEntity> pages,
  }) async {
    documents[document.id] = document;
    this.pages[document.id] = pages;
    return Success(document);
  }

  @override
  Future<Result<void, StorageError>> deleteDocument(String id) async {
    documents.remove(id);
    pages.remove(id);
    return const Success(null);
  }

  @override
  Future<Result<void, StorageError>> renameDocument(String id, String newTitle) async {
    if (documents.containsKey(id)) {
      documents[id] = documents[id]!.copyWith(title: newTitle);
    }
    return const Success(null);
  }

  @override
  Future<Result<List<DocumentEntity>, StorageError>> searchDocuments(String query) async {
    return Success(
      documents.values.where((d) => d.title.toLowerCase().contains(query.toLowerCase())).toList(),
    );
  }

  @override
  Future<Result<DocumentEntity?, StorageError>> getActiveDraft() async {
    return const Success(null);
  }

  @override
  Future<Result<void, StorageError>> discardDraft(String draftId) async {
    documents.remove(draftId);
    pages.remove(draftId);
    return const Success(null);
  }
}

PageEntity createPage(int index, {int rotation = 0, String docId = 'doc_test'}) {
  return PageEntity(
    id: 'page_$index',
    documentId: docId,
    position: index,
    originalFileKey: 'documents/$docId/pages/page_${index}_orig.jpg',
    cropPolygon: const CropPolygon(
      topLeft: Point2D(0.0, 0.0),
      topRight: Point2D(1.0, 0.0),
      bottomRight: Point2D(1.0, 1.0),
      bottomLeft: Point2D(0.0, 1.0),
    ),
    rotationDegrees: rotation,
    pixelWidth: 800,
    pixelHeight: 1200,
    createdAt: DateTime.now(),
  );
}

void main() {
  late MockDocumentRepository mockRepo;

  setUp(() {
    mockRepo = MockDocumentRepository();
  });

  Widget buildOrganizerHarness({
    required List<PageEntity> pages,
    ValueChanged<List<PageEntity>>? onPagesChanged,
    ValueChanged<DocumentEntity>? onSaveDocument,
    Future<ScannedImage?> Function(PageEntity page)? onRetakePage,
    Future<ScannedImage?> Function()? onAddPageCamera,
    Future<List<ScannedImage>?> Function()? onAddPageGallery,
    VoidCallback? onDiscardDraft,
  }) {
    return MaterialApp(
      home: PageOrganizerScreen(
        initialPages: pages,
        repository: mockRepo,
        onPagesChanged: onPagesChanged,
        onSaveDocument: onSaveDocument,
        onRetakePage: onRetakePage,
        onAddPageCamera: onAddPageCamera,
        onAddPageGallery: onAddPageGallery,
        onDiscardDraft: onDiscardDraft,
      ),
    );
  }

  group('PageOrganizerScreen - Grid Rendering & Badges', () {
    testWidgets('renders grid with sequential 1..N page badges', (tester) async {
      final initialPages = [
        createPage(0),
        createPage(1),
        createPage(2),
      ];

      await tester.pumpWidget(buildOrganizerHarness(pages: initialPages));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('page_organizer_screen')), findsOneWidget);
      expect(find.text('Organize Pages (3)'), findsOneWidget);

      // Verify badges 1, 2, 3
      expect(find.byKey(const Key('page_badge_0')), findsOneWidget);
      expect(find.byKey(const Key('page_badge_1')), findsOneWidget);
      expect(find.byKey(const Key('page_badge_2')), findsOneWidget);

      expect(find.text('1'), findsWidgets);
      expect(find.text('2'), findsWidgets);
      expect(find.text('3'), findsWidgets);
    });
  });

  group('PageOrganizerScreen - Accessible Reordering', () {
    testWidgets('Move Up on index 0 is disabled, Move Down on index N-1 is disabled', (tester) async {
      final initialPages = [
        createPage(0),
        createPage(1),
      ];

      await tester.pumpWidget(buildOrganizerHarness(pages: initialPages));
      await tester.pumpAndSettle();

      final moveUp0 = tester.widget<IconButton>(find.byKey(const Key('move_up_btn_0')));
      expect(moveUp0.onPressed, isNull, reason: 'Index 0 Move Up must be disabled');

      final moveDown1 = tester.widget<IconButton>(find.byKey(const Key('move_down_btn_1')));
      expect(moveDown1.onPressed, isNull, reason: 'Index N-1 Move Down must be disabled');

      // Index 1 Move Up is enabled
      final moveUp1 = tester.widget<IconButton>(find.byKey(const Key('move_up_btn_1')));
      expect(moveUp1.onPressed, isNotNull);

      // Index 0 Move Down is enabled
      final moveDown0 = tester.widget<IconButton>(find.byKey(const Key('move_down_btn_0')));
      expect(moveDown0.onPressed, isNotNull);
    });

    testWidgets('tapping Move Up swaps page with predecessor and reindexes', (tester) async {
      List<PageEntity>? updatedPages;
      final initialPages = [
        createPage(0),
        createPage(1),
      ];

      await tester.pumpWidget(
        buildOrganizerHarness(
          pages: initialPages,
          onPagesChanged: (pages) => updatedPages = pages,
        ),
      );
      await tester.pumpAndSettle();

      // Tap Move Up on page 1 (second page)
      await tester.tap(find.byKey(const Key('move_up_btn_1')));
      await tester.pumpAndSettle();

      expect(updatedPages, isNotNull);
      expect(updatedPages!.length, equals(2));
      expect(updatedPages![0].id, equals('page_1'));
      expect(updatedPages![0].position, equals(0));
      expect(updatedPages![1].id, equals('page_0'));
      expect(updatedPages![1].position, equals(1));
    });

    testWidgets('tapping Move Down swaps page with successor and reindexes', (tester) async {
      List<PageEntity>? updatedPages;
      final initialPages = [
        createPage(0),
        createPage(1),
      ];

      await tester.pumpWidget(
        buildOrganizerHarness(
          pages: initialPages,
          onPagesChanged: (pages) => updatedPages = pages,
        ),
      );
      await tester.pumpAndSettle();

      // Tap Move Down on page 0 (first page)
      await tester.tap(find.byKey(const Key('move_down_btn_0')));
      await tester.pumpAndSettle();

      expect(updatedPages, isNotNull);
      expect(updatedPages![0].id, equals('page_1'));
      expect(updatedPages![0].position, equals(0));
      expect(updatedPages![1].id, equals('page_0'));
      expect(updatedPages![1].position, equals(1));
    });
  });

  group('PageOrganizerScreen - Page Rotation', () {
    testWidgets('tapping rotate button rotates page 90 degrees clockwise', (tester) async {
      List<PageEntity>? updatedPages;
      final initialPages = [
        createPage(0, rotation: 0),
      ];

      await tester.pumpWidget(
        buildOrganizerHarness(
          pages: initialPages,
          onPagesChanged: (pages) => updatedPages = pages,
        ),
      );
      await tester.pumpAndSettle();

      // Tap rotate button on page 0
      await tester.tap(find.byKey(const Key('rotate_page_btn_0')));
      await tester.pumpAndSettle();

      expect(updatedPages, isNotNull);
      expect(updatedPages![0].rotationDegrees, equals(90));
      expect(find.text('90°'), findsOneWidget);

      // Rotate again: 90 -> 180
      await tester.tap(find.byKey(const Key('rotate_page_btn_0')));
      await tester.pumpAndSettle();

      expect(updatedPages![0].rotationDegrees, equals(180));
      expect(find.text('180°'), findsOneWidget);
    });
  });

  group('PageOrganizerScreen - Retake Page Contract', () {
    testWidgets('retake commits replacement ONLY after user accepts new image', (tester) async {
      List<PageEntity>? updatedPages;
      final initialPages = [
        createPage(0),
      ];

      // 1. User accepts new image
      await tester.pumpWidget(
        buildOrganizerHarness(
          pages: initialPages,
          onPagesChanged: (pages) => updatedPages = pages,
          onRetakePage: (page) async {
            return ScannedImage(
              imagePath: 'documents/doc_test/pages/replacement_orig.jpg',
              pixelWidth: 1000,
              pixelHeight: 1500,
              capturedAt: DateTime.now(),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('retake_page_btn_0')));
      await tester.pumpAndSettle();

      expect(updatedPages, isNotNull);
      expect(updatedPages![0].originalFileKey, equals('documents/doc_test/pages/replacement_orig.jpg'));
      expect(updatedPages![0].pixelWidth, equals(1000));
      expect(updatedPages![0].pixelHeight, equals(1500));
    });

    testWidgets('retake cancellation preserves original image without alteration', (tester) async {
      List<PageEntity>? updatedPages;
      final initialPages = [
        createPage(0),
      ];

      // 2. User cancels retake (returns null)
      await tester.pumpWidget(
        buildOrganizerHarness(
          pages: initialPages,
          onPagesChanged: (pages) => updatedPages = pages,
          onRetakePage: (page) async => null,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('retake_page_btn_0')));
      await tester.pumpAndSettle();

      expect(updatedPages, isNull, reason: 'Original page must remain untouched on retake cancel');
    });
  });

  group('PageOrganizerScreen - Delete Page Contract', () {
    testWidgets('delete button displays confirmation dialog; cancel preserves page', (tester) async {
      final initialPages = [
        createPage(0),
        createPage(1),
      ];

      await tester.pumpWidget(buildOrganizerHarness(pages: initialPages));
      await tester.pumpAndSettle();

      // Tap delete on Page 1
      await tester.tap(find.byKey(const Key('delete_page_btn_0')));
      await tester.pumpAndSettle();

      // Dialog is visible
      expect(find.byKey(const Key('delete_page_dialog')), findsOneWidget);
      expect(find.text('Delete Page 1?'), findsOneWidget);

      // Tap cancel
      await tester.tap(find.byKey(const Key('dialog_cancel_btn')));
      await tester.pumpAndSettle();

      // Dialog dismissed, both pages remain
      expect(find.byKey(const Key('delete_page_dialog')), findsNothing);
      expect(find.text('Organize Pages (2)'), findsOneWidget);
    });

    testWidgets('confirming delete removes page and re-indexes remaining pages strictly 0..N-1', (tester) async {
      List<PageEntity>? updatedPages;
      final initialPages = [
        createPage(0),
        createPage(1),
        createPage(2),
      ];

      await tester.pumpWidget(
        buildOrganizerHarness(
          pages: initialPages,
          onPagesChanged: (pages) => updatedPages = pages,
        ),
      );
      await tester.pumpAndSettle();

      // Delete middle page (Page 2, index 1)
      await tester.tap(find.byKey(const Key('delete_page_btn_1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('dialog_confirm_btn')));
      await tester.pumpAndSettle();

      expect(updatedPages, isNotNull);
      expect(updatedPages!.length, equals(2));
      expect(updatedPages![0].id, equals('page_0'));
      expect(updatedPages![0].position, equals(0));
      expect(updatedPages![1].id, equals('page_2'));
      expect(updatedPages![1].position, equals(1));
    });

    testWidgets('deleting last remaining page warns about discarding draft', (tester) async {
      bool draftDiscarded = false;
      final initialPages = [
        createPage(0),
      ];

      await tester.pumpWidget(
        buildOrganizerHarness(
          pages: initialPages,
          onDiscardDraft: () => draftDiscarded = true,
        ),
      );
      await tester.pumpAndSettle();

      // Delete the only page
      await tester.tap(find.byKey(const Key('delete_page_btn_0')));
      await tester.pumpAndSettle();

      // Dialog warns about draft discard
      expect(find.text('Discard Draft?'), findsOneWidget);
      expect(find.textContaining('discard the current document draft'), findsOneWidget);

      await tester.tap(find.byKey(const Key('dialog_confirm_btn')));
      await tester.pumpAndSettle();

      expect(draftDiscarded, isTrue);
    });
  });

  group('PageOrganizerScreen - Append Page Flow', () {
    testWidgets('Add Page button opens choice modal and appends new page', (tester) async {
      List<PageEntity>? updatedPages;
      final initialPages = [
        createPage(0),
      ];

      await tester.pumpWidget(
        buildOrganizerHarness(
          pages: initialPages,
          onPagesChanged: (pages) => updatedPages = pages,
          onAddPageCamera: () async {
            return ScannedImage(
              imagePath: 'documents/doc_test/pages/new_page_orig.jpg',
              pixelWidth: 800,
              pixelHeight: 1200,
              capturedAt: DateTime.now(),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      // Tap Add Page button
      await tester.tap(find.byKey(const Key('add_page_btn')));
      await tester.pumpAndSettle();

      // Modal options visible
      expect(find.text('Add Page to Document'), findsOneWidget);
      expect(find.byKey(const Key('add_page_camera_option')), findsOneWidget);
      expect(find.byKey(const Key('add_page_gallery_option')), findsOneWidget);

      // Tap camera option
      await tester.tap(find.byKey(const Key('add_page_camera_option')));
      await tester.pumpAndSettle();

      expect(updatedPages, isNotNull);
      expect(updatedPages!.length, equals(2));
      expect(updatedPages![0].id, equals('page_0'));
      expect(updatedPages![0].position, equals(0));
      expect(updatedPages![1].position, equals(1));
      expect(updatedPages![1].originalFileKey, equals('documents/doc_test/pages/new_page_orig.jpg'));
    });
  });

  group('PageOrganizerScreen - Save Document Button', () {
    testWidgets('Save Document button is present and enabled when pages exist', (tester) async {
      final initialPages = [
        createPage(0),
      ];

      await tester.pumpWidget(buildOrganizerHarness(pages: initialPages));
      await tester.pumpAndSettle();

      final saveBtn = find.byKey(const Key('save_document_btn'));
      expect(saveBtn, findsOneWidget);

      // Tap Save Document button -> opens Save Document Dialog
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('save_document_dialog')), findsOneWidget);
    });
  });
}
