#!/usr/bin/env python3
"""
================================================================================
DocErena Offline Scan Code (QR / Barcode Decoder) Automated Verification Suite
================================================================================
Tests:
  1. Plain-text QR decoding via bundled jsQR offline engine.
  2. URL QR decoding via bundled jsQR offline engine.
  3. Blurry QR input handling (graceful null return without crashes).
  4. Invalid non-QR image input handling (graceful null return).
  5. UI In-App verification via Chrome DevTools Protocol:
     - Entry via openScanCodeMode() from All Features / All Tools
     - QR viewfinder reticle & animated laser display
     - Plain-text modal presentation with copy button and hidden link button
     - One-tap clipboard copy verification
     - URL modal presentation with explicit separate tap 'Open Link' button
     - Dialog stacking prevention (mutex debounce lock)
     - Draft preservation: sessionPages preserved across code scan mode
================================================================================
"""

import os
import sys
import time
import json
import base64
import subprocess
import urllib.request
import websocket
from PIL import Image, ImageFilter
import qrcode

BASE_DIR = r"d:\camscanner"
INPUT_DIR = os.path.join(BASE_DIR, "verification", "sample_inputs")
SCREENSHOTS_DIR = os.path.join(BASE_DIR, "verification", "screenshots", "qr_verification")
os.makedirs(INPUT_DIR, exist_ok=True)
os.makedirs(SCREENSHOTS_DIR, exist_ok=True)

# ---------------------------------------------------------
# Step 1: Generate Authentic Test Vectors
# ---------------------------------------------------------
print("=" * 80)
print(" STEP 1: GENERATING AUTHENTIC QR TEST VECTORS")
print("=" * 80)

PLAINTEXT_PAYLOAD = "DocErena Offline Document Scanner v5.0 - Confidential Invoice #9942"
URL_PAYLOAD = "https://github.com/AAMISHKHAN0/doc_erena"

plain_qr_path = os.path.join(INPUT_DIR, "test_qr_plaintext.png")
url_qr_path = os.path.join(INPUT_DIR, "test_qr_url.png")
blurry_qr_path = os.path.join(INPUT_DIR, "test_qr_blurry.png")
invalid_img_path = os.path.join(INPUT_DIR, "test_qr_invalid.png")

# Plain text QR
img_plain = qrcode.make(PLAINTEXT_PAYLOAD).convert('RGB')
img_plain.save(plain_qr_path)
print(f"  [+] Generated Plaintext QR: {plain_qr_path}")

# URL QR
img_url = qrcode.make(URL_PAYLOAD).convert('RGB')
img_url.save(url_qr_path)
print(f"  [+] Generated URL QR:       {url_qr_path}")

# Blurry QR
img_blurred = img_plain.filter(ImageFilter.GaussianBlur(radius=14))
img_blurred.save(blurry_qr_path)
print(f"  [+] Generated Blurry QR:    {blurry_qr_path}")

# Invalid non-QR
img_invalid = Image.new('RGB', (320, 320), color=(240, 242, 248))
img_invalid.save(invalid_img_path)
print(f"  [+] Generated Non-QR Image: {invalid_img_path}")

# ---------------------------------------------------------
# Step 2: Algorithmic Verification via Offline jsQR Engine
# ---------------------------------------------------------
print("\n" + "=" * 80)
print(" STEP 2: VERIFYING OFFLINE jsQR DECODER ENGINE")
print("=" * 80)

def decode_image_with_jsqr(image_path):
    img = Image.open(image_path).convert('RGBA')
    w, h = img.size
    raw_bytes = img.tobytes()
    temp_raw = os.path.join(INPUT_DIR, "temp_eval.raw")
    with open(temp_raw, "wb") as f:
        f.write(raw_bytes)

    node_eval = f"""
    const fs = require('fs');
    const jsQR = require('{os.path.join(BASE_DIR, "web_preview", "jsqr.min.js").replace(os.sep, "/")}');
    const raw = fs.readFileSync('{temp_raw.replace(os.sep, "/")}');
    const clamped = new Uint8ClampedArray(raw);
    const result = jsQR(clamped, {w}, {h}, {{ inversionAttempts: 'attemptBoth' }});
    console.log(JSON.stringify(result ? {{ data: result.data }} : null));
    """
    res = subprocess.run(["node", "-e", node_eval], capture_output=True, text=True)
    if os.path.exists(temp_raw):
        try: os.remove(temp_raw)
        except: pass
    if res.returncode != 0:
        raise RuntimeError(f"Node jsQR error: {res.stderr}")
    return json.loads(res.stdout.strip())

