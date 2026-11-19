# Project: DocErena — Milestone 1 (Offline Scanner Core & Digital PDF Text Editing Spike)

## Architecture
- **Framework**: Flutter (Dart) targeting Android (minSdk 24, targetSdk 34/35).
- **Core Principles**:
  - 100% Offline by design: Zero cloud APIs, zero telemetry, no `android.permission.INTERNET`.
  - Non-destructive processing: Raw captured images are immutable; crops, rotations, and filters are persisted as metadata.
  - Interface-driven decoupling: `IDocumentScanner`, `IPdfGenerator`, `IDocumentRepository`, `IFileStorageService`, `IShareService`.
  - Atomic persistence: Drafts auto-saved with status `draft`; committed to `saved` inside SQLite transaction; writes staged via `.tmp` files.
  - Permissive open-source stack: Apache 2.0 / BSD / MIT dependencies only. No GPL/AGPL copyleft libraries.
  - Temporary package identifier: `com.digitalerena.docerena` (labeled as temporary).

## Code Layout
```
d:\camscanner\
├── android\                    # Android native project configuration
│   └── app\src\main\
│       ├── AndroidManifest.xml # Permissions (CAMERA only, NO INTERNET), FileProvider
│       └── res\xml\filepaths.xml # Scoped FileProvider paths for private cache
├── lib\
│   ├── main.dart               # App entrypoint, dependency injection & global error boundary
│   ├── core\
│   │   ├── theme\              # Design system tokens, color palette, typography
│   │   ├── geometry\           # Quadrilateral math, convex hull, normalization [0..1]
│   │   ├── interfaces\         # Abstract contracts: IDocumentScanner, IPdfGenerator, etc.
│   │   ├── errors\             # Strongly-typed Result<T, E> and failure hierarchies
│   │   └── storage\            # Atomic file I/O, relative path key resolution
│   ├── data\
│   │   ├── models\             # DocumentModel, PageModel, ExportModel, SQLite mappers
│   │   ├── database\           # SQLite schema, migrations, connection factory
│   │   └── repositories\       # DocumentRepository implementation with draft recovery
│   ├── domain\
│   │   └── entities\           # Pure entities: Document, Page, CropPolygon, PdfSpec
│   ├── services\
│   │   ├── scanner\            # Custom scanner adapter & photo picker integration
│   │   ├── transform\          # Non-destructive crop, 90° rotate, filter algorithms
│   │   ├── pdf\                # Multipage PDF compilation engine (pure Dart pdf)
│   │   └── share\              # Android Share Sheet (FileProvider) & SAF file picker
│   └── presentation\
│       ├── navigation\         # App routing & transitions
│       ├── screens\
│       │   ├── s01_welcome\    # Onboarding & contextual permission guidance
│       │   ├── s02_home\       # Document list/grid, search by name, sort, FAB
│       │   ├── s03_camera\     # Live capture, flash toggle, counter badge, import
│       │   ├── s04_crop\       # 4-corner crop canvas, zoom loupe, 90° rotate, reset
│       │   ├── s05_enhance\    # Original, color, grayscale, b&w filters, sliders
│       │   ├── s06_organizer\  # Page thumbnails, drag reorder, accessible move, delete, retake
│       │   ├── s07_save\       # Date-based title suggestion, atomic commit
│       │   ├── s08_viewer\     # Multi-page interactive viewer, pinch-zoom
│       │   └── s09_export\     # PDF settings (A4/Letter/Fit), SAF save copy, share sheet
│       └── widgets\            # Shared accessible UI components (≥48dp touch targets)
├── test\                       # Automated unit and widget test suites
│   ├── unit\
│   │   ├── crop_geometry_test.dart
│   │   ├── page_reorder_test.dart
│   │   └── document_persistence_test.dart
│   ├── widgets\
│   │   ├── home_screen_test.dart
│   │   ├── organizer_screen_test.dart
│   │   └── accessibility_semantics_test.dart
│   └── e2e\
│       ├── offline_workflow_e2e_test.dart
│       └── pdf_export_integrity_test.dart
└── docs\
    └── research\
        └── digital_pdf_text_editing_spike.md # R4 research spike deliverable
```

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Environment Inspection Report | Toolchain, SDK inspection, Windows setup guide, and testability matrix | M0 | ORIGINAL_REQUEST §R1 |
| 2 | Replaceable Interface Contracts | `IDocumentScanner`, `IPdfGenerator`, `IDocumentRepository`, `IFileStorageService`, `IShareService` | M1 | 03_ARCH §7 |
| 3 | Core Data Models & SQLite Schema | `documents`, `pages`, `exports` tables with foreign keys and atomic persistence | M1 | 03_ARCH §3 |
| 4 | Atomic File Storage Service | Relative keys, `.tmp` staging, `fsync`, atomic rename, disk-full protection | M1 | 03_ARCH §3 |
| 5 | Draft Persistence & Startup Recovery | Auto-save in-progress drafts; prompt Resume/Discard on app cold restart | M1 | 01_PRD §MG-01 |
| 6 | Original Brand Identity & Theme Tokens | Deep Indigo / Digital Teal palette, dark/light theme, no CamScanner imitation | M2 | 02_EXP §Nav, §R3 |
| 7 | Accessibility & ≥48dp Touch Targets | TalkBack semantics, 48x48dp minimum targets, accessible non-drag reordering | M2 | 05_QA QA-07, §R3 |
| 8 | S01 Welcome & Permission Guidance | First-launch explanation, contextual camera request, "Open Settings" link | M2 | 02_EXP S01 |
| 9 | S02 Home Document List & Grid | Card list/grid, search by name, sort options, empty states, scan FAB | M2 | 02_EXP S02 |
| 10 | S07 Save Document Screen / Dialog | Suggested date title `DocErena_YYYYMMDD_HHMMSS`, UUID disambiguation | M2 | 02_EXP S07 |
| 11 | S08 Document Viewer Screen | InteractiveViewer, pinch-zoom, pan, page scrubber, missing page recovery | M2 | 02_EXP S08 |
| 12 | S03 Camera Capture Screen | Viewfinder, shutter, flash toggle (auto/on/off), page counter badge | M3 | 02_EXP S03 |
| 13 | System Image Picker Import | Multi-image import via system picker preserving selected order | M3 | 01_PRD SC-04 |
| 14 | S04 Non-Destructive Manual Crop | 4 draggable corner pins, normalized `[0.0, 1.0]`, original untouched | M3 | 01_PRD SC-02 |
| 15 | Convex Hull & Geometry Validation | Reject self-intersecting bowtie/degenerate quad; reset to full frame | M3 | 03_ARCH §4 |
| 16 | Magnification Loupe / Zoom Lens | 2x zoom lens offset from finger during corner drag to prevent occlusion | M3 | 02_EXP S04 |
| 17 | 90-Degree Page Rotation | Rotate clockwise in 90° increments (0, 90, 180, 270) with dynamic preview | M3 | 01_PRD SC-03 |
| 18 | S05 Image Enhancement Filters | Original, Color, Grayscale, Black & White (binarized), brightness/contrast | M3 | 01_PRD SC-06 |
| 19 | S06 Page Organizer Screen | Thumbnail grid with page badges, drag-and-drop reorder, move up/down | M4 | 02_EXP S06 |
| 20 | Page Deletion with Confirmation | Delete page with dialog; re-index remaining pages 0..N-1 | M4 | 01_PRD SC-05 |
| 21 | Retake & Append Page Flows | Retake replaces only after confirmation; append preserves existing | M4 | 01_PRD SC-07 |
| 22 | Multipage PDF Generation Engine | Assemble ordered pages into valid PDF (A4/Letter/Fit, High/Med/Low) | M4 | 01_PRD PD-01 |
| 23 | Android System Share Sheet | Expose PDF via FileProvider (`content://` URI) with temporary read grant | M4 | 01_PRD PD-02 |
| 24 | SAF System Save Copy Picker | Save copy to user-chosen storage via `ACTION_CREATE_DOCUMENT` | M4 | 01_PRD PD-02 |
| 25 | R4 Digital PDF Text Editing Spike | Architecture report evaluating 6 engines against 6 criteria & 10 scenarios | M5 | ORIGINAL_REQUEST §R4 |
| 26 | Automated Test Suites & Pass 100% | Unit, widget, and E2E tests (crop math, reorder, persistence, PDF integrity) | M6 | ORIGINAL_REQUEST §R5 |
| 27 | Static Analysis & Verification Report | `flutter analyze`, device checklist, and post-milestone report delivery | M6 | ORIGINAL_REQUEST §R5 |
| 28 | Automatic Boundary & Corner Detection | Pure Dart on-device edge detection locating document corners using gradient analysis and ray casting | M7 | ORIGINAL_REQUEST §R2 |
| 29 | Fallback to Manual 4-Corner Crop | Seamless fallback to 4-corner homography crop when auto detection confidence is low | M7 | ORIGINAL_REQUEST §R2 |
| 30 | Multi-Page Batch Scan Session | Rapid capture workflow with `BatchScanSession` and per-capture atomic draft persistence in SQLite | M7 | ORIGINAL_REQUEST §R2 |
| 31 | Auto Shadow Removal Filter | Illumination background normalization via local block-wise division over immutable raw source | M7 | ORIGINAL_REQUEST §R2 |
| 32 | Document Contrast Enhancement | Adaptive percentile histogram stretching snapping paper to white and faded ink to black | M7 | ORIGINAL_REQUEST §R2 |
| 33 | Magic Color Filter | HSV saturation boost combined with 3x3 unsharp mask sharpening and highlight whitening | M7 | ORIGINAL_REQUEST §R2 |
| 34 | SQLite Schema v2 Migration | Upgraded `pages` table schema and CHECK constraint supporting new enhancement filter enum values | M7 | 03_ARCH §3, DB Helper |
| 35 | Offline PDF Merge | Combine multiple saved documents/PDF byte streams into a consolidated ISO 32000 PDF | M8 | ORIGINAL_REQUEST §R3 |
| 36 | Offline PDF Split | Divide document into separate ISO 32000 compliant PDFs by comma-separated page ranges | M8 | ORIGINAL_REQUEST §R3 |
| 37 | PDF Page Rotation in 90° Increments | Rotate individual pages by 90° clockwise in PDF export via `/Rotate` attribute | M8 | ORIGINAL_REQUEST §R3 |
| 38 | PDF Page Deletion & Extraction | Delete selected pages or extract page subsets into independent standalone PDFs | M8 | ORIGINAL_REQUEST §R3 |
| 39 | Material 3 UI Elevation & Tonal Surfaces | Calibrated surface elevation tokens, subtle 1dp tonal borders, custom vector icons, haptic feedback | M9 | ORIGINAL_REQUEST §R1 |
| 40 | Responsive Breakpoints & Multi-Screen Support | Adaptive layouts across compact phones (<600dp), tablets/foldables (600-840dp, >=840dp) with NavigationRail | M9 | ORIGINAL_REQUEST §R1 |
| 41 | Interactive Camera Batch Mode & Review Strip | Mode toggle, pulsing counter badge, live edge overlay, in-progress batch review strip | M9 | ORIGINAL_REQUEST §R1, §R2 |
| 42 | Interactive PDF Viewer & Thumbnail Rail | Smooth pinch-to-zoom (up to 4x), double-tap zoom animation, page scrubber slider, page thumbnail rail | M9 | ORIGINAL_REQUEST §R3 |
| 43 | PDF Tools Management UI | Dedicated UI flows and dialogs for PDF Merge, PDF Split, and batch page operations | M9 | ORIGINAL_REQUEST §R3 |
| 44 | Automated Test Suites for M2 Features | Unit and widget tests for edge detection, batch session, filter transforms, and PDF tools | M10 | ORIGINAL_REQUEST §R4 |
| 45 | E2E 100% Pass & Adversarial Hardening | Pass all test suites, Tier 5 challenger stress test verification, zero flutter analyze errors | M10 | ORIGINAL_REQUEST §R4 |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M0 | Environment Inspection | R1 environment inspection report, stack confirmation, setup instructions | None | DONE |
| M1 | Domain Core & Persistence Engine | Replaceable interfaces, Result types, SQLite schema, atomic file store, draft recovery | M0 | DONE |
| M2 | Design System & Core UI Screens | Original branding, tokens, accessibility, S01, S02, S07, S08, S09 | M1 | DONE |
| M3 | Scanner & Transformation Engine | Capture/import integration, S04 crop canvas, zoom loupe, 90° rotate, S05 filters | M1 | DONE |
| M4 | Page Organizer, PDF Export & Share | S06 organizer, drag & accessible move, retake/delete, multipage PDF generation, share sheet | M2, M3 | DONE |
| M5 | Digital PDF Text Editing Spike | Offline engine comparison, 6 criteria, 3 tiers, 10 test scenarios, recommendations | M0 | DONE |
| M6 | E2E Testing Pass & Final Verification | Pass 100% E2E test suites, static analysis, device test checklist, final milestone report | M4, M5 | DONE |
| M7 | Scanning Refinement & Image Processing | Edge detection, fallback crop, batch scan session, shadow removal, contrast, magic color, SQLite v2 | M1, M3 | DONE |
| M8 | PDF Tools & Page Manipulation Engine | Offline PDF merge, split, 90° rotate, page extraction/deletion, ISO 32000 compliance | M1, M4 | DONE |
| M9 | Responsive UI, Interactive Viewer & Design Elevation | M3 craft, tonal borders, haptics, responsive layouts, batch camera UI, interactive PDF viewer, PDF tools UI | M7, M8 | DONE |
| M10 | E2E Test Suite Pass, Adversarial Hardening & Final Verification | 100% pass across all unit, widget, and e2e test suites, Tier 5 adversarial stress tests, flutter analyze | M7, M8, M9 | DONE |

