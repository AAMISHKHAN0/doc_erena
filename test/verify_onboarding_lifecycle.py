import subprocess
import time
import xml.etree.ElementTree as ET

ADB = r"C:\Users\Aamishkhan\AppData\Local\Android\Sdk\platform-tools\adb.exe"
SERIAL = "emulator-5554"
PKG = "com.digitalerena.docerena"
ACTIVITY = f"{PKG}/.MainActivity"

def adb(args):
    res = subprocess.run([ADB, "-s", SERIAL] + args, capture_output=True, text=True)
    return res.stdout.strip()

def get_screen_nodes():
    adb(["shell", "uiautomator", "dump", "/data/local/tmp/d.xml"])
    s = adb(["shell", "cat", "/data/local/tmp/d.xml"])
    try:
        root = ET.fromstring(s)
        nodes = []
        for node in root.iter():
            text = node.attrib.get("text") or node.attrib.get("content-desc") or ""
            bounds = node.attrib.get("bounds", "")
            if text or bounds:
                nodes.append((text, bounds))
        return nodes
    except Exception as e:
        return []

def get_screen_texts():
    return [t for t, b in get_screen_nodes() if t]

def wait_for_text(pattern, timeout=25):
    t0 = time.time()
    while time.time() - t0 < timeout:
        texts = get_screen_texts()
        for t in texts:
            if pattern.lower() in t.lower():
                return True
        time.sleep(1)
    return False

def tap_node_by_text(pattern, timeout=10):
    t0 = time.time()
    while time.time() - t0 < timeout:
        nodes = get_screen_nodes()
        for text, bounds in nodes:
            if pattern.lower() in text.lower() and bounds:
                try:
                    pts = [int(p) for p in bounds.replace("][", ",").replace("[", "").replace("]", "").split(",")]
                    cx = (pts[0] + pts[2]) // 2
                    cy = (pts[1] + pts[3]) // 2
                    print(f"  Tapping '{text}' at ({cx}, {cy})")
                    adb(["shell", "input", "tap", str(cx), str(cy)])
                    return True
                except Exception as e:
                    print("Error parsing bounds:", bounds, e)
        time.sleep(1)
    return False

print("=== 1. Fresh Install / Reset ===")
adb(["shell", "am", "force-stop", "com.google.android.photopicker"])
adb(["shell", "pm", "clear", PKG])
adb(["shell", "settings", "put", "secure", "accessibility_enabled", "1"])
adb(["shell", "am", "start", "-S", "-W", "-n", ACTIVITY])

assert wait_for_text("Let's get started", timeout=25), "Welcome screen missing after fresh install!"
t1 = get_screen_texts()
print("Screen 1 Texts:", t1[:6])
print("PASS: Welcome screen displayed on fresh install.")

print("\n=== 2. Tap Let's get started ===")
assert tap_node_by_text("Let's get started"), "Could not find 'Let's get started' button!"
assert wait_for_text("Scan in seconds", timeout=10), "Onboarding 1 missing!"
t2 = get_screen_texts()
print("Screen 2 Texts:", t2[:6])
print("PASS: Onboarding 1 displayed.")

print("\n=== 3. Tap Next ===")
# On Onboarding 1, tap 'Next'
assert tap_node_by_text("Next"), "Could not find 'Next' button!"
assert wait_for_text("Edit and organize", timeout=10), "Onboarding 2 missing!"
t3 = get_screen_texts()
print("Screen 3 Texts:", t3[:6])
print("PASS: Onboarding 2 displayed.")

print("\n=== 4. Tap Go to home ===")
assert tap_node_by_text("Go to home"), "Could not find 'Go to home' button!"
assert wait_for_text("Recent documents", timeout=10), "Home screen missing!"
t4 = get_screen_texts()
print("Screen 4 Texts:", t4[:8])
assert any("Your documents" in str(t) or "Recent documents" in str(t) for t in t4), "Home screen missing!"
print("PASS: Home screen displayed.")

print("\n=== 5. Force stop and restart (verify onboarding persistence) ===")
adb(["shell", "am", "force-stop", PKG])
time.sleep(1)
adb(["shell", "am", "start", "-S", "-W", "-n", ACTIVITY])
assert wait_for_text("documents", timeout=20), "Home screen did not appear on restart!"
t5 = get_screen_texts()
print("Screen 5 Texts:", t5[:8])
assert not any("Let's get started" in str(t) for t in t5), "Welcome screen re-appeared for returning user!"
assert any("Your documents" in str(t) or "Recent documents" in str(t) for t in t5), "Home persistence failed!"
print("PASS: Onboarding persisted across process death and restart.")

print("\n=== 6. Replay Onboarding from Settings ===")
# Tap Settings icon/gear at top right (bounds approx [900, 150][1040, 290])
settings_tapped = False
for text, bounds in get_screen_nodes():
    if "settings" in text.lower() or "gear" in text.lower():
        pts = [int(p) for p in bounds.replace("][", ",").replace("[", "").replace("]", "").split(",")]
        adb(["shell", "input", "tap", str((pts[0]+pts[2])//2), str((pts[1]+pts[3])//2)])
        settings_tapped = True
        break
if not settings_tapped:
    # Tap Settings gear at (965, 220)
    adb(["shell", "input", "tap", "965", "220"])

assert wait_for_text("Settings", timeout=10), "Failed to open Settings screen!"
time.sleep(1)

# Scroll down to ensure 'Welcome & Tutorial' is visible
adb(["shell", "input", "swipe", "540", "1600", "540", "600", "300"])
time.sleep(1)

assert tap_node_by_text("Welcome & Tutorial") or tap_node_by_text("Replay"), "Could not tap Welcome & Tutorial button!"
assert wait_for_text("Let's get started", timeout=10), "Replay onboarding did not navigate to Welcome screen!"
t6 = get_screen_texts()
print("Screen 6 Texts:", t6[:6])
print("PASS: Replay onboarding works successfully.")

print("\n>>> ALL ONBOARDING & PERSISTENCE TESTS PASSED! <<<")

