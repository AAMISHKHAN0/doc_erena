import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:docerena/core/errors/result.dart';
import 'package:docerena/core/geometry/crop_polygon.dart';
import 'package:docerena/core/interfaces/i_document_repository.dart';
import 'package:docerena/core/interfaces/i_pdf_generator.dart';
import 'package:docerena/core/interfaces/i_share_service.dart';
import 'package:docerena/core/interfaces/i_file_storage_service.dart';
import 'package:docerena/core/theme/app_colors.dart';
import 'package:docerena/core/theme/app_theme.dart';
import 'package:docerena/core/theme/app_typography.dart';
import 'package:docerena/domain/entities/document.dart';
import 'package:docerena/domain/entities/export_result.dart';
import 'package:docerena/domain/entities/page_entity.dart';
import 'package:docerena/presentation/widgets/accessible_touch_target.dart';
import 'package:docerena/presentation/widgets/docerena_app_bar.dart';
import 'package:docerena/presentation/widgets/docerena_button.dart';
import 'package:docerena/presentation/widgets/docerena_empty_state.dart';
import 'package:docerena/presentation/widgets/document_card.dart';
import 'package:docerena/presentation/screens/s01_welcome/welcome_screen.dart';
import 'package:docerena/presentation/screens/s02_home/home_screen.dart';
import 'package:docerena/presentation/screens/s07_save/save_document_dialog.dart';
import 'package:docerena/presentation/screens/s08_viewer/document_viewer_screen.dart';
import 'package:docerena/presentation/screens/s09_export/export_bottom_sheet.dart';

// --- In-Memory Fake Repositories & Services for Widget Testing ---

class FakeDocumentRepository implements IDocumentRepository {
  final Map<String, DocumentEntity> documents = {};
  final Map<String, List<PageEntity>> pages = {};

  void seedDocument(DocumentEntity doc, List<PageEntity> docPages) {
    documents[doc.id] = doc;
    pages[doc.id] = docPages;
  }

  @override
  Future<Result<List<DocumentEntity>, StorageError>> getAllDocuments() async {
    final list = documents.values.where((d) => !d.isDeleted).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return Result.ok(list);
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
    documents[document.id] = document.copyWith(pageCount: pages.length);
    this.pages[document.id] = pages;
    return Result.ok(documents[document.id]!);
  }

  @override
  Future<Result<void, StorageError>> deleteDocument(String id) async {
    documents.remove(id);
    pages.remove(id);
    return Result.ok(null);
  }

  @override
  Future<Result<void, StorageError>> renameDocument(String id, String newTitle) async {
    if (documents.containsKey(id)) {
      documents[id] = documents[id]!.copyWith(
        title: newTitle,
        updatedAt: DateTime.now(),
      );
      return Result.ok(null);
    }
    return Result.err(const StorageError(
      message: 'Document not found',
      code: StorageErrorCode.fileNotFound,
    ));
  }

  @override
  Future<Result<List<DocumentEntity>, StorageError>> searchDocuments(String query) async {
    final q = query.toLowerCase();
    final results = documents.values
        .where((d) => !d.isDeleted && d.title.toLowerCase().contains(q))
        .toList();
    return Result.ok(results);
  }

  @override
  Future<Result<DocumentEntity?, StorageError>> getActiveDraft() async {
    final drafts = documents.values.where((d) => d.isDraft).toList();
    return Result.ok(drafts.isNotEmpty ? drafts.first : null);
  }

  @override
  Future<Result<void, StorageError>> discardDraft(String draftId) async {
    documents.remove(draftId);
    pages.remove(draftId);
    return Result.ok(null);
  }
}

class FakePdfGenerator implements IPdfGenerator {
  bool generateCalled = false;
  PdfPageFormat? lastFormat;
  PdfQualityPreset? lastQuality;

  @override
  Future<Result<GeneratedPdf, PdfExportError>> generateMultipagePdf({
    required String documentTitle,
    required List<PdfPageSpec> pages,
    required PdfPageFormat pageFormat,
    required PdfQualityPreset quality,
  }) async {
    generateCalled = true;
    lastFormat = pageFormat;
    lastQuality = quality;
    return Result.ok(GeneratedPdf(
      filePath: '/mock/cache/$documentTitle.pdf',
      pageCount: pages.length,
      fileSizeBytes: 1024 * 500,
    ));
  }

