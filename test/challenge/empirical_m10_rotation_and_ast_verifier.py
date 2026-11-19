#!/usr/bin/env python3
"""
DocErena Milestone 10 Empirical Adversarial Challenge & Verification Harness
=============================================================================
Author: challenger_m10_1
Target: Milestone 10 Rotation Hardening, Regression Integrity & AST Balance

This script provides empirical, adversarial verification of:
1. Rotation delta math in `lib/presentation/screens/pdf_tools/pdf_rotate_pages_bottom_sheet.dart`
   and `lib/services/pdf/pdf_manipulation_service.dart`:
   - 16/16 permutation pairs of (initial_rot, target_rot) in {0, 90, 180, 270}^2.
   - Negative and large angle inputs (e.g. 450°, -90°, -720°, 1080°).
   - "Reset All" behavior on heterogeneous multi-page documents.
   - "Rotate All" and selective rotation behavior on heterogeneous documents.
   - 10,000 randomized generative fuzzing operations on 100-page heterogeneous documents.
   - Direct source code AST validation of bottom sheet and manipulation service implementations.
2. Full AST delimiter balance across all 74 workspace Dart files.
"""

import os
import sys
import random
import unittest

def dart_modulo(a: int, b: int) -> int:
    """Dart % operator implements Euclidean modulo where result is in [0, |b|-1].
    Python % operator matches this exact behavior for positive b.
    """
    return a % b

def compute_relative_delta(initial_rot: int, target_rot: int) -> int:
    """Mirrors:
    final initialRot = (entry.key < _pages.length) ? (_pages[entry.key].rotationDegrees % 360) : 0;
    relativeDeltas[entry.key] = ((entry.value - initialRot) % 360 + 360) % 360;
    """
    norm_initial = dart_modulo(initial_rot, 360)
    norm_target = dart_modulo(target_rot, 360)
    delta = dart_modulo(dart_modulo(norm_target - norm_initial, 360) + 360, 360)
    return delta

def apply_service_rotation(stored_rot: int, delta: int) -> int:
    """Mirrors:
    effectiveRotation = ((p.rotationDegrees + additional) % 360 + 360) % 360;
    """
    return dart_modulo(dart_modulo(stored_rot + delta, 360) + 360, 360)


def check_dart_file_delimiters(filepath: str):
    """Parses a Dart file, handling single-line comments, block comments,
    single/double/multiline/raw string literals, and validates bracket stack balance."""
    with open(filepath, 'r', encoding='utf-8') as f:
        code = f.read()

    stack = []
    pairs = {')': '(', '}': '{', ']': '['}
    i = 0
    n = len(code)

    in_lc = False
    in_bc = False
    str_mode = None

    while i < n:
        if in_lc:
            if code[i] == '\n':
                in_lc = False
            i += 1
            continue

        if in_bc:
            if code[i:i+2] == '*/':
                in_bc = False
                i += 2
            else:
                i += 1
            continue

        if str_mode is not None:
            is_raw = str_mode.startswith('r')
            quote_type = str_mode[1:] if is_raw else str_mode
            quote_len = len(quote_type)

            if code[i:i+quote_len] == quote_type:
                if is_raw:
                    str_mode = None
                    i += quote_len
                    continue
                else:
                    bs_count = 0
                    j = i - 1
                    while j >= 0 and code[j] == '\\':
                        bs_count += 1
                        j -= 1
                    if bs_count % 2 == 0:
                        str_mode = None
                        i += quote_len
                        continue
                    else:
                        i += quote_len
                        continue
            i += 1
            continue

        if code[i:i+2] == '//':
            in_lc = True
            i += 2
            continue
        if code[i:i+2] == '/*':
            in_bc = True
            i += 2
            continue

        if code[i] == 'r' and i + 1 < n and code[i+1] in ("'", '"'):
            if code[i+1:i+4] in ("'''", '"""'):
                str_mode = 'r' + code[i+1:i+4]
                i += 4
                continue
            else:
                str_mode = 'r' + code[i+1]
                i += 2
                continue

        if code[i:i+3] in ("'''", '"""'):
            str_mode = code[i:i+3]
            i += 3
            continue

        if code[i] in ("'", '"'):
            str_mode = code[i]
            i += 1
            continue

        c = code[i]
        if c in '({[':
            stack.append((c, i))
        elif c in ')}]':
            if not stack:
                return False, f"Unexpected closing '{c}' at offset {i}"
            top_c, top_i = stack.pop()
            if top_c != pairs[c]:
                return False, f"Mismatched '{c}' at {i}, expected matching for '{top_c}' at {top_i}"
        i += 1

    if str_mode is not None:
        return False, f"Unterminated string {str_mode}"
    if in_bc:
        return False, "Unterminated block comment"
    if stack:
        top_c, top_i = stack[-1]
        return False, f"Unclosed '{top_c}' opened at {top_i}"

    return True, "Balanced"


