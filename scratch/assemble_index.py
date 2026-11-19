import os
import re
import hashlib

parts_dir = r'd:\camscanner\scratch\parts'
part_files = sorted([f for f in os.listdir(parts_dir) if f.endswith('.html')])
print(f"Found {len(part_files)} part files: {part_files}")

full_content = ""
for pf in part_files:
    p_path = os.path.join(parts_dir, pf)
    with open(p_path, 'r', encoding='utf-8') as f:
        full_content += f.read() + "\n"

# Verify forbidden substitute / fallback patterns are completely absent
assert 'fallbackCanvas' not in full_content, "ERROR: fallbackCanvas found in assembled source!"
assert 'DocErena Offline Document Page' not in full_content, "ERROR: substitute document page found in assembled source!"

# Verify critical storage methods are present
assert 'getDocuments: function' in full_content or 'getDocuments(' in full_content, "ERROR: getDocuments missing from DocErenaStorage!"
assert 'getFolders: function' in full_content or 'getFolders(' in full_content, "ERROR: getFolders missing from DocErenaStorage!"
assert 'getTrash: function' in full_content or 'getTrash(' in full_content, "ERROR: getTrash missing from DocErenaStorage!"

# Verify Experimental OCR badge is present
assert 'Experimental' in full_content, "ERROR: Experimental badge missing!"
assert 'Experimental offline text recognition' in full_content, "ERROR: OCR disclosure missing!"

# Verify zero external URLs for 100% offline security
urls = re.findall(r'https?://[^\s"\'<>]+', full_content)
assert len(urls) == 0, f"ERROR: Found external URLs in assembled source: {urls}"

encoded_bytes = full_content.encode('utf-8')
h_master = hashlib.sha256(encoded_bytes).hexdigest()

# 1. Write to web_preview/index.html
out_web = r'd:\camscanner\web_preview\index.html'
with open(out_web, 'wb') as f:
    f.write(encoded_bytes)
h_web = hashlib.sha256(open(out_web, 'rb').read()).hexdigest()
print(f"Wrote {len(encoded_bytes):,} bytes to {out_web} (SHA-256: {h_web})")

# 2. Write to build_apk/assets/index.html (Bit-for-bit identical)
out_assets = r'd:\camscanner\build_apk\assets\index.html'
with open(out_assets, 'wb') as f:
    f.write(encoded_bytes)
h_assets = hashlib.sha256(open(out_assets, 'rb').read()).hexdigest()
print(f"Wrote {len(encoded_bytes):,} bytes to {out_assets} (SHA-256: {h_assets})")

# 3. Write to android/app/src/main/assets/index.html (Bit-for-bit identical)
out_android_assets = r'd:\camscanner\android\app\src\main\assets\index.html'
os.makedirs(os.path.dirname(out_android_assets), exist_ok=True)
with open(out_android_assets, 'wb') as f:
    f.write(encoded_bytes)
h_android = hashlib.sha256(open(out_android_assets, 'rb').read()).hexdigest()
print(f"Wrote {len(encoded_bytes):,} bytes to {out_android_assets} (SHA-256: {h_android})")

# 4. Also sync to build_apk/bundle_module/assets/index.html if exists
out_bundle_assets = r'd:\camscanner\build_apk\bundle_module\assets\index.html'
if os.path.exists(os.path.dirname(out_bundle_assets)):
    with open(out_bundle_assets, 'wb') as f:
        f.write(encoded_bytes)
    h_bundle = hashlib.sha256(open(out_bundle_assets, 'rb').read()).hexdigest()
    assert h_bundle == h_master, "ERROR: Bundle assets hash mismatch!"
    print(f"Wrote {len(encoded_bytes):,} bytes to {out_bundle_assets} (SHA-256: {h_bundle})")

# Verify Bit-for-Bit Parity across all outputs
assert h_web == h_assets == h_android == h_master, "ERROR: Bit-for-bit parity check failed across web preview and APK!"
print(f"SUCCESS: Bit-for-bit parity verified across Web Preview and APK assets! SHA-256: {h_master}")