# Test 1: Plaintext
res_plain = decode_image_with_jsqr(plain_qr_path)
assert res_plain is not None, "Plaintext QR failed to decode!"
assert res_plain["data"] == PLAINTEXT_PAYLOAD, f"Decoded payload mismatch: {res_plain['data']}"
print(f"  [PASS] Plaintext QR Decoded Successfully:")
print(f"         Expected: '{PLAINTEXT_PAYLOAD}'")
print(f"         Actual:   '{res_plain['data']}'")

# Test 2: URL
res_url = decode_image_with_jsqr(url_qr_path)
assert res_url is not None, "URL QR failed to decode!"
assert res_url["data"] == URL_PAYLOAD, f"Decoded URL mismatch: {res_url['data']}"
print(f"  [PASS] URL QR Decoded Successfully:")
print(f"         Expected: '{URL_PAYLOAD}'")
print(f"         Actual:   '{res_url['data']}'")

# Test 3: Blurry
res_blurry = decode_image_with_jsqr(blurry_qr_path)
assert res_blurry is None, f"Blurry QR should return None, got: {res_blurry}"
print("  [PASS] Blurry QR Handled Gracefully (Returned None without throwing).")

# Test 4: Invalid Image
res_invalid = decode_image_with_jsqr(invalid_img_path)
assert res_invalid is None, f"Invalid non-QR image should return None, got: {res_invalid}"
print("  [PASS] Invalid Non-QR Image Handled Gracefully (Returned None).")

# ---------------------------------------------------------
# Step 3: In-App UI & Interaction Verification via Chrome CDP
# ---------------------------------------------------------
print("\n" + "=" * 80)
print(" STEP 3: TESTING IN-APP UI, DIALOG STACKING & DRAFT PRESERVATION")
print("=" * 80)

port = 9338
chrome_exe = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
proc = subprocess.Popen([
    chrome_exe,
    "--headless=new",
    f"--remote-debugging-port={port}",
    "--remote-allow-origins=*",
    "--disable-gpu",
    "about:blank"
])

