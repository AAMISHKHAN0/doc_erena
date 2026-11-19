import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:docerena/core/errors/result.dart';
import 'package:docerena/core/geometry/crop_polygon.dart';
import 'package:docerena/core/interfaces/i_document_repository.dart';
import 'package:docerena/core/theme/app_colors.dart';
import 'package:docerena/core/theme/app_theme.dart';
import 'package:docerena/domain/entities/document.dart';
import 'package:docerena/domain/entities/page_entity.dart';
import 'package:docerena/presentation/screens/s02_home/home_screen.dart';
import 'package:docerena/presentation/screens/s06_organizer/page_organizer_screen.dart';
import 'package:docerena/presentation/widgets/accessible_touch_target.dart';
import 'package:docerena/presentation/widgets/docerena_app_bar.dart';
import 'package:docerena/presentation/widgets/docerena_button.dart';
import 'package:docerena/presentation/widgets/docerena_empty_state.dart';
import 'package:docerena/presentation/widgets/document_card.dart';

class FakeDocumentRepository implements IDocumentRepository {
  final Map<String, DocumentEntity> documents = {};
  final Map<String, List<PageEntity>> pages = {};

  @override
  Future<Result<List<DocumentEntity>, StorageError>> getAllDocuments() async =>
      Success(documents.values.where((d) => !d.isDeleted).toList());

  @override
  Future<Result<DocumentEntity?, StorageError>> getDocumentById(String id) async =>
      Success(documents[id]);

  @override
  Future<Result<List<PageEntity>, StorageError>> getPagesForDocument(String documentId) async =>
      Success(pages[documentId] ?? []);

