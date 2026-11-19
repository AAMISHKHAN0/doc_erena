#!/usr/bin/env python3
"""
================================================================================
DocErena v5.0 Independent Inspection Defect Verification & Proof Script
Device: emulator-5554 (Android API 37)
Target APK: docerena_v5_phonetest.apk (versionCode 5, versionName 5.0.0-phonetest)

Verifications:
  1. Proof Pipeline: Import 2 distinct images -> Save -> Force-stop -> Reopen -> Export PDF -> Independently compare both pages
  2. Issue 1: OCR engine verification on multiple images against ground truth (receipt, invoice, unknown)
  3. Issue 2: Protected PDF generated through APK from exact contract & invoice, independently decrypted & visually compared
  4. Issue 3: PDF generator error enforcement (never emits substitute/placeholder page)
  5. Issue 4: Protection respects selected document (tested with 2 differently named documents, proving docs[0] is not hardcoded)
  6. Issue 6: Persistence test inside APK across cold restart & force-stop
================================================================================
"""

import os
import sys
import time
import json
import base64
import shutil
import hashlib
import subprocess
import numpy as np
from PIL import Image
import pypdf

ADB = r"C:\Users\Aamishkhan\AppData\Local\Android\Sdk\platform-tools\adb.exe"
DEVICE = "emulator-5554"
PACKAGE = "com.digitalerena.docerena"
ACTIVITY = f"{PACKAGE}/.MainActivity"

BASE_DIR = r"d:\camscanner"
INPUT_CONTRACT = os.path.join(BASE_DIR, "verification", "sample_inputs", "sample_contract_page1.png")
INPUT_INVOICE = os.path.join(BASE_DIR, "verification", "sample_inputs", "sample_invoice_page2.png")
INPUT_OCR_INVOICE = os.path.join(BASE_DIR, "verification", "sample_inputs", "test_invoice.png")
INPUT_RECEIPT = os.path.join(BASE_DIR, "verification", "sample_inputs", "test_receipt.png")
INPUT_UNKNOWN = os.path.join(BASE_DIR, "verification", "sample_inputs", "test_unknown.png")

OUTPUT_DIR = os.path.join(BASE_DIR, "verification", "sample_outputs")
REVIEW_OUTPUT_DIR = os.path.join(BASE_DIR, "review_package", "04_REAL_DOCUMENT_EVIDENCE", "sample_outputs")
SCREENSHOTS_DIR = os.path.join(BASE_DIR, "verification", "screenshots", "v5_verification")

os.makedirs(OUTPUT_DIR, exist_ok=True)
os.makedirs(REVIEW_OUTPUT_DIR, exist_ok=True)
os.makedirs(SCREENSHOTS_DIR, exist_ok=True)

def run_adb(args, timeout=30):
    cmd = [ADB, "-s", DEVICE] + args
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)

def exec_js(js_code, wait=2.0, expected_token=None):
    run_adb(["logcat", "-c"])
    tmp_pc = os.path.join(BASE_DIR, "scratch", "v5_temp_exec.js")
    with open(tmp_pc, "w", encoding="utf-8") as f:
        f.write(js_code)
    run_adb(["push", tmp_pc, "/data/local/tmp/v5_temp_exec.js"])
    run_adb(["shell", "am", "start", "-n", ACTIVITY, "--es", "exec_js_file", "/data/local/tmp/v5_temp_exec.js"])
    start = time.time()
    total_wait = max(wait, 3.5 if expected_token else wait)
    while time.time() - start < total_wait:
        time.sleep(0.4)
        res = run_adb(["logcat", "-d", "-s", "DocErenaJS:D"])
        if expected_token and expected_token in res.stdout:
            return res.stdout
    res = run_adb(["logcat", "-d", "-s", "DocErenaJS:D"])
    return res.stdout

def take_screenshot(name):
    dst = os.path.join(SCREENSHOTS_DIR, f"{name}.png")
    with open(dst, "wb") as f:
        subprocess.run([ADB, "-s", DEVICE, "exec-out", "screencap", "-p"], stdout=f)
    print(f"  [Screencap] {name}.png ({os.path.getsize(dst):,} bytes)")
    return dst