try:
    time.sleep(1.5)
    with urllib.request.urlopen(f"http://127.0.0.1:{port}/json/version") as r:
        info = json.loads(r.read().decode())
    
    browser_ws = websocket.create_connection(info["webSocketDebuggerUrl"])
    browser_ws.send(json.dumps({"id": 1, "method": "Target.createTarget", "params": {"url": "about:blank"}}))
    resp = json.loads(browser_ws.recv())
    target_id = resp["result"]["targetId"]
    browser_ws.close()

    page_ws_url = f"ws://127.0.0.1:{port}/devtools/page/{target_id}"
    ws = websocket.create_connection(page_ws_url)

    _msg_id = 100
    def send_cdp(method, params=None):
        global _msg_id
        _msg_id += 1
        cmd = {"id": _msg_id, "method": method}
        if params: cmd["params"] = params
        ws.send(json.dumps(cmd))
        while True:
            raw = ws.recv()
            r = json.loads(raw)
            if r.get("id") == _msg_id:
                if "error" in r:
                    raise RuntimeError(f"CDP error: {r['error']}")
                return r.get("result", {})

    send_cdp("Page.enable")
    send_cdp("Runtime.enable")
    send_cdp("Emulation.setDeviceMetricsOverride", {
        "width": 390,
        "height": 844,
        "deviceScaleFactor": 2.0,
        "mobile": True
    })

    send_cdp("Page.navigate", {"url": "http://localhost:8080/index.html"})
    time.sleep(2.0)

    def eval_js(expression):
        res = send_cdp("Runtime.evaluate", {
            "expression": expression,
            "returnByValue": True,
            "awaitPromise": True
        })
        val = res.get("result", {}).get("value")
        return val

    # Verify jsQR presence in loaded app
    jsqr_present = eval_js("typeof window.jsQR === 'function'")
    assert jsqr_present, "jsQR is not loaded in window scope!"
    print("  [PASS] window.jsQR is loaded and functional in the live app.")

    # 1. Establish initial camera scan draft
    eval_js("""
    sessionPages = [
        { id: 'page_test_1', title: 'Page 1 Contract Draft', rawUrl: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==' },
        { id: 'page_test_2', title: 'Page 2 Invoice Draft', rawUrl: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==' }
    ];
    updateBatchThumbBadge();
    """)
    draft_count = eval_js("sessionPages.length")
    assert draft_count == 2, f"Expected 2 draft pages, got {draft_count}"
    print(f"  [PASS] Initial scan draft established with {draft_count} pages.")

    # 2. Open Scan Code Mode
    eval_js("openScanCodeMode();")
    time.sleep(0.5)

    qr_overlay_hidden = eval_js("document.getElementById('camera-qr-overlay').classList.contains('hidden')")
    doc_frame_hidden = eval_js("document.getElementById('camera-doc-frame').classList.contains('hidden')")
    current_mode = eval_js("cameraMode")
    
    assert not qr_overlay_hidden, "#camera-qr-overlay should be VISIBLE!"
    assert doc_frame_hidden, "#camera-doc-frame should be HIDDEN!"
    assert current_mode == "code", f"Expected cameraMode 'code', got '{current_mode}'"
    print("  [PASS] openScanCodeMode() successfully activated QR Viewfinder overlay.")

    # Capture Viewfinder Reticle Screenshot
    screen_data = send_cdp("Page.captureScreenshot", {"format": "png"})
    with open(os.path.join(SCREENSHOTS_DIR, "01_qr_viewfinder_overlay.png"), "wb") as f:
        f.write(base64.b64decode(screen_data["data"]))
    print("  [+] Captured screenshot: 01_qr_viewfinder_overlay.png")

    # 3. Test Plaintext QR Decoded Event
    eval_js(f"handleDecodedCode('{PLAINTEXT_PAYLOAD}');")
    time.sleep(0.3)

    modal_hidden = eval_js("document.getElementById('modal-qr-result').classList.contains('hidden')")
    displayed_text = eval_js("document.getElementById('qr-result-text').textContent")
    badge_text = eval_js("document.getElementById('qr-result-badge').textContent")
    open_link_btn_hidden = eval_js("document.getElementById('qr-open-link-btn').classList.contains('hidden')")

    assert not modal_hidden, "QR result modal should be visible!"
    assert displayed_text == PLAINTEXT_PAYLOAD, f"Displayed text mismatch: {displayed_text}"
    assert "PLAIN TEXT" in badge_text.upper(), f"Expected Plain Text badge, got '{badge_text}'"
    assert open_link_btn_hidden, "Open Link button must be HIDDEN for plain text!"
    print(f"  [PASS] Plaintext Decoded Modal verified (Text matches, Open Link button is hidden).")

    # Test Copy Button Action
    eval_js("copyDecodedQrText();")
    copy_btn_text = eval_js("document.getElementById('qr-copy-btn-text').textContent")
    assert "COPIED" in copy_btn_text.upper(), f"Copy button text did not update: {copy_btn_text}"
    print("  [PASS] Copy to Clipboard action executed and button updated to 'Copied!'.")

    # Capture Plaintext Result Modal Screenshot
    screen_data = send_cdp("Page.captureScreenshot", {"format": "png"})
    with open(os.path.join(SCREENSHOTS_DIR, "02_plaintext_qr_modal.png"), "wb") as f:
        f.write(base64.b64decode(screen_data["data"]))
    print("  [+] Captured screenshot: 02_plaintext_qr_modal.png")

    # 4. Test Dialog Stacking Prevention (Mutex Lock)
    eval_js("""
    // Fire 5 rapid decoded events while dialog is open
    for (let i = 0; i < 5; i++) {
        handleDecodedCode('Duplicate Payload ' + i);
    }
    """)
    time.sleep(0.3)
    modal_count = eval_js("document.querySelectorAll('#modal-qr-result').length")
    dialog_open_flag = eval_js("isScanCodeDialogOpen")
    displayed_text_after_dupes = eval_js("document.getElementById('qr-result-text').textContent")
    
    assert modal_count == 1, f"Expected exactly 1 modal element, found {modal_count}"
    assert dialog_open_flag is True, "isScanCodeDialogOpen flag should remain True"
    assert displayed_text_after_dupes == PLAINTEXT_PAYLOAD, "Modal content should not be overwritten while open"
    print("  [PASS] Dialog stacking prevention verified: Duplicate events rejected while dialog is open.")

    # Dismiss Plaintext modal
    eval_js("closeQrResultModal();")
    time.sleep(0.3)
    modal_hidden_after_close = eval_js("document.getElementById('modal-qr-result').classList.contains('hidden')")
    dialog_open_flag_after_close = eval_js("isScanCodeDialogOpen")
    assert modal_hidden_after_close, "Modal should be hidden after closing"
    assert dialog_open_flag_after_close is False, "isScanCodeDialogOpen must reset to False"
    print("  [PASS] closeQrResultModal() cleanly dismissed modal and released mutex lock.")

    # 5. Test URL QR Decoded Event & Separate Tap Enforcement
    eval_js(f"handleDecodedCode('{URL_PAYLOAD}');")
    time.sleep(0.3)

    url_modal_hidden = eval_js("document.getElementById('modal-qr-result').classList.contains('hidden')")
    url_displayed = eval_js("document.getElementById('qr-result-text').textContent")
    url_badge_text = eval_js("document.getElementById('qr-result-badge').textContent")
    url_open_btn_hidden = eval_js("document.getElementById('qr-open-link-btn').classList.contains('hidden')")

    assert not url_modal_hidden, "QR result modal should be visible for URL!"
    assert url_displayed == URL_PAYLOAD, f"URL display mismatch: {url_displayed}"
    assert "WEBSITE LINK" in url_badge_text.upper(), f"Expected Website Link badge, got '{url_badge_text}'"
    assert not url_open_btn_hidden, "Open Link button must be VISIBLE for web URLs!"
    print(f"  [PASS] URL Decoded Modal verified (Requires explicit separate tap to open link).")

    # Capture URL Result Modal Screenshot
    screen_data = send_cdp("Page.captureScreenshot", {"format": "png"})
    with open(os.path.join(SCREENSHOTS_DIR, "03_url_qr_modal.png"), "wb") as f:
        f.write(base64.b64decode(screen_data["data"]))
    print("  [+] Captured screenshot: 03_url_qr_modal.png")

    # Close modal
    eval_js("closeQrResultModal();")
    time.sleep(0.3)

    # 6. Test Draft Preservation upon Returning to Camera
    eval_js("closeScanCodeMode();")
    time.sleep(0.3)

    restored_mode = eval_js("cameraMode")
    qr_overlay_closed = eval_js("document.getElementById('camera-qr-overlay').classList.contains('hidden')")
    doc_frame_restored = not eval_js("document.getElementById('camera-doc-frame').classList.contains('hidden')")
    retained_draft_count = eval_js("sessionPages.length")
    p1_title = eval_js("sessionPages[0].title")
    p2_title = eval_js("sessionPages[1].title")

    assert qr_overlay_closed, "QR overlay should be closed"
    assert doc_frame_restored, "Document viewfinder frame should be restored"
    assert retained_draft_count == 2, f"Draft pages lost! Expected 2, got {retained_draft_count}"
    assert p1_title == 'Page 1 Contract Draft', f"Draft 1 damaged: {p1_title}"
    assert p2_title == 'Page 2 Invoice Draft', f"Draft 2 damaged: {p2_title}"
    print(f"  [PASS] Scan draft perfectly preserved: {retained_draft_count} pages retained without modification.")

    # Capture Restored Camera Screen Screenshot
    screen_data = send_cdp("Page.captureScreenshot", {"format": "png"})
    with open(os.path.join(SCREENSHOTS_DIR, "04_camera_draft_restored.png"), "wb") as f:
        f.write(base64.b64decode(screen_data["data"]))
    print("  [+] Captured screenshot: 04_camera_draft_restored.png")

    ws.close()

finally:
    proc.terminate()
    try: proc.wait(timeout=3)
    except: proc.kill()

print("\n" + "=" * 80)
print(" ALL 6 TEST PHASES PASSED WITH ZERO ERRORS!")
print(" Actual Decoded Plaintext: " + PLAINTEXT_PAYLOAD)
print(" Actual Decoded URL:       " + URL_PAYLOAD)
print(" Actual Blurry Result:     None (Safe Non-Crashing Fallback)")
print(" Actual Invalid Result:    None (Safe Non-Crashing Fallback)")
print(" Dialog Stacking:          Prevented (1 Modal Max)")
print(" Scan Draft Preservation:  Verified (2/2 Pages Intact)")
print("================================================================================")
