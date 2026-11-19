"""
DocErena Empirical Challenge & Stress-Test Suite
Author: teamwork_challenger (Critic & Specialist)
Targets:
1. Atomic File Write Protocol (FileStorageService logic & stress harness)
2. SQLite Repository Engine & Draft Lifecycle (Schema DDL, atomic rollback, FK cascade, case-insensitive search)
3. PDF Generation & ISO 32000 Compliance (Header, EOF trailer, page counter regex, memory safety)
4. Share Security Boundaries (Path traversal, database blacklist, bypass attempts)
"""

import os
import sys
import time
import math
import re
import sqlite3
import tempfile
import shutil
import unittest
from pathlib import Path

# ==============================================================================
# 1. ATOMIC FILE WRITE PROTOCOL TEST HARNESS
# ==============================================================================

class AtomicWriteHarness:
    """Simulates and stress-tests FileStorageService.writeAtomic logic."""
    def __init__(self, base_dir: str):
        self.base_dir = base_dir

    def resolve_key(self, relative_key: str) -> str:
        # Replicate Dart normalize & path traversal check
        normalized = os.path.normpath(relative_key)
        # Note: on Windows, \root is root-relative; on POSIX /root is absolute
        if (normalized.startswith('..') or 
            os.path.isabs(normalized) or 
            normalized.startswith('\\') or 
            normalized.startswith('/')):
            raise ValueError(f"Directory traversal attempt: {relative_key}")
        return os.path.join(self.base_dir, normalized)

    def write_atomic(self, relative_key: str, data: bytes, simulate_disk_full: bool = False, simulate_crash_before_rename: bool = False):
        if len(data) == 0:
            return {"success": False, "error": "corruptedData", "message": "Refusing to write 0-byte file"}

        target_path = self.resolve_key(relative_key)
        os.makedirs(os.path.dirname(target_path), exist_ok=True)

        temp_path = f"{target_path}.tmp_{time.time_ns()}"
        temp_file_created = False
        try:
            with open(temp_path, "wb") as f:
                temp_file_created = True
                f.write(data)
                f.flush()
                os.fsync(f.fileno())

            # Verify written length
            written_length = os.path.getsize(temp_path)
            if simulate_disk_full or written_length != len(data):
                if os.path.exists(temp_path):
                    os.remove(temp_path)
                return {"success": False, "error": "diskFull", "message": "Incomplete write"}

            if simulate_crash_before_rename:
                raise RuntimeError("Simulated crash right before atomic rename")

            # Windows atomic replace / POSIX rename
            # os.replace is atomic on both POSIX and Windows (MoveFileEx with MOVEFILE_REPLACE_EXISTING)
            os.replace(temp_path, target_path)
            return {"success": True, "path": target_path}

        except Exception as e:
            # Cleanup on failure
            if temp_file_created and os.path.exists(temp_path):
                try:
                    os.remove(temp_path)
                except Exception:
                    pass
            return {"success": False, "error": "ioFailure", "message": str(e)}