def compute_correlation(im1, im2):
    a1 = np.array(im1.convert("RGB").resize((400, 550)), dtype=np.float32)
    a2 = np.array(im2.convert("RGB").resize((400, 550)), dtype=np.float32)
    n1 = a1 - np.mean(a1)
    n2 = a2 - np.mean(a2)
    denom = np.sqrt(np.sum(n1 ** 2)) * np.sqrt(np.sum(n2 ** 2))
    return float(np.sum(n1 * n2) / denom) if denom != 0 else 0.0

def main():
    print("=" * 80)
    print(" DOCERENA V5.0 RIGOROUS DEFECT FIX & PIPELINE VERIFICATION")
    print(f" Device:  {DEVICE}")
    print(f" Package: {PACKAGE}")
    print(f" Time:    {time.strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 80)

    # 0. Check inputs
    assert os.path.exists(INPUT_CONTRACT), "Missing contract input"
    assert os.path.exists(INPUT_INVOICE), "Missing invoice input"
    assert os.path.exists(INPUT_RECEIPT), "Missing receipt input"
    assert os.path.exists(INPUT_UNKNOWN), "Missing unknown input"

    im_contract = Image.open(INPUT_CONTRACT)
    im_invoice = Image.open(INPUT_INVOICE)

    with open(INPUT_CONTRACT, "rb") as f:
        contract_b64 = "data:image/png;base64," + base64.b64encode(f.read()).decode()
    with open(INPUT_INVOICE, "rb") as f:
        invoice_b64 = "data:image/png;base64," + base64.b64encode(f.read()).decode()

    # Launch app
    print("\n[Step 1/8] Launching docerena_v5_phonetest.apk on emulator...")
    run_adb(["shell", "pm", "grant", PACKAGE, "android.permission.CAMERA"])
    run_adb(["shell", "am", "start", "-W", "-S", "-n", ACTIVITY, "--es", "screen", "home"])
    time.sleep(2.0)
    for _ in range(15):
        chk = exec_js("console.log('READY_CHECK: ' + (typeof DocErenaStorage !== 'undefined'));", wait=0.5)
        if "READY_CHECK: true" in chk:
            print("  ✓ App scripts fully initialized")
            break
        time.sleep(0.5)

    # Initialize pristine state: empty library for authentic journey demonstration
    init_clean_js = """
    (() => {
        DocErenaStorage.saveDocuments([]);
        navigateTo('home');
        renderDocumentList();
        console.log("CLEAN_INIT_SUCCESS: docs=0");
    })();
    """
    exec_js(init_clean_js, wait=1.5)
    take_screenshot("01_app_launched")

    # =========================================================================
    # CORE PROOF: Import 2 distinct images -> Save -> Force-stop -> Reopen -> Export PDF
    # =========================================================================
    print("\n[Step 2/8] CORE PROOF: Importing 2 distinct images into app batch...")
    import_js = f"""
    (async () => {{
        sessionPages = [];
        await new Promise(r => addRawImageToBatch('{contract_b64}', 'Contract Page 1', r));
        await new Promise(r => addRawImageToBatch('{invoice_b64}', 'Invoice Page 2', r));
        navigateTo('organizer');
        renderOrganizerGrid();
        console.log("BATCH_IMPORT_SUCCESS: count=" + sessionPages.length);
    }})();
    """
    out = exec_js(import_js, wait=2.5)
    print("  Import logcat:", [line for line in out.splitlines() if "BATCH_IMPORT" in line])
    assert "BATCH_IMPORT_SUCCESS: count=2" in out, "Failed to import both pages"
    take_screenshot("02_pages_imported_batch_grid")

    print("\n[Step 3/8] Navigating to Save Screen and Committing Save inside APK...")
    save_doc_js = """
    (async () => {
        navigateTo('save');
        const titleInput = document.getElementById('save-doc-title-input');
        if (titleInput) titleInput.value = 'Milestone3_Export_Contract_Invoice';
        console.log("NAV_SAVE_SCREEN: ready");
    })();
    """
    exec_js(save_doc_js, wait=1.5)
    take_screenshot("03_save_document_screen")

    commit_save_js = """
    (async () => {
        await ensurePagesAreJpeg(sessionPages);
        const doc = {
            id: 'doc_verified_contract_invoice',
            title: 'Milestone3_Export_Contract_Invoice',
            folder: 'Work',
            date: new Date().toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }),
            pageCount: sessionPages.length,
            pages: JSON.parse(JSON.stringify(sessionPages)),
            starred: true
        };
        DocErenaStorage.saveDocument(doc);
        activeDocForViewer = doc;
        openDocumentInViewer(doc.id);
        console.log("SAVE_DOC_SUCCESS: id=" + doc.id + ", pages=" + doc.pages.length);
    })();
    """
    out = exec_js(commit_save_js, wait=2.0)
    print("  Save logcat:", [line for line in out.splitlines() if "SAVE_DOC_SUCCESS" in line])
    assert "SAVE_DOC_SUCCESS" in out, "Failed to save document"
    take_screenshot("04_saved_document_viewer")

    print("\n[Step 4/8] FORCE-STOPPING APP (am force-stop)...")
    t_kill = time.time()
    run_adb(["shell", "am", "force-stop", PACKAGE])
    time.sleep(1.0)
    pid_check = run_adb(["shell", "pidof", PACKAGE]).stdout.strip()
    assert pid_check == "", f"Process failed to terminate: {pid_check}"
    print(f"  ✓ App completely terminated at {time.strftime('%H:%M:%S', time.localtime(t_kill))}")

    print("\n[Step 5/8] REOPENING APP (Cold Restart)...")
    t_reopen = time.time()
    run_adb(["shell", "am", "start", "-W", "-n", ACTIVITY, "--es", "screen", "home"])
    time.sleep(2.0)
    new_pid = run_adb(["shell", "pidof", PACKAGE]).stdout.strip()
    print(f"  ✓ App resurrected with new PID: {new_pid} at {time.strftime('%H:%M:%S', time.localtime(t_reopen))}")
    assert new_pid != "", "App failed to restart"

    for _ in range(15):
        chk = exec_js("console.log('READY_CHECK_COLD: ' + (typeof DocErenaStorage !== 'undefined'));", wait=0.5)
        if "READY_CHECK_COLD: true" in chk:
            print("  ✓ App scripts re-initialized after cold start")
            break
        time.sleep(0.5)

    # Verify home screen displays the persisted document in library
    verify_home_js = """
    (() => {
        navigateTo('home');
        renderDocumentList();
        const docs = DocErenaStorage.getDocuments();
        console.log("COLD_HOME_RESTORE: docs=" + (docs ? docs.length : 0));
    })();
    """
    exec_js(verify_home_js, wait=1.5)
    take_screenshot("05_reopened_home_persisted")

    # Query durable storage with readiness polling
    check_storage_js = """
    (() => {
        function checkDoc() {
            if (typeof DocErenaStorage !== 'undefined' && typeof openDocumentInViewer === 'function') {
                const doc = DocErenaStorage.getDocumentById('doc_verified_contract_invoice');
                if (doc) {
                    console.log("COLD_RESTORE_SUCCESS: title=" + doc.title + ", pageCount=" + doc.pageCount + ", pages=" + (doc.pages ? doc.pages.length : 0));
                    activeDocForViewer = doc;
                    openDocumentInViewer(doc.id);
                } else {
                    console.log("COLD_RESTORE_FAIL: document missing!");
                }
            } else {
                setTimeout(checkDoc, 200);
            }
        }
        checkDoc();
    })();
    """
    out = exec_js(check_storage_js, wait=2.0)
    print("  Restore logcat:", [line for line in out.splitlines() if "COLD_RESTORE" in line])
    assert "COLD_RESTORE_SUCCESS" in out, "Document failed to survive process kill"
    take_screenshot("06_reopened_document_viewer")

    # Export normal PDF from APK
    print("\n[Step 6/8] EXPORTING PDF FROM INSTALLED APK...")
    export_filename = "Milestone3_Export_Contract_Invoice.pdf"
    export_js = f"""
    (async () => {{
        const doc = DocErenaStorage.getDocumentById('doc_verified_contract_invoice');
        activeDocForViewer = doc;
        await ensurePagesAreJpeg(doc.pages);
        const b64 = generateRealPdfBase64(doc.title, doc.pages, {{ pageSize: 'a4', quality: 'high' }});
        DocErenaNative.savePdf(b64, '{export_filename}');
        console.log("EXPORT_PDF_SUCCESS: b64_len=" + b64.length);
    }})();
    """
    out = exec_js(export_js, wait=2.5)
    print("  Export logcat:", [line for line in out.splitlines() if "EXPORT_PDF" in line])
    assert "EXPORT_PDF_SUCCESS" in out, "PDF export failed in APK"

    # Pull exported PDF
    emu_pdf_path = f"/sdcard/Android/data/{PACKAGE}/files/Documents/{export_filename}"
    local_pdf = os.path.join(OUTPUT_DIR, export_filename)
    review_pdf = os.path.join(REVIEW_OUTPUT_DIR, export_filename)
    run_adb(["pull", emu_pdf_path, local_pdf])
    assert os.path.exists(local_pdf) and os.path.getsize(local_pdf) > 5000, f"Exported PDF missing or empty: {local_pdf}"
    shutil.copy2(local_pdf, review_pdf)
    print(f"  ✓ Pulled APK-exported PDF: {local_pdf} ({os.path.getsize(local_pdf):,} bytes)")

    # Independently verify normal exported PDF
    reader_norm = pypdf.PdfReader(local_pdf)
    assert len(reader_norm.pages) == 2, f"Expected 2 pages, got {len(reader_norm.pages)}"
    img_p1 = reader_norm.pages[0].images[0].image
    img_p2 = reader_norm.pages[1].images[0].image

    corr_p1_c = compute_correlation(img_p1, im_contract)
    corr_p1_i = compute_correlation(img_p1, im_invoice)
    corr_p2_c = compute_correlation(img_p2, im_contract)
    corr_p2_i = compute_correlation(img_p2, im_invoice)

    print(f"  [Independent Visual Cross-Correlation: Normal PDF]")
    print(f"    Page 1 vs Contract Input: {corr_p1_c:.4f} (Expected >= 0.80)")
    print(f"    Page 1 vs Invoice Input:  {corr_p1_i:.4f} (Baseline white paper: ~0.34)")
    print(f"    Page 2 vs Contract Input: {corr_p2_c:.4f} (Baseline white paper: ~0.34)")
    print(f"    Page 2 vs Invoice Input:  {corr_p2_i:.4f} (Expected >= 0.70)")
    print(f"    Page 1 Discrimination Delta: {corr_p1_c - corr_p1_i:.4f} (Expected > 0.50)")
    print(f"    Page 2 Discrimination Delta: {corr_p2_i - corr_p2_c:.4f} (Expected > 0.50)")
    assert corr_p1_c >= 0.80, "Page 1 does not correlate with Contract"
    assert corr_p2_i >= 0.70, "Page 2 does not correlate with Invoice"
    assert corr_p1_c > corr_p1_i + 0.50, "Page 1 discrimination failed"
    assert corr_p2_i > corr_p2_c + 0.50, "Page 2 discrimination failed"
    print("  ✓ CORE PROOF COMPLETE: Input -> Save -> Cold restart -> Export -> Independent visual comparison PASSED!")

    # =========================================================================
    # ISSUE 2: Protected PDF from exact Contract and Invoice THROUGH THE APK
    # =========================================================================
    print("\n[Step 7/8] ISSUE 2: Generating Protected PDF from exact files THROUGH APK...")
    prot_filename = "DocErena_Protected_Verified.pdf"
    prot_password = "DocErenaPass2026!"
    prot_js = f"""
    (async () => {{
        const doc = DocErenaStorage.getDocumentById('doc_verified_contract_invoice');
        activeDocForViewer = doc;
        selectedDocForProtect = doc;
        await ensurePagesAreJpeg(doc.pages);
        const encB64 = DocErenaCrypto.buildProtectedPdf(doc.title, doc.pages, '{prot_password}');
        DocErenaNative.protectPdf(encB64, '{prot_password}', '{prot_filename}');
        console.log("PROTECT_PDF_APK_SUCCESS: encB64_len=" + encB64.length);
    }})();
    """
    out = exec_js(prot_js, wait=3.0)
    print("  Protect logcat:", [line for line in out.splitlines() if "PROTECT_PDF_APK" in line])
    assert "PROTECT_PDF_APK_SUCCESS" in out, "Protected PDF generation failed in APK"

    emu_prot_path = f"/sdcard/Android/data/{PACKAGE}/files/Documents/{prot_filename}"
    local_prot = os.path.join(OUTPUT_DIR, prot_filename)
    review_prot = os.path.join(REVIEW_OUTPUT_DIR, prot_filename)
    run_adb(["pull", emu_prot_path, local_prot])
    assert os.path.exists(local_prot) and os.path.getsize(local_prot) > 5000, f"Protected PDF missing or empty: {local_prot}"
    shutil.copy2(local_prot, review_prot)
    print(f"  ✓ Pulled Protected PDF: {local_prot} ({os.path.getsize(local_prot):,} bytes)")

    # Independent Decryption & Visual Comparison
    reader_prot = pypdf.PdfReader(local_prot)
    assert reader_prot.is_encrypted is True, "PDF must be encrypted"
    dec_ret = reader_prot.decrypt(prot_password)
    assert dec_ret in [1, 2], f"Decryption with correct password failed: ret={dec_ret}"
    assert len(reader_prot.pages) == 2, f"Expected 2 pages in decrypted PDF, got {len(reader_prot.pages)}"

    p_img1 = reader_prot.pages[0].images[0].image
    p_img2 = reader_prot.pages[1].images[0].image

    # Save extracted images for evidence
    p_img1.save(os.path.join(OUTPUT_DIR, "extracted_prot_p1_contract.png"))
    p_img2.save(os.path.join(OUTPUT_DIR, "extracted_prot_p2_invoice.png"))

    corr_prot_p1_c = compute_correlation(p_img1, im_contract)
    corr_prot_p1_i = compute_correlation(p_img1, im_invoice)
    corr_prot_p2_c = compute_correlation(p_img2, im_contract)
    corr_prot_p2_i = compute_correlation(p_img2, im_invoice)

    print(f"  [Independent Visual Cross-Correlation: Protected PDF Decrypted]")
    print(f"    Page 1 vs Contract Input: {corr_prot_p1_c:.4f} (Expected >= 0.80)")
    print(f"    Page 1 vs Invoice Input:  {corr_prot_p1_i:.4f} (Baseline white paper: ~0.34)")
    print(f"    Page 2 vs Contract Input: {corr_prot_p2_c:.4f} (Baseline white paper: ~0.34)")
    print(f"    Page 2 vs Invoice Input:  {corr_prot_p2_i:.4f} (Expected >= 0.70)")
    print(f"    Page 1 Discrimination Delta: {corr_prot_p1_c - corr_prot_p1_i:.4f} (Expected > 0.50)")
    print(f"    Page 2 Discrimination Delta: {corr_prot_p2_i - corr_prot_p2_c:.4f} (Expected > 0.50)")

    assert corr_prot_p1_c >= 0.80, "Protected Page 1 does not correlate with Contract"
    assert corr_prot_p2_i >= 0.70, "Protected Page 2 does not correlate with Invoice"
    assert corr_prot_p1_c > corr_prot_p1_i + 0.50, "Protected Page 1 discrimination failed"
    assert corr_prot_p2_i > corr_prot_p2_c + 0.50, "Protected Page 2 discrimination failed"
    print("  ✓ ISSUE 2 RESOLVED: Protected PDF generated through APK decrypted & visually verified against exact originals!")

    # =========================================================================
    # ISSUE 4: Protection selects document chosen by user (NOT docs[0])
    # =========================================================================
    print("\n[Step 8/8] ISSUE 4: Testing Protection with 2 differently named documents...")
    test_issue4_js = f"""
    (async () => {{
        // Clear and create 2 distinct documents
        DocErenaStorage.saveDocuments([]);
        
        const docAlpha = {{
            id: 'doc_alpha_contract',
            title: 'Doc_Alpha_Contract',
            folder: 'Work',
            date: 'Today',
            pageCount: 1,
            pages: [{{ id: 'p_alpha', title: 'Alpha Contract', enhancedUrl: '{contract_b64}', width: 1200, height: 1600 }}]
        }};
        const docBeta = {{
            id: 'doc_beta_invoice',
            title: 'Doc_Beta_Invoice',
            folder: 'Work',
            date: 'Today',
            pageCount: 1,
            pages: [{{ id: 'p_beta', title: 'Beta Invoice', enhancedUrl: '{invoice_b64}', width: 1200, height: 1600 }}]
        }};
        
        DocErenaStorage.saveDocument(docAlpha);
        DocErenaStorage.saveDocument(docBeta);
        
        // Select Doc Beta explicitly (docBeta is NOT docs[0]!)
        selectDocumentToProtect('doc_beta_invoice');
        navigateTo('protect-pdf');
        
        const displayedTitle = document.getElementById('protect-doc-title') ? document.getElementById('protect-doc-title').textContent : '';
        console.log("ISSUE4_SELECTION_CHECK: displayedTitle=" + displayedTitle);
        
        // Execute protection on Doc Beta
        await executeProtectPdf();
    }})();
    """
    out = exec_js(test_issue4_js, wait=3.0)
    print("  Issue 4 logcat:", [line for line in out.splitlines() if "ISSUE4" in line or "PROTECT" in line])
    assert "Doc_Beta_Invoice" in out, "Protect PDF UI failed to display Doc Beta title!"

    # Verify Doc Beta protected PDF file exists on emulator
    emu_beta_pdf = f"/sdcard/Android/data/{PACKAGE}/files/Documents/Doc_Beta_Invoice_Protected.pdf"
    local_beta_pdf = os.path.join(OUTPUT_DIR, "Doc_Beta_Invoice_Protected.pdf")
    review_beta_pdf = os.path.join(REVIEW_OUTPUT_DIR, "Doc_Beta_Invoice_Protected.pdf")
    run_adb(["pull", emu_beta_pdf, local_beta_pdf])
    assert os.path.exists(local_beta_pdf) and os.path.getsize(local_beta_pdf) > 2000, "Doc Beta protected PDF missing!"
    shutil.copy2(local_beta_pdf, review_beta_pdf)
    print(f"  ✓ Pulled Doc Beta Protected PDF: {local_beta_pdf} ({os.path.getsize(local_beta_pdf):,} bytes)")

    # Decrypt and verify image is INVOICE, NOT contract!
    reader_beta = pypdf.PdfReader(local_beta_pdf)
    reader_beta.decrypt("DocErena2026!")
    img_beta = reader_beta.pages[0].images[0].image
    corr_beta_invoice = compute_correlation(img_beta, im_invoice)
    corr_beta_contract = compute_correlation(img_beta, im_contract)

    print(f"  [Issue 4 Verification: Doc Beta Protected Content]")
    print(f"    Doc Beta vs Invoice:  {corr_beta_invoice:.4f} (Expected >= 0.70)")
    print(f"    Doc Beta vs Contract: {corr_beta_contract:.4f} (Expected < 0.30)")
    assert corr_beta_invoice >= 0.70, "Doc Beta does not contain invoice image!"
    assert corr_beta_invoice > corr_beta_contract + 0.50, "Doc Beta mistakenly contained contract from docs[0]!"
    print("  ✓ ISSUE 4 RESOLVED: Exactly selected document was protected, proving docs[0] hardcoding is eliminated!")

    # =========================================================================
    # ISSUE 3: Replace placeholder page synthesis with clear error
    # =========================================================================
    print("\n--- ISSUE 3: Testing PDF Generator Error on Corrupt/Missing Input Data ---")
    test_issue3_js = """
    (() => {
        try {
            // Attempt generating PDF with corrupted/unsupported page image data
            const badPages = [{ title: 'Corrupt Page', enhancedUrl: 'invalid_data_scheme://corrupt' }];
            generateRealPdfBase64('BadDoc', badPages);
            console.log("ISSUE3_CHECK: FAILED_DID_NOT_THROW");
        } catch (err) {
            console.log("ISSUE3_CHECK: SUCCESS_THREW_ERROR: " + err.message);
        }
    })();
    """
    out = exec_js(test_issue3_js, wait=2.0, expected_token="ISSUE3_CHECK")
    print("  Issue 3 logcat:", [line for line in out.splitlines() if "ISSUE3_CHECK" in line])
    assert "SUCCESS_THREW_ERROR" in out and "substitute content" in out, "PDF generator did not reject invalid data"
    print("  ✓ ISSUE 3 RESOLVED: PDF generator strictly throws error and refuses to synthesize placeholder content!")

    # =========================================================================
    # ISSUE 1: Offline OCR Tested on Multiple Images Inside APK
    # =========================================================================
    print("\n--- ISSUE 1: Testing On-Device Offline OCR on Multiple Images Inside APK ---")
    ocr_results = {}
    for img_name, img_path in [("receipt", INPUT_RECEIPT), ("invoice", INPUT_OCR_INVOICE), ("unknown", INPUT_UNKNOWN)]:
        im_ocr = Image.open(img_path).convert("RGBA")
        w_ocr, h_ocr = im_ocr.size
        ocr_b64 = "data:image/png;base64," + base64.b64encode(open(img_path, "rb").read()).decode()
        
        ocr_js = f"""
        (async () => {{
            const img = new Image();
            await new Promise((res, rej) => {{
                img.onload = res;
                img.onerror = rej;
                img.src = '{ocr_b64}';
            }});
            const cvs = document.createElement('canvas');
            cvs.width = {w_ocr};
            cvs.height = {h_ocr};
            const ctx = cvs.getContext('2d');
            ctx.drawImage(img, 0, 0);
            
            const result = DocErenaOCR.processCanvas(cvs, {{ title: '{img_name}' }});
            console.log("OCR_RESULT_{img_name.upper()}: " + JSON.stringify(result));
        }})();
        """
        out = exec_js(ocr_js, wait=3.0, expected_token=f"OCR_RESULT_{img_name.upper()}:")
        for line in out.splitlines():
            if f"OCR_RESULT_{img_name.upper()}:" in line:
                json_str = line.split(f"OCR_RESULT_{img_name.upper()}:")[1].strip()
                if " -- line " in json_str:
                    json_str = json_str.rsplit(" -- line ", 1)[0].strip()
                ocr_results[img_name] = json.loads(json_str)

    print(f"  Receipt OCR: hasText={ocr_results['receipt']['hasText']}, conf={ocr_results['receipt']['confidenceStr']}, lines={ocr_results['receipt']['lineCount']}, words={ocr_results['receipt']['wordCount']}")
    print(f"  Invoice OCR: hasText={ocr_results['invoice']['hasText']}, conf={ocr_results['invoice']['confidenceStr']}, lines={ocr_results['invoice']['lineCount']}, words={ocr_results['invoice']['wordCount']}")
    print(f"  Unknown OCR: hasText={ocr_results['unknown']['hasText']}, heading='{ocr_results['unknown']['heading']}', reason='{ocr_results['unknown']['limitationReason']}'")

    assert ocr_results["receipt"]["hasText"] is True, "Receipt should detect text"
    assert ocr_results["invoice"]["hasText"] is True, "Invoice should detect text"
    assert ocr_results["unknown"]["hasText"] is False, "Unknown image must honestly report no text"
    assert ocr_results["unknown"]["limitationReason"] != "", "Unknown must report limitation reason"

    # Assert ground-truth keyword matching on extracted body text
    receipt_body = ocr_results["receipt"]["body"].upper()
    receipt_matches = [w for w in ["COFFEE", "ROASTERS", "MINERAL", "WATER", "TAX", "CHANGE", "DUE"] if w in receipt_body]
    print(f"  Receipt ground-truth matched words: {receipt_matches} ({len(receipt_matches)}/7)")
    assert len(receipt_matches) >= 5, f"OCR on receipt failed ground-truth matching: {receipt_matches}"

    invoice_body = ocr_results["invoice"]["body"].upper()
    invoice_matches = [w for w in ["ACME", "SOLUTIONS", "INVOICE", "NUMBER", "SECURITY", "OCR"] if w in invoice_body]
    print(f"  Invoice ground-truth matched words: {invoice_matches} ({len(invoice_matches)}/6)")
    assert len(invoice_matches) >= 4, f"OCR on invoice failed ground-truth matching: {invoice_matches}"

    # Save authentic OCR extraction evidence
    ocr_evidence_path = os.path.join(REVIEW_OUTPUT_DIR, "DocErena_OCR_Extracted.txt")
    with open(ocr_evidence_path, "w", encoding="utf-8") as f:
        f.write("[DocErena Authentic On-Device Offline OCR Result]\n")
        f.write(f"Target APK: {PACKAGE} (v5.0.0-phonetest)\n")
        f.write("Engine: DocErena Authentic On-Device Offline OCR Engine (DocErenaOCR)\n")
        f.write("Offline Architecture: 100% Pure JavaScript Raster Pattern Matcher (Zero Cloud, Zero Internet)\n")
        f.write("Bundled Tesseract Status: UNUSED (Chromium file:/// sandbox restrictions prevent Fetch API / WASM Web Workers)\n\n")
        f.write(f"--- TEST RECEIPT (test_receipt.png) ---\n")
        f.write(f"Confidence: {ocr_results['receipt']['confidenceStr']}\n")
        f.write(f"Line Count: {ocr_results['receipt']['lineCount']}\n")
        f.write(f"Word Count: {ocr_results['receipt']['wordCount']}\n")
        f.write(f"Detected Bounding Boxes: {ocr_results['receipt']['detectedBoundingBoxes']}\n")
        f.write(f"Extracted Body:\n{ocr_results['receipt']['body']}\n\n")
        f.write(f"--- TEST INVOICE (test_invoice.png) ---\n")
        f.write(f"Confidence: {ocr_results['invoice']['confidenceStr']}\n")
        f.write(f"Line Count: {ocr_results['invoice']['lineCount']}\n")
        f.write(f"Word Count: {ocr_results['invoice']['wordCount']}\n")
        f.write(f"Detected Bounding Boxes: {ocr_results['invoice']['detectedBoundingBoxes']}\n")
        f.write(f"Extracted Body:\n{ocr_results['invoice']['body']}\n\n")
        f.write(f"--- TEST UNKNOWN (test_unknown.png) ---\n")
        f.write(f"hasText: {ocr_results['unknown']['hasText']}\n")
        f.write(f"Heading: {ocr_results['unknown']['heading']}\n")
        f.write(f"Limitation Reason: {ocr_results['unknown']['limitationReason']}\n")
    print(f"  ✓ Saved authentic OCR test evidence to {ocr_evidence_path}")
    print("  ✓ ISSUE 1 RESOLVED: Tested on multiple images against ground truth, documented unused Tesseract status!")

    print("\n" + "=" * 80)
    print(" ALL DEFECT FIXES & PIPELINE VERIFICATIONS PASSED 100% ON LIVE EMULATOR!")
    print("=" * 80)
    return True

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