## Interface Contracts
### Scanner ↔ Domain
```dart
abstract class IDocumentScanner {
  Future<Result<ScannedImage, ScannerError>> capturePage({required CameraFlashMode flashMode});
  Future<Result<List<ScannedImage>, ScannerError>> importFromGallery();
  Future<Result<CropPolygon, ScannerError>> detectDocumentCorners(String imagePath);
  Future<Result<String, ScannerError>> applyCropAndPerspective({
    required String originalImagePath,
    required CropPolygon polygon,
    required String targetPath,
  });
}
```

### PDF Generator ↔ Domain
```dart
abstract class IPdfGenerator {
  Future<Result<GeneratedPdf, PdfExportError>> generateMultipagePdf({
    required String documentTitle,
    required List<PdfPageSpec> pages,
    required PdfPageFormat pageFormat,
    required PdfQualityPreset quality,
  });
  Future<Result<PdfValidationInfo, PdfExportError>> validatePdfFile(String filePath);
}
```

### PDF Manipulation Service ↔ Domain
```dart
abstract class IPdfManipulationService {
  Future<Result<GeneratedPdf, PdfExportError>> mergeDocuments({
    required List<String> sourceDocumentIds,
    required String mergedTitle,
    required PdfPageFormat pageFormat,
    required PdfQualityPreset quality,
  });
  Future<Result<List<GeneratedPdf>, PdfExportError>> splitDocument({
    required String sourceDocumentId,
    required List<List<int>> pageIndexRanges,
    required String baseTitle,
    required PdfPageFormat pageFormat,
    required PdfQualityPreset quality,
  });
  Future<Result<GeneratedPdf, PdfExportError>> rotateDocumentPages({
    required String documentId,
    required Map<int, int> pageIndexToRotationDegrees,
    required String targetTitle,
  });
  Future<Result<GeneratedPdf, PdfExportError>> extractDocumentPages({
    required String sourceDocumentId,
    required List<int> pageIndicesToExtract,
    required String extractedTitle,
  });
  Future<Result<void, PdfExportError>> deleteDocumentPages({
    required String documentId,
    required List<int> pageIndicesToDelete,
  });
}
```

### Storage Repository ↔ Domain
```dart
abstract class IDocumentRepository {
  Future<Result<List<DocumentEntity>, StorageError>> getAllDocuments();
  Future<Result<DocumentEntity?, StorageError>> getDocumentById(String id);
  Future<Result<List<PageEntity>, StorageError>> getPagesForDocument(String documentId);
  Future<Result<DocumentEntity, StorageError>> saveDocumentAtomic({
    required DocumentEntity document,
    required List<PageEntity> pages,
  });
  Future<Result<void, StorageError>> deleteDocument(String id);
  Future<Result<void, StorageError>> renameDocument(String id, String newTitle);
  Future<Result<List<DocumentEntity>, StorageError>> searchDocuments(String query);
  Future<Result<DocumentEntity?, StorageError>> getActiveDraft();
  Future<Result<void, StorageError>> discardDraft(String draftId);
}
```

### Share Service ↔ Domain
```dart
abstract class IShareService {
  Future<Result<void, ShareError>> sharePdf({
    required String pdfCachePath,
    required String mimeType,
    required String subject,
  });
  Future<Result<String, ShareError>> saveCopyViaPicker({
    required String sourceCachePath,
    required String suggestedFileName,
  });
}
```