class TestAtomicFileWriteProtocol(unittest.TestCase):
    def setUp(self):
        self.test_dir = tempfile.mkdtemp(prefix="docerena_atomic_test_")
        self.harness = AtomicWriteHarness(self.test_dir)

    def tearDown(self):
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_zero_byte_rejection(self):
        """Verify 0-byte write is rejected with corruptedData and leaves no trace."""
        res = self.harness.write_atomic("docs/doc1/empty.jpg", b"")
        self.assertFalse(res["success"])
        self.assertEqual(res["error"], "corruptedData")
        target_path = os.path.join(self.test_dir, "docs", "doc1", "empty.jpg")
        self.assertFalse(os.path.exists(target_path))
        # Ensure no temp files remain
        parent = os.path.dirname(target_path)
        if os.path.exists(parent):
            tmp_files = [f for f in os.listdir(parent) if ".tmp" in f]
            self.assertEqual(len(tmp_files), 0)

    def test_successful_atomic_write_and_fsync(self):
        """Verify .tmp staging, fsync flush, and atomic rename to target."""
        payload = b"GENUINE_DOCERENA_IMAGE_PAYLOAD_12345"
        key = "documents/doc_alpha/pages/p0_orig.jpg"
        res = self.harness.write_atomic(key, payload)
        self.assertTrue(res["success"])
        target_path = res["path"]
        self.assertTrue(os.path.exists(target_path))
        with open(target_path, "rb") as f:
            self.assertEqual(f.read(), payload)
        # Verify no .tmp files left
        parent = os.path.dirname(target_path)
        tmp_files = [f for f in os.listdir(parent) if ".tmp" in f]
        self.assertEqual(len(tmp_files), 0)

    def test_cleanup_on_failure(self):
        """Verify temporary file is immediately purged on crash/exception."""
        key = "documents/doc_alpha/pages/crash_page.jpg"
        res = self.harness.write_atomic(key, b"data", simulate_crash_before_rename=True)
        self.assertFalse(res["success"])
        self.assertEqual(res["error"], "ioFailure")
        target_path = os.path.join(self.test_dir, "documents", "doc_alpha", "pages", "crash_page.jpg")
        self.assertFalse(os.path.exists(target_path))
        parent = os.path.dirname(target_path)
        tmp_files = [f for f in os.listdir(parent) if ".tmp" in f]
        self.assertEqual(len(tmp_files), 0, "Leftover .tmp file detected after failed write!")

    def test_disk_full_simulation(self):
        """Verify incomplete write is flagged as diskFull and temp file cleaned up."""
        key = "documents/doc_alpha/pages/disk_full.jpg"
        res = self.harness.write_atomic(key, b"partial_data", simulate_disk_full=True)
        self.assertFalse(res["success"])
        self.assertEqual(res["error"], "diskFull")
        target_path = os.path.join(self.test_dir, "documents", "doc_alpha", "pages", "disk_full.jpg")
        self.assertFalse(os.path.exists(target_path))

    def test_directory_traversal_blocking(self):
        """Verify path traversal attacks throw exceptions and never escape base path."""
        attacks = [
            "../../etc/passwd",
            "../secret.txt",
            "/absolute/root/file.jpg",
            "documents/../../../system32/cmd.exe",
        ]
        for attack in attacks:
            with self.assertRaises(ValueError):
                self.harness.resolve_key(attack)


# ==============================================================================
# 2. SQLITE REPOSITORY & DRAFT LIFECYCLE TEST HARNESS
# ==============================================================================

DOCERENA_SCHEMA = """
PRAGMA foreign_keys = ON;

CREATE TABLE documents (
  id TEXT PRIMARY KEY NOT NULL,
  title TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('draft', 'saved')),
  deleted_at INTEGER DEFAULT NULL,
  schema_version INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE pages (
  id TEXT PRIMARY KEY NOT NULL,
  document_id TEXT NOT NULL,
  position INTEGER NOT NULL,
  original_file_key TEXT NOT NULL,
  crop_points TEXT NOT NULL,
  rotation_degrees INTEGER NOT NULL DEFAULT 0 CHECK(rotation_degrees IN (0, 90, 180, 270)),
  filter TEXT NOT NULL DEFAULT 'original' CHECK(filter IN ('original', 'color', 'grayscale', 'black_and_white')),
  brightness REAL NOT NULL DEFAULT 0.0,
  contrast REAL NOT NULL DEFAULT 1.0,
  processed_cache_key TEXT,
  pixel_width INTEGER NOT NULL,
  pixel_height INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  FOREIGN KEY(document_id) REFERENCES documents(id) ON DELETE CASCADE
);

CREATE TABLE exports (
  id TEXT PRIMARY KEY NOT NULL,
  document_id TEXT NOT NULL,
  type TEXT NOT NULL DEFAULT 'pdf',
  created_at INTEGER NOT NULL,
  temporary_file_key TEXT NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('in_progress', 'completed', 'failed')),
  FOREIGN KEY(document_id) REFERENCES documents(id) ON DELETE CASCADE
);

CREATE INDEX idx_pages_doc_pos ON pages(document_id, position ASC);
CREATE INDEX idx_docs_updated ON documents(updated_at DESC);
CREATE INDEX idx_docs_status ON documents(status);
"""

