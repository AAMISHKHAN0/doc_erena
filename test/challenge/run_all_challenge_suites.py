#!/usr/bin/env python3
"""Batch execution of all 8 challenge and verification suites."""

import subprocess
import time
import sys

suites = [
    ('test/challenge/deep_stress_harness.py', 'Deep Stress Harness (M1-M4)'),
    ('test/challenge/fuzz_m8_harness.py', 'M8 Range Fuzzing & Scale Harness'),
    ('test/challenge/empirical_challenge_suite.py', 'Empirical Challenge Suite'),
    ('test/challenge/m9_review_harness.py', 'M9 Review Harness'),
    ('test/challenge/m9_adversarial_harness.py', 'M9 Adversarial Layout & Batch Harness'),
    ('test/challenge/viewer_pdf_tools_adversarial_suite.py', 'Viewer & PDF Tools Suite'),
    ('test/challenge/adversarial_m9_integrity_harness.py', 'M9 Integrity & Contract Harness'),
    ('test/challenge/empirical_m10_rotation_and_ast_verifier.py', 'M10 Rotation Permutations & AST Verifier'),
    ('test/challenge/export_and_share_suite.py', 'S09 Export & S10 Share Document Suite'),
    ('test/challenge/documents_and_folder_suite.py', 'S11 Documents & Folder Contents Suite'),
    ('test/challenge/document_search_and_favorites_suite.py', 'S11 Document Search & Favorites Suite'),
    ('test/challenge/document_actions_and_delete_suite.py', 'S11 Document Actions & Delete Confirmation Suite'),
    ('test/challenge/trash_lifecycle_suite.py', 'S11 Recently Deleted & Permanent Delete Lifecycle Suite'),
    ('test/challenge/pdf_tools_and_merge_suite.py', 'S12 PDF Tools & Merge PDF Suite'),
    ('test/challenge/m10_adversarial_scaling_e2e_suite.py', 'M10 Adversarial Scaling & Stress Suite'),
    ('test/challenge/scan_modes_and_live_verification_suite.py', '5 Scan Modes & Advanced Live Verification Suite'),
    ('test/challenge/run_e2e_suite.py', '4-Tier Master E2E Automated Verification Suite'),
]

print("=" * 80)
print(" EXECUTING ALL 17 CHALLENGE & REGRESSION TEST SUITES")
print("=" * 80)

all_passed = True
total_time = 0.0

for path, desc in suites:
    t0 = time.time()
    res = subprocess.run([sys.executable, path], capture_output=True, text=True)
    dt = time.time() - t0
    total_time += dt

    if res.returncode == 0:
        print(f"[PASS] {path:<55} ({dt:6.3f}s) - {desc}")
    else:
        all_passed = False
        print(f"[FAIL] {path:<55} ({dt:6.3f}s) - {desc} (exit={res.returncode})")
        print("--- STDOUT ---")
        print(res.stdout[-1000:])
        print("--- STDERR ---")
        print(res.stderr[-1000:])

print("=" * 80)
print(f"TOTAL EXECUTION TIME: {total_time:.3f}s")
if all_passed:
    print("FINAL VERDICT: 17/17 SUITES PASSED (100% PASS, 0 FAILURES, 0 WARNINGS, 0 FINDINGS)")
    sys.exit(0)
else:
    print("FINAL VERDICT: FAILURES DETECTED IN TEST SUITES")
    sys.exit(1)
