# DocErena Test Infrastructure & Automated Verification Matrix (TEST_INFRA.md)

**Document Version:** 4.0.0  
**Project:** DocErena — Offline Document Scanner & PDF Studio  
**Package Identifier:** `com.digitalerena.docerena`  
**Runtime Architecture:** Native Android WebView Container + Offline JavaScript Engine + Standalone Toolchain (API 34-37)  
**Verification Target:** Comprehensive 5-Scan-Mode Suite, 60+ Feature Inventory, 4-Tier Opaque-Box E2E Automated Verification  
**Date:** 2026-11-19  
**Status:** **ACTIVE & MAINTAINED**

---

## 1. Test Philosophy & Core Architecture

The DocErena testing infrastructure is engineered around four foundational principles: **Opaque-Box Verification**, **Requirement-Driven Traceability**, **Strict Offline-First Integrity**, and **Deterministic Empirical Oracles**.

### 1.1 Opaque-Box (Black-Box) Testing
- Tests interact strictly through public interfaces, DOM structures, user-facing touch controls, JavaScript engine bridges, SQLite/IndexedDB/localStorage persistence boundaries, and binary file representations.
- Tests do not rely on private internal mock flags, bypassed validation checks, or synthetic shortcuts.
- Observable behavior, UI navigation state, and file output contracts are validated against authoritative mathematical specifications and binary standards.

### 1.2 4-Tier Test Hierarchy
The test infrastructure organizes all verification into four complementary tiers:
1. **Tier 1: Feature Coverage**:
   - Comprehensive verification across all core user-facing features (Welcome, Onboarding, Home, Settings, Navigation, Organizer, Filters, PDF Tools, Library, Trash).
   - Deep verification of all 5 production scan modes: Single Page, Multi-Page Batch, 2-Sided ID Cards (2-in-1 A4 composite), Book Spread (interactive split adjustment & ordered slicing), and Verified Timestamp (viewfinder live preview overlay, cryptographic certification watermark burn-in, PDF export persistence).
   - Modal draft state preservation across opening/closing `#modal-camera-all-features`.
   - Coming Soon badge integrity: Timestamp "Soon" badge removed upon verification; all 16 unbuilt tools strictly retain "Soon" badges and Coming Soon dialogs.
2. **Tier 2: Boundary & Corner Cases**:
   - Evaluates geometric degeneracies (bowtie quads), arithmetic boundaries (exposure clamping `[-100, 100]`, scrubber divisions guard), invariant protections (prohibiting deletion of the last remaining page), and input fuzzing.
   - Scan mode boundaries: ID card single-sided cancellation rollback, Book split ratio boundaries strictly clamped to `[0.20, 0.80]`, Timestamp formatting validation.
3. **Tier 3: Cross-Feature Interactions & Pipelines**:
   - Chains multiple features across realistic end-to-end user workflows:
     - *Pipeline A*: Scan -> Crop -> Filter -> Organize -> Save -> Viewer -> Export -> Merge -> Trash -> Restore.
     - *Pipeline B*: Folder Management -> Document Assignment -> Favorite -> Search -> Removal.
     - *Pipeline C*: PDF Split -> Stream Compression -> Share Sheet -> Scoped FileProvider URI.
     - *Pipeline D*: 5-Mode Multi-Document Workflow -> Multi-Page Compilation -> PDF Assembly & Verification.
4. **Tier 4: Real-World Operational Scenarios & Live Device Testing**:
   - *S-01*: Multi-page mixed receipt/contract/card batch scan and compilation.
   - *S-02*: 100% Offline Guarantee Audit (Zero `android.permission.INTERNET`, zero cloud telemetry).
   - *S-03*: Real APK binary and manifest audit (`classes.dex`, bundled assets, SHA-256).
   - *S-04*: Live cold-restart persistence survival across simulated OS process kill (`am force-stop` -> `am start`).
   - *S-05*: Camera permission denial and recovery flow (`pm revoke` / `pm grant android.permission.CAMERA`).
   - *S-06*: Dynamic camera rotation handling (`settings put system user_rotation <0|1>`).
   - *S-07*: Photo capture of angled perspective sheet and homography rectification (NCC > 0.90).
   - *S-08*: Independent PDF inspection via `pypdf 7.1.0` and `pillow 12.3.0` (page count, stream extraction, watermark verification).

### 1.3 Strict Offline-First & Privacy Guarantee
- **Zero Internet Permissions**: `AndroidManifest.xml` (in source and inside the compiled APK) must never declare `android.permission.INTERNET` or `android.permission.ACCESS_NETWORK_STATE`.
- **Zero Remote Telemetry**: All bundled assets (`assets/index.html`, `assets/tailwind.js`) are 100% self-contained with no external CDN dependencies, analytics trackers, or remote APIs.
- **App-Private Storage Isolation**: Scoped file sharing via `DocErenaFileProvider` (`content://com.digitalerena.docerena.fileprovider/...`) ensuring files are exposed only via system share sheets.

---

## 2. Test Architecture & Directory Layout