  @override
  Future<Result<PdfValidationInfo, PdfExportError>> validatePdfFile(String filePath) async {
    return Result.ok(const PdfValidationInfo(
      isValid: true,
      pageCount: 3,
      fileSizeBytes: 1024 * 500,
    ));
  }
}

class FakeShareService implements IShareService {
  bool shareCalled = false;
  bool saveCopyCalled = false;
  String? lastSharedPath;
  String? lastSavedName;

  @override
  Future<Result<void, ShareError>> sharePdf({
    required String pdfCachePath,
    required String mimeType,
    required String subject,
  }) async {
    shareCalled = true;
    lastSharedPath = pdfCachePath;
    return Result.ok(null);
  }

  @override
  Future<Result<String, ShareError>> saveCopyViaPicker({
    required String sourceCachePath,
    required String suggestedFileName,
  }) async {
    saveCopyCalled = true;
    lastSavedName = suggestedFileName;
    return Result.ok('/mock/storage/emulated/0/Download/$suggestedFileName');
  }
}

class FakeFileStorageService implements IFileStorageService {
  @override
  String resolveKey(String relativeKey) => '/mock/files/$relativeKey';

  @override
  String createOriginalKey(String documentId, String pageId) =>
      'documents/$documentId/pages/${pageId}_orig.jpg';

  @override
  String createExportKey(String exportId) => 'cache/exports/$exportId.pdf';

  @override
  Future<Result<void, StorageError>> writeAtomic(String relativeKey, List<int> bytes) async =>
      Result.ok(null);

  @override
  Future<Result<List<int>, StorageError>> readFile(String relativeKey) async =>
      Result.ok([]);

  @override
  Future<Result<void, StorageError>> deleteFile(String relativeKey) async =>
      Result.ok(null);

  @override
  Future<bool> fileExists(String relativeKey) async => false;
}

// --- Test Suite ---