  @override
  Future<Result<DocumentEntity, StorageError>> saveDocumentAtomic({
    required DocumentEntity document,
    required List<PageEntity> pages,
  }) async {
    documents[document.id] = document.copyWith(pageCount: pages.length);
    this.pages[document.id] = pages;
    return Success(documents[document.id]!);
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
  Future<Result<List<DocumentEntity>, StorageError>> searchDocuments(String query) async =>
      Success(documents.values
          .where((d) => d.title.toLowerCase().contains(query.toLowerCase()))
          .toList());

  @override
  Future<Result<DocumentEntity?, StorageError>> getActiveDraft() async =>
      Success(documents.values.cast<DocumentEntity?>().firstWhere(
            (d) => d?.status == DocumentStatus.draft,
            orElse: () => null,
          ));

  @override
  Future<Result<void, StorageError>> discardDraft(String draftId) async {
    documents.remove(draftId);
    pages.remove(draftId);
    return const Success(null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeDocumentRepository repo;
  late DocumentEntity sampleDoc1;
  late DocumentEntity sampleDoc2;
  late List<PageEntity> samplePages;

  setUp(() {
    repo = FakeDocumentRepository();

    sampleDoc1 = DocumentEntity(
      id: 'doc-resp-1',
      title: 'Tax Declaration 2026',
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
      updatedAt: DateTime.now().subtract(const Duration(hours: 1)),
      pageCount: 3,
    );

    sampleDoc2 = DocumentEntity(
      id: 'doc-resp-2',
      title: 'Employment Agreement',
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
      updatedAt: DateTime.now().subtract(const Duration(days: 1)),
      pageCount: 5,
    );

    samplePages = [
      PageEntity(
        id: 'p1',
        documentId: sampleDoc1.id,
        position: 0,
        originalFileKey: 'dummy/path1.jpg',
        cropPolygon: CropPolygon.fullFrame(),
        pixelWidth: 800,
        pixelHeight: 1200,
        createdAt: DateTime.now(),
      ),
      PageEntity(
        id: 'p2',
        documentId: sampleDoc1.id,
        position: 1,
        originalFileKey: 'dummy/path2.jpg',
        cropPolygon: CropPolygon.fullFrame(),
        pixelWidth: 800,
        pixelHeight: 1200,
        createdAt: DateTime.now(),
      ),
    ];

    repo.documents[sampleDoc1.id] = sampleDoc1;
    repo.documents[sampleDoc2.id] = sampleDoc2;
    repo.pages[sampleDoc1.id] = samplePages;
  });

  group('Tier 1: Responsive Breakpoints (<600dp, 600-840dp, >=840dp)', () {
    testWidgets('compact phone viewport (<600dp) renders HomeScreen without overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: HomeScreen(repository: repo),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('Tax Declaration 2026'), findsOneWidget);
      expect(find.text('Employment Agreement'), findsOneWidget);
      expect(find.byKey(const Key('home_scan_fab')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('medium tablet/foldable viewport (600-840dp) renders HomeScreen cleanly', (tester) async {
      tester.view.physicalSize = const Size(720, 960);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: HomeScreen(repository: repo),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('Tax Declaration 2026'), findsOneWidget);
      expect(find.text('Employment Agreement'), findsOneWidget);
      expect(find.byKey(const Key('home_scan_fab')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('expanded wide tablet viewport (>=840dp) renders HomeScreen without clipping', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: HomeScreen(repository: repo),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('Tax Declaration 2026'), findsOneWidget);
      expect(find.text('Employment Agreement'), findsOneWidget);
      expect(find.byKey(const Key('home_scan_fab')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('PageOrganizerScreen adapts across compact and tablet viewports', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: PageOrganizerScreen(
            pages: samplePages,
            onSaveDocument: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PageOrganizerScreen), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Now switch to tablet width (720dp)
      tester.view.physicalSize = const Size(720, 900);
      await tester.pumpAndSettle();

      expect(find.byType(PageOrganizerScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Tier 2: Minimum 48x48dp Touch Targets (QA-07 & WCAG AA)', () {
    testWidgets('AccessibleTouchTarget enforces minimum 48x48dp dimensions', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AccessibleTouchTarget(
                semanticLabel: 'Small icon with accessible target',
                child: Container(
                  width: 24,
                  height: 24,
                  color: AppColors.deepIndigo,
                ),
              ),
            ),
          ),
        ),
      );

      final size = tester.getSize(find.byType(AccessibleTouchTarget));
      expect(size.width, greaterThanOrEqualTo(48.0));
      expect(size.height, greaterThanOrEqualTo(48.0));
    });

    testWidgets('DocerenaButton variants enforce minimum 48x48dp dimensions', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                DocerenaButton.filled(
                  text: 'Submit Scan',
                  onPressed: () {},
                ),
                DocerenaButton.outlined(
                  text: 'Cancel Action',
                  onPressed: () {},
                ),
                DocerenaButton.text(
                  text: 'Skip Step',
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      );

      final buttonFinders = find.byType(DocerenaButton);
      expect(buttonFinders, findsNWidgets(3));

      for (int i = 0; i < 3; i++) {
        final size = tester.getSize(buttonFinders.at(i));
        expect(size.width, greaterThanOrEqualTo(48.0));
        expect(size.height, greaterThanOrEqualTo(48.0));
      }
    });

    testWidgets('HomeScreen Floating Action Button satisfies minimum 48x48dp', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: HomeScreen(repository: repo),
        ),
      );
      await tester.pumpAndSettle();

      final fabFinder = find.byKey(const Key('home_scan_fab'));
      expect(fabFinder, findsOneWidget);

      final fabSize = tester.getSize(fabFinder);
      expect(fabSize.width, greaterThanOrEqualTo(48.0));
      expect(fabSize.height, greaterThanOrEqualTo(48.0));
    });

    testWidgets('DocumentCard popup action menu trigger satisfies minimum 48x48dp', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: DocumentCard(
              document: sampleDoc1,
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final menuFinder = find.byKey(Key('doc_card_menu_${sampleDoc1.id}'));
      expect(menuFinder, findsOneWidget);

      final menuSize = tester.getSize(menuFinder);
      expect(menuSize.width, greaterThanOrEqualTo(48.0));
      expect(menuSize.height, greaterThanOrEqualTo(48.0));
    });
  });

  group('Tier 2: Lack of RenderFlex Overflow at 2.0x Text Scaling', () {
    testWidgets('HomeScreen renders with zero RenderFlex overflow at 2.0x text scaling', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 640),
            textScaler: TextScaler.linear(2.0),
          ),
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: HomeScreen(repository: repo),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('DocerenaAppBar renders with zero overflow at 2.0x text scaling', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 640),
            textScaler: TextScaler.linear(2.0),
          ),
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              appBar: DocerenaAppBar(
                title: 'DocErena Offline Document Scanner Pro',
                showSearch: true,
                showViewToggle: true,
                showSort: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('DocerenaEmptyState renders with zero overflow at 2.0x text scaling', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 640),
            textScaler: TextScaler.linear(2.0),
          ),
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: DocerenaEmptyState(
                title: 'No Documents Yet',
                description: 'Capture pages using your camera or import photos from your device to begin.',
                actionLabel: 'Scan Document',
                onActionPressed: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('DocumentCard in List and Grid modes renders with zero overflow at 2.0x text scaling', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 640),
            textScaler: TextScaler.linear(2.0),
          ),
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: Column(
                children: [
                  DocumentCard(
                    document: sampleDoc1,
                    isGrid: false,
                    onTap: () {},
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 200,
                    width: 170,
                    child: DocumentCard(
                      document: sampleDoc2,
                      isGrid: true,
                      onTap: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