class TestSqliteRepositoryEngine(unittest.TestCase):
    def setUp(self):
        self.conn = sqlite3.connect(":memory:")
        self.conn.executescript(DOCERENA_SCHEMA)

    def tearDown(self):
        self.conn.close()

    def test_foreign_keys_pragmas_enabled(self):
        """Verify PRAGMA foreign_keys is strictly ON."""
        cur = self.conn.cursor()
        cur.execute("PRAGMA foreign_keys;")
        val = cur.fetchone()[0]
        self.assertEqual(val, 1)

    def test_foreign_key_orphan_rejection(self):
        """Verify child page cannot be inserted without a valid parent document."""
        cur = self.conn.cursor()
        with self.assertRaises(sqlite3.IntegrityError):
            cur.execute("""
                INSERT INTO pages (id, document_id, position, original_file_key, crop_points, pixel_width, pixel_height, created_at)
                VALUES ('p_orphan', 'non_existent_doc', 0, 'key', '[]', 100, 100, 1000);
            """)

    def test_foreign_key_cascading_deletion(self):
        """Verify deleting parent document cascade-deletes all associated pages and exports."""
        cur = self.conn.cursor()
        # 1. Insert doc
        cur.execute("""
            INSERT INTO documents (id, title, created_at, updated_at, status)
            VALUES ('doc_cascade', 'Parent Doc', 1000, 1000, 'saved');
        """)
        # 2. Insert 3 pages
        for i in range(3):
            cur.execute(f"""
                INSERT INTO pages (id, document_id, position, original_file_key, crop_points, pixel_width, pixel_height, created_at)
                VALUES ('p_{i}', 'doc_cascade', {i}, 'key_{i}', '[]', 1000, 1500, 1000);
            """)
        # 3. Insert export
        cur.execute("""
            INSERT INTO exports (id, document_id, temporary_file_key, status, created_at)
            VALUES ('exp_1', 'doc_cascade', 'cache/exports/exp_1.pdf', 'completed', 1000);
        """)
        self.conn.commit()

        # Check counts
        cur.execute("SELECT COUNT(*) FROM pages WHERE document_id = 'doc_cascade';")
        self.assertEqual(cur.fetchone()[0], 3)
        cur.execute("SELECT COUNT(*) FROM exports WHERE document_id = 'doc_cascade';")
        self.assertEqual(cur.fetchone()[0], 1)

        # 4. Delete document
        cur.execute("DELETE FROM documents WHERE id = 'doc_cascade';")
        self.conn.commit()

        # Check cascading deletion
        cur.execute("SELECT COUNT(*) FROM pages WHERE document_id = 'doc_cascade';")
        self.assertEqual(cur.fetchone()[0], 0, "Pages were not cascade-deleted by SQLite foreign key!")
        cur.execute("SELECT COUNT(*) FROM exports WHERE document_id = 'doc_cascade';")
        self.assertEqual(cur.fetchone()[0], 0, "Exports were not cascade-deleted by SQLite foreign key!")

    def test_atomic_transaction_rollback_on_failure(self):
        """Stress-test: simulate a failure halfway through saveDocumentAtomic. Verify 100% rollback."""
        cur = self.conn.cursor()
        now = int(time.time() * 1000)

        # We will attempt a transaction: insert doc, insert page 0, then page 1 with INVALID rotation (e.g. 45 degrees)
        failed = False
        try:
            with self.conn: # context manager initiates transaction and rolls back on exception
                cur.execute("""
                    INSERT INTO documents (id, title, created_at, updated_at, status)
                    VALUES ('doc_tx_fail', 'Faulty Doc', ?, ?, 'saved');
                """, (now, now))
                # Page 0 (valid)
                cur.execute("""
                    INSERT INTO pages (id, document_id, position, original_file_key, crop_points, rotation_degrees, pixel_width, pixel_height, created_at)
                    VALUES ('p_ok', 'doc_tx_fail', 0, 'key0', '[]', 0, 100, 100, ?);
                """, (now,))
                # Page 1 (INVALID rotation 45 violates CHECK constraint)
                cur.execute("""
                    INSERT INTO pages (id, document_id, position, original_file_key, crop_points, rotation_degrees, pixel_width, pixel_height, created_at)
                    VALUES ('p_bad', 'doc_tx_fail', 1, 'key1', '[]', 45, 100, 100, ?);
                """, (now,))
        except sqlite3.IntegrityError:
            failed = True

        self.assertTrue(failed, "CHECK constraint should have triggered IntegrityError")

        # Verify rollback: document and page 0 MUST NOT exist in database!
        cur.execute("SELECT COUNT(*) FROM documents WHERE id = 'doc_tx_fail';")
        self.assertEqual(cur.fetchone()[0], 0, "Document was partially committed despite failure!")
        cur.execute("SELECT COUNT(*) FROM pages WHERE document_id = 'doc_tx_fail';")
        self.assertEqual(cur.fetchone()[0], 0, "Page 0 was partially committed despite failure!")

    def test_draft_lifecycle_and_discarding(self):
        """Verify draft isolation, active draft retrieval, and discardDraft behavior."""
        cur = self.conn.cursor()
        now = int(time.time() * 1000)

        # 1. Insert saved document
        cur.execute("""
            INSERT INTO documents (id, title, created_at, updated_at, status)
            VALUES ('doc_saved', 'Saved Document', ?, ?, 'saved');
        """, (now, now))

        # 2. Insert draft document
        cur.execute("""
            INSERT INTO documents (id, title, created_at, updated_at, status)
            VALUES ('doc_draft', 'In-Progress Draft', ?, ?, 'draft');
        """, (now + 10, now + 10))
        cur.execute("""
            INSERT INTO pages (id, document_id, position, original_file_key, crop_points, pixel_width, pixel_height, created_at)
            VALUES ('p_draft_1', 'doc_draft', 0, 'key_draft', '[]', 500, 500, ?);
        """, (now + 10,))
        self.conn.commit()

        # getAllDocuments query: WHERE status = 'saved'
        cur.execute("SELECT id FROM documents WHERE status = 'saved' AND deleted_at IS NULL;")
        saved_ids = [r[0] for r in cur.fetchall()]
        self.assertIn('doc_saved', saved_ids)
        self.assertNotIn('doc_draft', saved_ids, "Draft must NEVER appear in saved documents query!")

        # getActiveDraft query: WHERE status = 'draft' ORDER BY updated_at DESC LIMIT 1
        cur.execute("SELECT id FROM documents WHERE status = 'draft' AND deleted_at IS NULL ORDER BY updated_at DESC LIMIT 1;")
        active_draft = cur.fetchone()
        self.assertIsNotNone(active_draft)
        self.assertEqual(active_draft[0], 'doc_draft')

        # discardDraft query: DELETE FROM documents WHERE id = ? AND status = 'draft'
        cur.execute("DELETE FROM documents WHERE id = ? AND status = 'draft';", ('doc_draft',))
        self.conn.commit()

        # Confirm draft is gone and page cascade deleted
        cur.execute("SELECT COUNT(*) FROM documents WHERE id = 'doc_draft';")
        self.assertEqual(cur.fetchone()[0], 0)
        cur.execute("SELECT COUNT(*) FROM pages WHERE document_id = 'doc_draft';")
        self.assertEqual(cur.fetchone()[0], 0, "Draft pages were not cascade deleted on discard!")

    def test_case_insensitive_search_and_wildcard_behavior(self):
        """Test case-insensitive search with COLLATE NOCASE, Unicode, and wildcard analysis."""
        cur = self.conn.cursor()
        now = int(time.time() * 1000)

        docs = [
            ('doc1', 'Tax Invoice 2026', 'saved'),
            ('doc2', 'medical lease AGREEMENT', 'saved'),
            ('doc3', 'Doctor Prescription', 'saved'),
            ('doc4', '100% Finalized Report', 'saved'),
            ('doc5', 'Draft Document', 'draft'), # should not be found
        ]
        for d_id, title, st in docs:
            cur.execute("""
                INSERT INTO documents (id, title, created_at, updated_at, status)
                VALUES (?, ?, ?, ?, ?);
            """, (d_id, title, now, now, st))
        self.conn.commit()

        # Helper query simulating DocumentRepository.searchDocuments
        def search(query_str):
            trimmed = query_str.strip()
            cur.execute("""
                SELECT id, title FROM documents
                WHERE status = 'saved' AND deleted_at IS NULL AND title LIKE ? COLLATE NOCASE
                ORDER BY updated_at DESC;
            """, (f"%{trimmed}%",))
            return cur.fetchall()

        # Test case insensitivity
        self.assertEqual(len(search('invoice')), 1)
        self.assertEqual(search('invoice')[0][0], 'doc1')
        self.assertEqual(len(search('INVOICE')), 1)
        self.assertEqual(len(search('InVoIcE')), 1)

        self.assertEqual(len(search('agreement')), 1)
        self.assertEqual(search('agreement')[0][0], 'doc2')
        self.assertEqual(len(search('AGREEMENT')), 1)

        # Test draft exclusion
        self.assertEqual(len(search('draft')), 0)

        # Edge case: search with '%' or '_'
        # Because DocumentRepository does NOT escape '%' or '_', searching for '%' matches all saved documents
        pct_results = search('%')
        self.assertEqual(len(pct_results), 4, "Unescaped '%' in LIKE matches all saved documents")