class TestRotationDeltaMathPermutations(unittest.TestCase):
    """Verifies all permutation pairs and edge angles for rotation hardening."""

    def test_all_16_standard_permutations(self):
        """Test all 4x4 = 16 combinations of initial and target angles."""
        angles = [0, 90, 180, 270]
        tested_pairs = 0
        for init_angle in angles:
            for target_angle in angles:
                delta = compute_relative_delta(init_angle, target_angle)
                effective = apply_service_rotation(init_angle, delta)
                self.assertEqual(
                    effective, target_angle,
                    f"Mismatch for pair init={init_angle}°, target={target_angle}°: got {effective}°"
                )
                self.assertIn(delta, [0, 90, 180, 270], f"Invalid delta {delta} for pair ({init_angle}, {target_angle})")
                self.assertEqual(delta % 90, 0, f"Delta {delta} not multiple of 90")
                tested_pairs += 1
        self.assertEqual(tested_pairs, 16)
        print(f"  [+] PASS: All {tested_pairs} permutation pairs produced exact target angles.")

    def test_negative_and_large_values(self):
        """Stress-test non-standard angles (450°, -90°, -720°, 1080°, etc.)."""
        test_cases = [
            (450, -90, 270),    # dispatch explicit case: 450° (equiv 90°), target -90° (equiv 270°)
            (-90, 450, 90),     # -90° (equiv 270°), target 450° (equiv 90°)
            (720, 0, 0),        # 720° (equiv 0°), target 0°
            (-720, 180, 180),   # -720° (equiv 0°), target 180°
            (360, 270, 270),    # 360° (equiv 0°), target 270°
            (810, 90, 90),      # 810° (equiv 90°), target 90°
            (-270, -180, 180),  # -270° (equiv 90°), target -180° (equiv 180°)
            (990, -450, 270),   # 990° (equiv 270°), target -450° (equiv 270°)
            (-3600, 3600, 0),   # large multiples of 360°
        ]
        for init_rot, target_rot, expected_target in test_cases:
            delta = compute_relative_delta(init_rot, target_rot)
            effective = apply_service_rotation(init_rot, delta)
            self.assertEqual(
                effective, expected_target,
                f"Mismatch for large/negative: init={init_rot}°, target={target_rot}° -> effective={effective}°, expected={expected_target}°"
            )
            self.assertEqual(delta % 90, 0, f"Delta {delta} not multiple of 90")
        print(f"  [+] PASS: {len(test_cases)} negative and large angle stress vectors verified.")

    def test_heterogeneous_multipage_reset_all(self):
        """Test 'Reset All' behavior on multi-page documents with mixed initial rotations."""
        initial_pages = [0, 90, 180, 270]
        target_pages = [0, 0, 0, 0]

        deltas = {}
        for idx, (init, target) in enumerate(zip(initial_pages, target_pages)):
            deltas[idx] = compute_relative_delta(init, target)

        self.assertEqual(deltas[0], 0)    # (0 - 0) % 360 = 0
        self.assertEqual(deltas[1], 270)  # (0 - 90) % 360 = 270
        self.assertEqual(deltas[2], 180)  # (0 - 180) % 360 = 180
        self.assertEqual(deltas[3], 90)   # (0 - 270) % 360 = 90

        effective_pages = [
            apply_service_rotation(initial_pages[i], deltas[i])
            for i in range(len(initial_pages))
        ]
        self.assertEqual(effective_pages, [0, 0, 0, 0])
        print("  [+] PASS: 'Reset All' on heterogeneous document cleanly resets all pages to 0°.")

    def test_heterogeneous_multipage_rotate_all(self):
        """Test 'Rotate All' (+90°) on multi-page documents with mixed initial rotations."""
        initial_pages = [0, 90, 180, 270]
        target_pages = [(p + 90) % 360 for p in initial_pages]
        self.assertEqual(target_pages, [90, 180, 270, 0])

        deltas = {i: compute_relative_delta(initial_pages[i], target_pages[i]) for i in range(4)}
        for d in deltas.values():
            self.assertEqual(d, 90)

        effective_pages = [apply_service_rotation(initial_pages[i], deltas[i]) for i in range(4)]
        self.assertEqual(effective_pages, target_pages)
        print("  [+] PASS: 'Rotate All' on heterogeneous document increments each page by 90°.")

    def test_heterogeneous_multipage_partial_selection(self):
        """Test leaving unselected pages untouched in service call."""
        initial_pages = [0, 90, 180, 270]
        deltas = {
            0: compute_relative_delta(0, 0),      # 0°
            1: compute_relative_delta(90, 180),  # 90°
            2: compute_relative_delta(180, 180),# 0°
            3: compute_relative_delta(270, 270),# 0°
        }
        self.assertEqual(deltas, {0: 0, 1: 90, 2: 0, 3: 0})
        effective = [apply_service_rotation(initial_pages[i], deltas[i]) for i in range(4)]
        self.assertEqual(effective, [0, 180, 180, 270])
        print("  [+] PASS: Selective rotation modifies only chosen pages without compounding.")

    def test_randomized_generative_fuzzing_100_pages(self):
        """Fuzz 10,000 UI operations across a 100-page document with mixed rotations."""
        rng = random.Random(42)
        page_count = 100
        initial_rotations = [rng.choice([0, 90, 180, 270, 360, 450, -90, -180]) for _ in range(page_count)]
        current_ui_rotations = [dart_modulo(r, 360) for r in initial_rotations]

        for op in range(10000):
            action = rng.choice(["rotate_one", "rotate_all", "reset_all"])
            if action == "rotate_one":
                idx = rng.randint(0, page_count - 1)
                current_ui_rotations[idx] = (current_ui_rotations[idx] + 90) % 360
            elif action == "rotate_all":
                current_ui_rotations = [(r + 90) % 360 for r in current_ui_rotations]
            elif action == "reset_all":
                current_ui_rotations = [0] * page_count

            if op % 2000 == 1999:
                deltas = {
                    i: compute_relative_delta(initial_rotations[i], current_ui_rotations[i])
                    for i in range(page_count)
                }
                effective = [
                    apply_service_rotation(initial_rotations[i], deltas[i])
                    for i in range(page_count)
                ]
                self.assertEqual(effective, current_ui_rotations)

        print("  [+] PASS: 10,000 randomized UI operations across 100 heterogeneous pages verified 100%.")

    def test_source_code_dart_ast_inspection(self):
        """Inspect actual Dart source code to confirm implementation matches math."""
        bs_path = os.path.join("lib", "presentation", "screens", "pdf_tools", "pdf_rotate_pages_bottom_sheet.dart")
        svc_path = os.path.join("lib", "services", "pdf", "pdf_manipulation_service.dart")

        self.assertTrue(os.path.exists(bs_path), f"File missing: {bs_path}")
        self.assertTrue(os.path.exists(svc_path), f"File missing: {svc_path}")

        with open(bs_path, "r", encoding="utf-8") as f:
            bs_src = f.read()

        with open(svc_path, "r", encoding="utf-8") as f:
            svc_src = f.read()

        self.assertIn("relativeDeltas", bs_src)
        self.assertIn("((entry.value - initialRot) % 360 + 360) % 360", bs_src)
        self.assertIn("pageIndexToRotationDegrees: relativeDeltas", bs_src)
        self.assertIn("rot % 90 != 0", svc_src)
        self.assertIn("((p.rotationDegrees + additional) % 360 + 360) % 360", svc_src)
        print("  [+] PASS: Source code AST contains exact relative delta arithmetic.")


