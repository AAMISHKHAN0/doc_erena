import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:docerena/core/errors/result.dart';
import 'package:docerena/core/geometry/crop_polygon.dart';
import 'package:docerena/core/interfaces/i_document_repository.dart';
import 'package:docerena/domain/entities/document.dart';
import 'package:docerena/domain/entities/page_entity.dart';
import 'package:docerena/presentation/screens/s06_organizer/page_organizer_screen.dart';
import 'package:docerena/presentation/widgets/accessible_touch_target.dart';
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
  group('Accessibility & TalkBack Semantics Tests (QA-07 & WCAG 2.1 AA)', () {
    testWidgets('Tier 1: Camera shutter button has accessible TalkBack label and >= 48x48dp target', (tester) async {
      final handle = tester.ensureSemantics();

      bool shutterTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AccessibleTouchTarget(
                minWidth: 76.0,
                minHeight: 76.0,
                semanticLabel: 'Capture document page',
                semanticHint: 'Take photo of current page',
                isButton: true,
                onTap: () {
                  shutterTapped = true;
                },
                child: const SizedBox(
                  key: Key('shutter_icon'),
                  width: 64,
                  height: 64,
                  child: Icon(Icons.camera_alt),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(AccessibleTouchTarget), findsOneWidget);

      // Verify semantics
      expect(
        tester.getSemantics(find.byType(AccessibleTouchTarget)),
        matchesSemantics(
          label: 'Capture document page',
          hint: 'Take photo of current page',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );

      // Verify dimensions >= 48x48 dp
      final renderBox = tester.getRect(find.byType(AccessibleTouchTarget));
      expect(renderBox.width, greaterThanOrEqualTo(48.0));
      expect(renderBox.height, greaterThanOrEqualTo(48.0));

      await tester.tap(find.byType(AccessibleTouchTarget));
      await tester.pump();
      expect(shutterTapped, isTrue);

      handle.dispose();
    });

    testWidgets('Tier 1: 4 corner crop handles have individual semantic labels and >= 48x48dp touch targets', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: 20,
                  top: 20,
                  child: AccessibleTouchTarget(
                    key: const Key('corner_tl'),
                    semanticLabel: 'Top-Left crop corner handle',
                    semanticHint: 'Drag to adjust upper-left boundary',
                    onTap: () {},
                    child: Container(width: 24, height: 24, color: Colors.blue),
                  ),
                ),
                Positioned(
                  right: 20,
                  top: 20,
                  child: AccessibleTouchTarget(
                    key: const Key('corner_tr'),
                    semanticLabel: 'Top-Right crop corner handle',
                    semanticHint: 'Drag to adjust upper-right boundary',
                    onTap: () {},
                    child: Container(width: 24, height: 24, color: Colors.blue),
                  ),
                ),
                Positioned(
                  right: 20,
                  bottom: 20,
                  child: AccessibleTouchTarget(
                    key: const Key('corner_br'),
                    semanticLabel: 'Bottom-Right crop corner handle',
                    semanticHint: 'Drag to adjust lower-right boundary',
                    onTap: () {},
                    child: Container(width: 24, height: 24, color: Colors.blue),
                  ),
                ),
                Positioned(
                  left: 20,
                  bottom: 20,
                  child: AccessibleTouchTarget(
                    key: const Key('corner_bl'),
                    semanticLabel: 'Bottom-Left crop corner handle',
                    semanticHint: 'Drag to adjust lower-left boundary',
                    onTap: () {},
                    child: Container(width: 24, height: 24, color: Colors.blue),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      for (final keyStr in ['corner_tl', 'corner_tr', 'corner_br', 'corner_bl']) {
        final key = Key(keyStr);
        final rect = tester.getRect(find.byKey(key));
        expect(rect.width, greaterThanOrEqualTo(48.0));
        expect(rect.height, greaterThanOrEqualTo(48.0));
      }

      expect(
        tester.getSemantics(find.byKey(const Key('corner_tl'))),
        matchesSemantics(
          label: 'Top-Left crop corner handle',
          hint: 'Drag to adjust upper-left boundary',
          hasTapAction: true,
        ),
      );

      handle.dispose();
    });

    testWidgets('Tier 1: Page organizer provides accessible Move Up / Move Down buttons for non-drag reordering', (tester) async {
      final handle = tester.ensureSemantics();
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

      expect(find.byType(PageOrganizerScreen), findsOneWidget);

      // Verify Move Down on index 0 meets 48dp minimum
      final moveDown0 = find.byKey(const Key('move_down_btn_0'));
      expect(moveDown0, findsOneWidget);
      final downRect = tester.getRect(moveDown0);
      expect(downRect.width, greaterThanOrEqualTo(48.0));
      expect(downRect.height, greaterThanOrEqualTo(48.0));

      // Verify Move Up on index 1 meets 48dp minimum
      final moveUp1 = find.byKey(const Key('move_up_btn_1'));
      expect(moveUp1, findsOneWidget);
      final upRect = tester.getRect(moveUp1);
      expect(upRect.width, greaterThanOrEqualTo(48.0));
      expect(upRect.height, greaterThanOrEqualTo(48.0));

      // Tap Move Down on index 0 to swap pages
      await tester.tap(moveDown0);
      await tester.pumpAndSettle();

      handle.dispose();
    });

    testWidgets('Tier 2: Document card touch targets for rename and delete are >= 48x48dp', (tester) async {
      final handle = tester.ensureSemantics();

      bool tapped = false;
      final doc = DocumentEntity(
        id: 'doc-1',
        title: 'Tax Return 2026',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now().subtract(const Duration(minutes: 2)),
        pageCount: 3,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentCard(
              document: doc,
              onTap: () {
                tapped = true;
              },
            ),
          ),
        ),
      );

      expect(find.byType(DocumentCard), findsOneWidget);
      expect(find.text('Tax Return 2026'), findsOneWidget);

      // Check options menu button touch target >= 48x48 dp
      final menuFinder = find.byKey(Key('doc_menu_${doc.id}'));
      expect(menuFinder, findsOneWidget);
      final menuRect = tester.getRect(menuFinder);
      expect(menuRect.width, greaterThanOrEqualTo(48.0));
      expect(menuRect.height, greaterThanOrEqualTo(48.0));

      // Tap card
      await tester.tap(find.byType(DocumentCard));
      await tester.pump();
      expect(tapped, isTrue);

      handle.dispose();
    });

    testWidgets('Tier 2: UI adapts cleanly to 2.0x system text scale without layout overflow', (tester) async {
      final doc = DocumentEntity(
        id: 'doc-scaled',
        title: 'Large Accessibility Text Scaling Test With Multi-Page Document',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        pageCount: 5,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: Scaffold(
              appBar: AppBar(
                title: const Text('DocErena'),
              ),
              body: ListView(
                children: [
                  DocumentCard(document: doc),
                ],
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(DocumentCard), findsOneWidget);
      expect(find.text('Large Accessibility Text Scaling Test With Multi-Page Document'), findsOneWidget);
    });
  });
}