```
d:\camscanner\test\
├── challenge\
│   ├── run_full_e2e_suite.py               # Master full-scope 4-tier E2E automated test runner
│   ├── run_e2e_suite.py                    # Master 4-tier baseline E2E automated test runner (72 tests)
│   ├── run_all_challenge_suites.py         # Batch runner executing all challenge suites
│   ├── m10_adversarial_scaling_e2e_suite.py# 10k fuzz iterations, 1,000-page scaling, state churn
│   ├── documents_and_folder_suite.py       # Documents screen, folder management, color swatches
│   ├── document_search_and_favorites_suite.py # Real-time title search, favorites filter
│   ├── document_actions_and_delete_suite.py# Action sheet, rename, move, soft-delete confirmation
│   ├── trash_lifecycle_suite.py            # Recently deleted, restore, permanent deletion warning
│   ├── pdf_tools_and_merge_suite.py        # PDF Tools 2x3 hub, merge engine, filename validation
│   ├── export_and_share_suite.py           # ISO 32000 PDF export, share dialog, quality selector
│   ├── viewer_pdf_tools_adversarial_suite.py # Viewer zoom matrix, double-tap toggle, scrubber
│   ├── empirical_challenge_suite.py        # Atomic file write rollback, SQLite schema integrity
│   ├── deep_stress_harness.py              # Multipage stress, concurrency, memory limits
│   ├── fuzz_m8_harness.py                  # High-entropy range parsing, AST delimiter integrity
│   ├── m9_review_harness.py                # Visual pastel tokens, touch targets >= 48dp
│   ├── m9_adversarial_harness.py           # Layout boundaries, multi-page batch stress
│   └── adversarial_m9_integrity_harness.py # Breakpoints, key contracts, re-indexing
├── verify_milestone3_real_scanner_journey.py# CDP-driven live scanner journey on emulator
├── verify_onboarding_lifecycle.py          # UIAutomator native touch & cold restart test
├── verify_v5_blockers_rigorous.py          # Deep validation of bug fixes & contracts
└── verify_v5_pipeline_integrity.py         # Image processing & PDF compiler integrity
```

---

## 3. Feature Inventory Mapped to 4-Tier Test Matrix

| # | Feature Name | Requirement | Tier 1 (Coverage) | Tier 2 (Boundary) | Tier 3 (Pipeline) | Tier 4 (Scenario) |
|---|--------------|:-----------:|:-----------------:|:-----------------:|:-----------------:|:-----------------:|
| 1 | Single Scan Mode | R1 | `F-10`, `F-13`, `F-SCAN-01` | - | `C-01`, `C-04` | `S-01`, `S-07` |
| 2 | Batch Scan Mode | R1 | `F-14`, `F-SCAN-02` | `B-03` | `C-01`, `C-04` | `S-01` |
| 3 | ID Cards Mode (2-in-1 A4) | R1 | `F-SCAN-03` | `B-11` | `C-04` | `S-01`, `S-08` |
| 4 | Book Mode (Split Adjustment) | R1 | `F-SCAN-04` | `B-12` | `C-04` | `S-01`, `S-08` |
| 5 | Timestamp Mode (Live & PDF) | R1 | `F-SCAN-05` | `B-13` | `C-04` | `S-08` |
| 6 | Draft State Preservation | R1 | `F-DRAFT-01` | - | `C-04` | - |
| 7 | Coming Soon Badges Integrity | R1 | `F-BADGE-01` | - | - | - |
| 8 | Welcome & Onboarding | - | `F-01`-`F-04` | - | - | `S-02`, `S-04` |
| 9 | Home & Global Navigation | - | `F-05`-`F-09` | - | `C-01`, `C-02` | `S-04` |
| 10 | Camera Flash & Hardware Feed | R4 | `F-11` | - | `C-01` | `S-05`, `S-06` |
| 11 | Edge Detection & 4-Corner Crop | R4 | `F-12`, `F-16`, `F-17` | `B-01`, `B-08` | `C-01` | `S-01`, `S-07` |
| 12 | 90° Image Rotation & Reset | - | `F-18`, `F-19` | `B-01` | `C-01` | `S-01` |
| 13 | Page Retake Flow | - | `F-20` | - | - | - |
| 14 | Filter Presets & Exposure | - | `F-21`-`F-23` | `B-02` | `C-01` | `S-01` |
| 15 | Organizer Grid, Reorder, Delete | - | `F-24`-`F-26` | `B-03` | `C-01` | `S-01` |
| 16 | Title Sanitization & Persistence | - | `F-27`, `F-28` | `B-06` | `C-01` | `S-04` |
| 17 | Multi-Page Viewer & Scrubber | - | `F-29`-`F-31` | `B-10` | `C-01` | `S-01` |
| 18 | ISO 32000 PDF Compilation | R3, R4 | `F-32`-`F-35` | - | `C-01`, `C-03` | `S-01`, `S-08` |
| 19 | Library, Folders & Favorites | - | `F-36`-`F-42` | `B-05`, `B-07` | `C-02` | `S-04` |
| 20 | Trash Lifecycle & Soft-Delete | - | `F-43`-`F-45` | - | `C-01` | `S-04` |
| 21 | PDF Tools: Merge, Split, Compress | - | `F-46`-`F-49` | `B-04`, `B-09` | `C-01`, `C-03` | - |
| 22 | Transparent Feature Disclosures | - | `F-50` | - | - | - |
| 23 | Offline OCR Text Recognition | - | `F-51` | - | - | - |
| 24 | Storage Protection across Kill | R4 | `F-52` | `B-06` | `C-01`, `C-02` | `S-04` |
| 25 | 100% Offline Core Operation | R2 | `F-53` | - | - | `S-02` |
| 26 | Edge-to-Edge System Insets | - | `F-54` | - | - | - |
| 27 | WCAG 48x48dp Touch Targets | - | `F-55` | - | - | - |
| 28 | Camera Permission Denial/Recovery | R4 | - | - | - | `S-05` |
| 29 | Camera Display Rotation Handling | R4 | - | - | - | `S-06` |
| 30 | Angled Sheet Homography Warp | R4 | - | - | - | `S-07` |
| 31 | Independent PDF Inspection (pypdf/PIL) | R3, R4 | - | - | - | `S-08` |