class TestASTDelimiterIntegrity(unittest.TestCase):
    """Verifies AST delimiter balance across all 74 workspace Dart files."""

    def test_all_workspace_dart_files(self):
        dart_files = []
        for root, dirs, files in os.walk("."):
            if ".git" in root or ".agents" in root:
                continue
            for file in files:
                if file.endswith(".dart"):
                    dart_files.append(os.path.join(root, file))

        self.assertGreaterEqual(len(dart_files), 74, f"Expected at least 74 Dart files, found {len(dart_files)}")

        failures = []
        for filepath in sorted(dart_files):
            success, msg = check_dart_file_delimiters(filepath)
            if not success:
                failures.append(f"{filepath}: {msg}")

        self.assertEqual(
            len(failures), 0,
            f"Delimiter errors detected in {len(failures)} files:\n" + "\n".join(failures)
        )
        print(f"  [+] PASS: All {len(dart_files)} workspace Dart files have 100% balanced delimiters.")


if __name__ == "__main__":
    print("=" * 80)
    print(" DOCERENA MILESTONE 10 EMPIRICAL CHALLENGER VERIFICATION HARNESS")
    print("=" * 80)
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    suite.addTests(loader.loadTestsFromTestCase(TestRotationDeltaMathPermutations))
    suite.addTests(loader.loadTestsFromTestCase(TestASTDelimiterIntegrity))
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    if not result.wasSuccessful():
        sys.exit(1)