void main() {
  group('Milestone 2: Design System & Tokens', () {
    test('AppColors verifies original branding tokens without CamScanner green', () {
      expect(AppColors.deepIndigo, const Color(0xFF4F46E5));
      expect(AppColors.digitalTeal, const Color(0xFF0D9488));
      expect(AppColors.slateNavy, const Color(0xFF0F172A));
      expect(AppColors.pureWhite, const Color(0xFFFFFFFF));

      // Strictly verify no CamScanner green (#00A86B)
      const camScannerGreen = Color(0xFF00A86B);
      expect(AppColors.deepIndigo, isNot(camScannerGreen));
      expect(AppColors.digitalTeal, isNot(camScannerGreen));
      expect(AppColors.success, isNot(camScannerGreen));
    });

    test('AppTheme defines compliant Light and Dark Material 3 ThemeData', () {
      final light = AppTheme.lightTheme;
      final dark = AppTheme.darkTheme;

      expect(light.useMaterial3, isTrue);
      expect(dark.useMaterial3, isTrue);

      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);

      expect(light.colorScheme.primary, AppColors.deepIndigo);
      expect(dark.colorScheme.primary, AppColors.lightIndigo);

      expect(light.scaffoldBackgroundColor, AppColors.canvasLight);
      expect(dark.scaffoldBackgroundColor, AppColors.slateNavy);

      // Verify button themes enforce >= 48dp minimum size
      expect(
        light.elevatedButtonTheme.style?.minimumSize?.resolve({}),
        const Size(48.0, 48.0),
      );
      expect(
        dark.elevatedButtonTheme.style?.minimumSize?.resolve({}),
        const Size(48.0, 48.0),
      );
    });

    test('AppTypography provides complete scalable typography scales', () {
      expect(AppTypography.lightTextTheme.displayLarge?.fontSize, 32.0);
      expect(AppTypography.lightTextTheme.titleMedium?.fontSize, 18.0);
      expect(AppTypography.lightTextTheme.bodyLarge?.fontSize, 16.0);
      expect(AppTypography.lightTextTheme.labelLarge?.fontSize, 14.0);
      expect(AppTypography.lightTextTheme.bodySmall?.fontSize, 12.0);
    });
  });

  group('Milestone 2: Shared Accessible Widgets', () {
    testWidgets('AccessibleTouchTarget ensures >= 48x48dp target and semantics', (tester) async {
      final handle = tester.ensureSemantics();
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: AccessibleTouchTarget(
                semanticLabel: 'Custom target',
                isButton: true,
                onTap: () => tapped = true,
                child: const Icon(Icons.star, size: 16.0),
              ),
            ),
          ),
        ),
      );

      final rect = tester.getRect(find.byType(AccessibleTouchTarget));
      expect(rect.width, greaterThanOrEqualTo(48.0));
      expect(rect.height, greaterThanOrEqualTo(48.0));

      await tester.tap(find.byType(AccessibleTouchTarget));
      await tester.pump();
      expect(tapped, isTrue);

      handle.dispose();
    });

    testWidgets('DocerenaButton renders filled, outlined, text and handles loading state', (tester) async {
      bool filledTapped = false;
      bool outlinedTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Column(
              children: [
                DocerenaButton.filled(
                  key: const Key('btn_filled'),
                  label: 'Filled Button',
                  onPressed: () => filledTapped = true,
                ),
                DocerenaButton.outlined(
                  key: const Key('btn_outlined'),
                  label: 'Outlined Button',
                  onPressed: () => outlinedTapped = true,
                ),
                DocerenaButton.text(
                  key: const Key('btn_text_loading'),
                  label: 'Loading Button',
                  isLoading: true,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      );

      final filledRect = tester.getRect(find.byKey(const Key('btn_filled')));
      expect(filledRect.height, greaterThanOrEqualTo(48.0));

      await tester.tap(find.byKey(const Key('btn_filled')));
      await tester.pump();
      expect(filledTapped, isTrue);

      await tester.tap(find.byKey(const Key('btn_outlined')));
      await tester.pump();
      expect(outlinedTapped, isTrue);

      // Loading button renders progress indicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('DocerenaAppBar renders branding, search toggle, and sort popup menu', (tester) async {
      bool searchToggled = false;
      DocumentSortOption? selectedSort;
      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            appBar: DocerenaAppBar(
              title: 'DocErena',
              onToggleSearch: () => searchToggled = true,
              onSortSelected: (sort) => selectedSort = sort,
              currentSort: DocumentSortOption.dateModified,
            ),
          ),
        ),
      );

      expect(find.text('DocErena'), findsOneWidget);

      // Tap search icon
      await tester.tap(find.byKey(const Key('app_bar_search_btn')));
      await tester.pump();
      expect(searchToggled, isTrue);

      // Tap sort menu
      await tester.tap(find.byKey(const Key('app_bar_sort_btn')));
      await tester.pumpAndSettle();

      expect(find.text('Date Modified'), findsOneWidget);
      expect(find.text('Title A–Z'), findsOneWidget);
      expect(find.text('Page Count'), findsOneWidget);

      await tester.tap(find.text('Title A–Z'));
      await tester.pumpAndSettle();
      expect(selectedSort, DocumentSortOption.title);
    });

    testWidgets('DocerenaEmptyState, EmptySearch, and StorageWarning render properly', (tester) async {
      bool scanTapped = false;
      bool clearTapped = false;
      bool dismissTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Column(
              children: [
                DocerenaStorageWarningBanner(
                  onDismiss: () => dismissTapped = true,
                ),
                DocerenaEmptySearchState(
                  query: 'MissingQuery',
                  onClearSearch: () => clearTapped = true,
                ),
                Expanded(
                  child: DocerenaEmptyState(
                    onScanPressed: () => scanTapped = true,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('No documents yet'), findsOneWidget);
      expect(find.text('Scan your first document'), findsOneWidget);
      expect(find.text('No documents found for "MissingQuery"'), findsOneWidget);
      expect(find.text('Low device storage. Free up space to ensure scans save properly.'), findsOneWidget);

      await tester.tap(find.text('Scan your first document'));
      await tester.pump();
      expect(scanTapped, isTrue);

      await tester.tap(find.text('Clear search filter'));
      await tester.pump();
      expect(clearTapped, isTrue);
    });

    testWidgets('DocumentCard displays document metadata, page count badge, and actions', (tester) async {
      final doc = DocumentEntity(
        id: 'doc-123',
        title: 'Tax Declaration 2026',
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
        updatedAt: DateTime.now().subtract(const Duration(minutes: 5)),
        pageCount: 4,
      );

      bool cardTapped = false;
      bool renameTapped = false;
      bool deleteTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: DocumentCard(
              document: doc,
              onTap: () => cardTapped = true,
              onRename: () => renameTapped = true,
              onDelete: () => deleteTapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Tax Declaration 2026'), findsOneWidget);
      expect(find.text('4 Pages'), findsOneWidget);
      expect(find.text('Updated 5m ago'), findsOneWidget);

      await tester.tap(find.text('Tax Declaration 2026'));
      await tester.pump();
      expect(cardTapped, isTrue);

      // Open popup menu
      await tester.tap(find.byKey(const Key('doc_menu_doc-123')));
      await tester.pumpAndSettle();

      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      expect(renameTapped, isTrue);
    });
  });

  group('Milestone 2: Screen S01 Welcome', () {
    testWidgets('WelcomeScreen renders offline statement, value propositions, and buttons', (tester) async {
      bool scanningTapped = false;
      bool exploreTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: WelcomeScreen(
            onStartScanning: () => scanningTapped = true,
            onExploreDocuments: () => exploreTapped = true,
          ),
        ),
      );

      expect(find.text('DocErena'), findsOneWidget);
      expect(find.text('Private, offline document scanning on your terms.'), findsOneWidget);
      expect(find.text('100% Offline & Private'), findsOneWidget);
      expect(find.text('Lossless Originals'), findsOneWidget);
      expect(find.text('Universal PDF Export'), findsOneWidget);

      await tester.tap(find.byKey(const Key('welcome_start_scanning_btn')));
      await tester.pump();
      expect(scanningTapped, isTrue);

      await tester.tap(find.byKey(const Key('welcome_explore_documents_btn')));
      await tester.pump();
      expect(exploreTapped, isTrue);
    });

    testWidgets('WelcomeScreen permission rationale dialog renders guidance and recovery actions', (tester) async {
      bool tryAgainTapped = false;
      bool settingsTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const Key('show_dialog_btn'),
                  onPressed: () {
                    WelcomeScreen.showPermissionRationaleDialog(
                      context: context,
                      onTryAgain: () => tryAgainTapped = true,
                      onOpenSettings: () => settingsTapped = true,
                    );
                  },
                  child: const Text('Show Dialog'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('show_dialog_btn')));
      await tester.pumpAndSettle();

      expect(find.text('Camera Access Required'), findsOneWidget);
      expect(
        find.text('DocErena needs camera access to capture paper documents. Your photos remain completely offline and private on your device.'),
        findsOneWidget,
      );

      expect(find.byKey(const Key('permission_try_again_btn')), findsOneWidget);
      expect(find.byKey(const Key('permission_open_settings_btn')), findsOneWidget);

      await tester.tap(find.byKey(const Key('permission_try_again_btn')));
      await tester.pumpAndSettle();
      expect(tryAgainTapped, isTrue);
    });
  });

  group('Milestone 2: Screen S02 Home Document List & Grid', () {
    late FakeDocumentRepository repo;

    setUp(() {
      repo = FakeDocumentRepository();
      repo.seedDocument(
        DocumentEntity(
          id: 'doc-1',
          title: 'Invoice November',
          createdAt: DateTime.now().subtract(const Duration(days: 1)),
          updatedAt: DateTime.now().subtract(const Duration(days: 1)),
          pageCount: 2,
        ),
        [],
      );
      repo.seedDocument(
        DocumentEntity(
          id: 'doc-2',
          title: 'Passport Copy',
          createdAt: DateTime.now().subtract(const Duration(hours: 2)),
          updatedAt: DateTime.now().subtract(const Duration(hours: 2)),
          pageCount: 1,
        ),
        [],
      );
    });

    testWidgets('HomeScreen loads and displays documents with scan FAB >= 56dp', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: HomeScreen(repository: repo),
        ),
      );

      // Loading -> settled
      await tester.pumpAndSettle();

      expect(find.text('Invoice November'), findsOneWidget);
      expect(find.text('Passport Copy'), findsOneWidget);

      final fabRect = tester.getRect(find.byKey(const Key('home_scan_fab')));
      expect(fabRect.width, greaterThanOrEqualTo(56.0));
      expect(fabRect.height, greaterThanOrEqualTo(56.0));
    });

    testWidgets('HomeScreen live search filters documents by title', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: HomeScreen(repository: repo),
        ),
      );
      await tester.pumpAndSettle();

      // Open search
      await tester.tap(find.byKey(const Key('app_bar_search_btn')));
      await tester.pumpAndSettle();

      // Enter query
      await tester.enterText(find.byKey(const Key('app_bar_search_field')), 'Passport');
      await tester.pumpAndSettle();

      expect(find.text('Passport Copy'), findsOneWidget);
      expect(find.text('Invoice November'), findsNothing);

      // Non-matching query
      await tester.enterText(find.byKey(const Key('app_bar_search_field')), 'UnknownDoc');
      await tester.pumpAndSettle();

      expect(find.text('No documents found for "UnknownDoc"'), findsOneWidget);
    });

    testWidgets('HomeScreen deletes document with confirmation dialog', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: HomeScreen(repository: repo),
        ),
      );
      await tester.pumpAndSettle();

      // Open menu for doc-1
      await tester.tap(find.byKey(const Key('doc_menu_doc-1')));
      await tester.pumpAndSettle();

      // Tap Delete
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Document?'), findsOneWidget);

      // Confirm delete
      await tester.tap(find.byKey(const Key('delete_dialog_confirm_btn')));
      await tester.pumpAndSettle();

      expect(find.text('Invoice November'), findsNothing);
      expect(repo.documents.containsKey('doc-1'), isFalse);
    });
  });

  group('Milestone 2: Screen S07 Save Document Dialog', () {
    late FakeDocumentRepository repo;
    late List<PageEntity> dummyPages;

    setUp(() {
      repo = FakeDocumentRepository();
      dummyPages = [
        PageEntity(
          id: 'p1',
          documentId: 'temp',
          position: 0,
          originalFileKey: 'documents/temp/p1_orig.jpg',
          cropPolygon: CropPolygon.fullFrame(),
          pixelWidth: 1080,
          pixelHeight: 1920,
          createdAt: DateTime.now(),
        ),
      ];
    });

    test('SaveDocumentDialog generates suggested title DocErena_YYYYMMDD_HHMMSS', () {
      final fixedDate = DateTime(2026, 11, 7, 13, 30, 45);
      final title = SaveDocumentDialog.generateSuggestedTitle(fixedDate);
      expect(title, 'DocErena_20261107_133045');
    });

    testWidgets('SaveDocumentDialog commits document to repository atomically', (tester) async {
      DocumentEntity? savedResult;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SaveDocumentDialog(
              repository: repo,
              pages: dummyPages,
              initialTitle: 'Contract Final',
              onSaveSuccess: (doc) => savedResult = doc,
            ),
          ),
        ),
      );

      expect(find.text('Save Document'), findsOneWidget);
      expect(find.text('Contract Final'), findsOneWidget);

      await tester.tap(find.byKey(const Key('save_confirm_btn')));
      await tester.pumpAndSettle();

      expect(savedResult, isNotNull);
      expect(savedResult!.title, 'Contract Final');
      expect(repo.documents.containsKey(savedResult!.id), isTrue);
    });

    testWidgets('SaveDocumentDialog permits duplicate titles disambiguated by UUID', (tester) async {
      // Pre-seed a document with title "Receipt"
      repo.seedDocument(
        DocumentEntity(
          id: 'receipt-uuid-1',
          title: 'Receipt',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          pageCount: 1,
        ),
        [],
      );

      DocumentEntity? savedResult;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SaveDocumentDialog(
              repository: repo,
              pages: dummyPages,
              initialTitle: 'Receipt',
              onSaveSuccess: (doc) => savedResult = doc,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('save_confirm_btn')));
      await tester.pumpAndSettle();

      expect(savedResult, isNotNull);
      expect(savedResult!.title, 'Receipt');
      expect(savedResult!.id, isNot('receipt-uuid-1'));
      expect(repo.documents.length, 2);
    });
  });

  group('Milestone 2: Screen S08 Document Viewer', () {
    late FakeDocumentRepository repo;
    late DocumentEntity doc;
    late List<PageEntity> pages;

    setUp(() {
      repo = FakeDocumentRepository();
      doc = DocumentEntity(
        id: 'doc-viewer-1',
        title: 'Project Brief',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        pageCount: 2,
      );
      pages = [
        PageEntity(
          id: 'page-1',
          documentId: 'doc-viewer-1',
          position: 0,
          originalFileKey: 'documents/doc-viewer-1/p1_orig.jpg',
          cropPolygon: CropPolygon.fullFrame(),
          pixelWidth: 1080,
          pixelHeight: 1920,
          createdAt: DateTime.now(),
        ),
        PageEntity(
          id: 'page-2',
          documentId: 'doc-viewer-1',
          position: 1,
          originalFileKey: 'documents/doc-viewer-1/p2_orig.jpg',
          cropPolygon: CropPolygon.fullFrame(),
          pixelWidth: 1080,
          pixelHeight: 1920,
          createdAt: DateTime.now(),
        ),
      ];
      repo.seedDocument(doc, pages);
    });

    testWidgets('DocumentViewerScreen renders InteractiveViewer and Page Indicator Pill', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: DocumentViewerScreen(
            document: doc,
            initialPages: pages,
            repository: repo,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Project Brief'), findsOneWidget);
      expect(find.text('Page 1 of 2'), findsOneWidget);

      // Verify InteractiveViewer is configured
      final interactiveViewerFinder = find.byType(InteractiveViewer);
      expect(interactiveViewerFinder, findsOneWidget);

      final InteractiveViewer iv = tester.widget(interactiveViewerFinder);
      expect(iv.maxScale, 4.0);
      expect(iv.minScale, 1.0);
      expect(iv.panEnabled, isTrue);

      // Verify missing page fallback renders gracefully when file is absent
      expect(find.text('Page image unavailable'), findsOneWidget);
    });
  });

  group('Milestone 2: Screen S09 Export Bottom Sheet', () {
    late FakePdfGenerator pdfGen;
    late FakeShareService shareService;
    late DocumentEntity doc;
    late List<PageEntity> pages;

    setUp(() {
      pdfGen = FakePdfGenerator();
      shareService = FakeShareService();
      doc = DocumentEntity(
        id: 'doc-exp-1',
        title: 'Annual Report',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        pageCount: 3,
      );
      pages = List.generate(
        3,
        (i) => PageEntity(
          id: 'p$i',
          documentId: 'doc-exp-1',
          position: i,
          originalFileKey: 'documents/doc-exp-1/p${i}_orig.jpg',
          cropPolygon: CropPolygon.fullFrame(),
          pixelWidth: 1080,
          pixelHeight: 1920,
          createdAt: DateTime.now(),
        ),
      );
    });

    testWidgets('ExportBottomSheet configures format, quality, estimates size, and triggers SAF save', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: ExportBottomSheet(
              document: doc,
              pages: pages,
              pdfGenerator: pdfGen,
              shareService: shareService,
            ),
          ),
        ),
      );

      expect(find.text('Export Document as PDF'), findsOneWidget);
      expect(find.text('Annual Report.pdf'), findsOneWidget);
      expect(find.text('3 pages • Estimated size: ~960 KB'), findsOneWidget);

      // Select High quality
      await tester.tap(find.text('High (300DPI)'));
      await tester.pumpAndSettle();

      expect(find.text('3 pages • Estimated size: ~2.2 MB'), findsOneWidget);

      // Tap Save to Device
      await tester.tap(find.byKey(const Key('export_save_device_btn')));
      await tester.pumpAndSettle();

      expect(pdfGen.generateCalled, isTrue);
      expect(pdfGen.lastQuality, PdfQualityPreset.high);
      expect(shareService.saveCopyCalled, isTrue);
      expect(shareService.lastSavedName, 'Annual Report.pdf');
    });

    testWidgets('ExportBottomSheet triggers Android share sheet', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: ExportBottomSheet(
              document: doc,
              pages: pages,
              pdfGenerator: pdfGen,
              shareService: shareService,
            ),
          ),
        ),
      );

      // Tap Share PDF
      await tester.tap(find.byKey(const Key('export_share_pdf_btn')));
      await tester.pumpAndSettle();

      expect(pdfGen.generateCalled, isTrue);
      expect(shareService.shareCalled, isTrue);
      expect(shareService.lastSharedPath, contains('Annual Report.pdf'));
    });
  });
}