---

## 4. Test Execution Guide

### 4.1 Master Comprehensive Full-Scope E2E Suite
To execute the complete 4-tier verification suite including all 5 scan modes and hardware scenarios:
```powershell
python test/challenge/run_full_e2e_suite.py
```
**Expected Output:**
- 84+ total verified assertions across all 4 tiers.
- 100% Pass rate (0 failures, 0 warnings, 0 unhandled exceptions).
- Exit code: `0`.

### 4.2 Baseline 4-Tier Automated Test Suite
To execute the baseline 72-test suite:
```powershell
python test/challenge/run_e2e_suite.py
```
**Expected Output:**
- 72 total tests executed (55 Tier 1, 10 Tier 2, 3 Tier 3, 4 Tier 4).
- 100% Pass rate (0 failures).
- Exit code: `0`.

### 4.3 Full Challenge & Stress Regression Batch
To execute the complete regression matrix of 16 adversarial challenge suites:
```powershell
python test/challenge/run_all_challenge_suites.py
```
**Expected Output:**
- 16/16 suites passed with 100% pass rate.
- Exit code: `0`.

---

## 5. Acceptance & Verification Contracts

1. **Scan Modes Specifications**:
   - **Single Scan**: Viewfinder captures 1 real page, transitions to crop, applies 4-corner perspective rectification, enhances, reviews, and compiles into 1-page ISO 32000 PDF.
   - **Batch Scan**: Sequential viewfinder captures increment `#camera-batch-badge` counter; captures accumulate in `sessionPages` maintaining strict chronological order; organizer review grid and exported PDF mirror exact capture sequence.
   - **ID Cards Mode**: Two-stage capture (Front then Back); `stitchIdCardToA4` composites both onto a single $1240 \times 1754$ px A4 sheet at 150 DPI with bounding boxes `(192, 240, 856, 540)` and `(192, 900, 856, 540)`; outputs single page.
   - **Book Mode**: Viewfinder captures 2-page book spread; interactive split divider/slider adjusts split boundary between 20% and 80% (default 50%); `processBookSpread` slices spread into ordered Left and Right pages and appends both to `sessionPages`.
   - **Timestamp Mode**: Live real-time date/time watermark preview on viewfinder (`#camera-timestamp-preview`); offscreen canvas burns verified timestamp watermark into image pixels; timestamp persists through crop, review, and exported ISO 32000 PDF.
   - **Draft Preservation**: Opening and closing `#modal-camera-all-features` maintains `sessionPages` length and contents completely intact.
   - **Coming Soon Badges**: Timestamp badge is removed; all other 16 unbuilt tools strictly display "Soon" badge and trigger `showComingSoon()`.

2. **Hardware & OS Lifecycle Specifications**:
   - **Camera Permission Denial & Recovery**: `pm revoke com.digitalerena.docerena android.permission.CAMERA` triggers permission denied banner; `pm grant` smoothly restores camera viewfinder.
   - **Display Rotation**: Switching `user_rotation` between `0` (portrait) and `1` (landscape) preserves application state without crash.
   - **Angled Sheet Homography Warp**: Non-rectangular quad crop rectifies perspective distortion; output compared with reference rect using Normalized Cross-Correlation (NCC > 0.90).
   - **Cold Restart Persistence**: Document creation -> save -> `am force-stop` -> `am start` preserves document title, page count, and page data across restart.
   - **Independent PDF Inspection**: Exported PDF verified via `pypdf 7.1.0` and `pillow 12.3.0` for valid PDF header, page count, extracted image fidelity, and timestamp watermark text.

3. **Android Security & Manifest Isolation**:
   - `android.permission.INTERNET` must NEVER be present in `AndroidManifest.xml` or compiled APK.
   - Scoped file sharing via `com.digitalerena.docerena.DocErenaFileProvider` with URI grant flags.