# ==============================================================================
# 3. PDF GENERATION & ISO 32000 SPECIFICATION TEST HARNESS
# ==============================================================================

class TestPdfGenerationAndIsoCompliance(unittest.TestCase):
    def test_iso_32000_magic_header_and_eof(self):
        """Verify strict ISO 32000 compliance rules (%PDF- header and %%EOF trailer)."""
        valid_pdf_sample = (
            b"%PDF-1.4\n"
            b"1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n"
            b"2 0 obj\n<< /Type /Pages /Kids [3 0 R 4 0 R 5 0 R] /Count 3 >>\nendobj\n"
            b"3 0 obj\n<< /Type /Page /Parent 2 0 R >>\nendobj\n"
            b"4 0 obj\n<< /Type /Page /Parent 2 0 R >>\nendobj\n"
            b"5 0 obj\n<< /Type /Page /Parent 2 0 R >>\nendobj\n"
            b"xref\n0 6\n0000000000 65535 f \n"
            b"trailer\n<< /Root 1 0 R /Size 6 >>\nstartxref\n300\n%%EOF\n"
        )

        # 1. Header check (sublist 0..5)
        header = valid_pdf_sample[:5].decode('ascii')
        self.assertEqual(header, "%PDF-")

        # 2. EOF check (tail 1024 bytes)
        tail = valid_pdf_sample[-1024:].decode('ascii', errors='ignore')
        self.assertIn("%%EOF", tail)

        # 3. Page counter regex verification
        # The regex used in PdfGeneratorService is: r'/Type\s*/Page\b'
        page_pattern = re.compile(r'/Type\s*/Page\b')
        content = valid_pdf_sample.decode('latin-1')
        matches = page_pattern.findall(content)
        # Note: /Type /Pages should NOT match because 's' is a word char, not a word boundary!
        self.assertEqual(len(matches), 3, f"Expected 3 pages, found {len(matches)}")

    def test_page_counter_regex_distinguishes_pages_from_page(self):
        """Empirically prove that /Type /Pages does not collide with /Type /Page\\b."""
        sample = "/Type /Pages /Kids [...] /Count 10 /Type /Page /Parent ... /Type /Page /Parent ..."
        pattern = re.compile(r'/Type\s*/Page\b')
        matches = pattern.findall(sample)
        self.assertEqual(len(matches), 2, "Failed: /Type /Pages matched /Type /Page\\b!")

    def test_memory_scaling_model(self):
        """Model heap memory consumption across 10, 50, and 100 pages for High vs Medium presets."""
        # Uncompressed 1080x1920 RGBA image = 1080 * 1920 * 4 = 8.29 MB raw bitmap
        # High preset: untouched JPEG bytes (~1.5 MB per page compressed)
        # Medium preset: clamped to 1600 max dimension, ~0.4 MB per page
        page_counts = [3, 10, 50, 100]
        results = {}
        for count in page_counts:
            high_heap_est_mb = count * 1.5 + (count * 0.1) # image bytes + PDF DOM overhead
            med_heap_est_mb = count * 0.4 + (count * 0.1)
            results[count] = {"high_mb": high_heap_est_mb, "med_mb": med_heap_est_mb}

        # Verify that for standard 3-page scan (Milestone 1 acceptance criterion):
        # Memory is tiny: ~4.8 MB High, ~1.5 MB Medium
        self.assertLess(results[3]["high_mb"], 10.0)
        # For 50 pages, High is ~80MB, well within modern Android 256MB heap limit
        self.assertLess(results[50]["high_mb"], 256.0)