# Run assertion validation
required_tokens = [
    'id="screen-splash"', 'id="screen-onboarding"', 'id="screen-home"',
    'id="screen-camera"', 'id="screen-crop"', 'id="screen-enhance"',
    'id="screen-organizer"', 'id="screen-save"', 'id="screen-viewer"',
    'id="screen-export"', 'id="screen-share"', 'id="screen-documents"',
    'id="screen-folder"', 'id="screen-create-folder"', 'id="screen-search"',
    'id="screen-trash"', 'id="screen-pdf-tools"', 'id="screen-merge-pdf"',
    'id="screen-split-pdf"', 'id="screen-compress-pdf"', 'id="screen-settings"',
    'id="screen-notifications"',
    'id="modal-add-pdf"', 'id="modal-doc-actions"', 'id="modal-delete-confirmation"',
    'id="modal-permanent-delete"', 'id="modal-move-folder"', 'id="modal-enter-password"',
    'id="menu-doc-title"', 'id="del-doc-title"',
    'id="merge-files-container"', 'id="merge-output-filename"',
    'id="trash-docs-container"', 'id="trash-search-input"',
    'id="dedicated-search-input"', 'id="search-result-count"',
    'Search documents', 'Your folders', 'New folder', 'Add folder', 'Create folder',
    'Save PDF', 'Share PDF', 'Continue to share', 'Choose a format',
    'Choose an app on the next screen.',
    'function showDocMenu', 'function handleMenuAction',
    'function openDeleteConfirmationModal', 'function confirmMoveToTrash',
    'function renderTrashDocs', 'function restoreTrashedDoc',
    'function openPermanentDeleteModal', 'function closePermanentDeleteModal',
    'function confirmPermanentDelete',
    'function renderMergeFilesList', 'function reorderMergeFile',
    'function removeMergeFile', 'function openAddPdfModal', 'function executeMergePdf',
    'function renderSearchResults', 'function clearSearchInput', 'function toggleDocFavorite',
    'function renderDocsScreenContent', 'function submitCreateFolder',
    'function openMoveToFolderModal', 'function replayOnboardingFlow',
    "target === 'pdf_tools'", "target === 'merge_pdf'", "target === 'trash'",
    "target === 'permanent_delete'", "target === 'menu'", "target === 'delete_dialog'",
    "target === 'split_pdf'", "target === 'compress_pdf'", "target === 'settings'",
    'id="screen-add-text"', 'id="screen-edit-pdf-text"', 'id="screen-create-signature"',
    'id="screen-place-signature"', 'id="screen-extract-text-ocr"', 'id="screen-ocr-result"',
    'id="screen-annotate-pdf"', 'id="screen-protect-pdf"', 'id="screen-backup-restore"',
    'id="screen-scan-id-card"', 'id="screen-scan-book"',
    'function initAddTextScreen', 'function initEditPdfTextScreen',
    'function initSignaturePadScreen', 'function setupPlaceSignatureScreen',
    'function setupOcrExtractionScreen', 'function runOfflineOcrExtraction',
    'function copyOcrResultText', 'function setupAnnotateScreen',
    'function executeProtectPdf', 'function exportLocalBackup',
    'function captureIdCardSide', 'function captureBookSpread',
    'DocErenaStorage.getDocuments', 'DocErenaStorage.getFolders', 'DocErenaStorage.getTrash',
    'function scrollToToolSection', 'function handleAllToolsSearch', 'function clearAllToolsSearch',
    'function showComingSoon', 'function closeComingSoonModal', 'function handleToolPdfToImages',
    'function openOrganizerForReorder', 'function triggerSystemFileImport',
    'function changeProtectDocument', 'function submitPasswordPrompt', 'function closePasswordPromptModal',
    'function openNotificationsScreen', 'function requestAppNotificationPermission',
    'function openOrganizerFromViewer', 'function addPageToCurrentDocument',
    'function openExportFromViewer', 'function shareCurrentViewerDoc',
    'function handleOrganizerBack', 'function handleOrganizerContinue'
]

missing = [tok for tok in required_tokens if tok not in full_content]
if missing:
    print(f"FAILED: {len(missing)} missing required tokens:")
    for m in missing:
        print(f"  - {m}")
    exit(1)
else:
    print(f"SUCCESS: All {len(required_tokens)} required contract tokens verified present!")