# ==============================================================================
# 4. SHARE SECURITY BOUNDARY HARNESS
# ==============================================================================

class ShareSecurityValidator:
    """Implements the exact logic of ShareService.sharePdf security check."""
    @staticmethod
    def is_blocked(pdf_cache_path: str) -> bool:
        lower = pdf_cache_path.lower()
        if (lower.endswith('.db') or
            lower.endswith('.sqlite') or
            'docerena.db' in lower or
            '/database/' in lower or
            '\\database\\' in lower):
            return True
        return False


class TestShareSecurityBoundary(unittest.TestCase):
    def test_direct_database_rejection(self):
        """Verify docerena.db and .db files are rejected."""
        self.assertTrue(ShareSecurityValidator.is_blocked("docerena.db"))
        self.assertTrue(ShareSecurityValidator.is_blocked("DOCERENA.DB"))
        self.assertTrue(ShareSecurityValidator.is_blocked("/data/user/0/com.digitalerena.docerena/databases/docerena.db"))
        self.assertTrue(ShareSecurityValidator.is_blocked("C:\\Users\\DocErena\\docerena.db"))
        self.assertTrue(ShareSecurityValidator.is_blocked("export.db"))
        self.assertTrue(ShareSecurityValidator.is_blocked("export.sqlite"))

    def test_database_folder_rejection(self):
        """Verify files in /database/ or \\database\\ are rejected."""
        self.assertTrue(ShareSecurityValidator.is_blocked("/data/user/0/com.digitalerena.docerena/database/secret.pdf"))
        self.assertTrue(ShareSecurityValidator.is_blocked("D:\\camscanner\\database\\tables.pdf"))

    def test_legitimate_pdf_paths_allowed(self):
        """Verify genuine PDF cache paths are permitted."""
        self.assertFalse(ShareSecurityValidator.is_blocked("/data/user/0/com.digitalerena.docerena/cache/exports/uuid-123.pdf"))
        self.assertFalse(ShareSecurityValidator.is_blocked("D:\\camscanner\\cache\\exports\\DocErena_20261107.pdf"))

    def test_adversarial_bypass_attacks(self):
        """Adversarial challenge: Test bypass attempts against the filter."""
        # 1. docerena.db-wal (SQLite Write-Ahead Log)
        # Should be blocked because it contains 'docerena.db'
        self.assertTrue(ShareSecurityValidator.is_blocked("docerena.db-wal"))
        self.assertTrue(ShareSecurityValidator.is_blocked("docerena.db-shm"))

        # 2. .sqlite3 extension (not in endsWith('.sqlite') check!)
        # Does the filter block an arbitrary .sqlite3 file outside /database/?
        sqlite3_blocked = ShareSecurityValidator.is_blocked("backup_tables.sqlite3")
        # In current ShareService implementation, endsWith('.sqlite') does NOT block '.sqlite3'!
        # We record this finding!
        print(f"\n[Adversarial Challenge Finding]: 'backup_tables.sqlite3' blocked? {sqlite3_blocked}")

        # 3. Android default databases directory: '/databases/' (plural with 's')
        # Android Context.getDatabasePath() uses 'databases', NOT 'database'!
        databases_plural_blocked = ShareSecurityValidator.is_blocked("/data/user/0/com.digitalerena.docerena/databases/dump.bin")
        print(f"[Adversarial Challenge Finding]: '/databases/dump.bin' blocked? {databases_plural_blocked}")


if __name__ == "__main__":
    unittest.main()
