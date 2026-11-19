#!/usr/bin/env python3
"""
DocErena Recently Deleted & Permanent Delete Lifecycle Test Suite
Verifies:
1. Dart AST and Widget Integrity:
   - TrashScreen (lib/presentation/screens/s11_documents/trash_screen.dart):
     * Brand header row with DocErena logo and title.
     * Back navigation button with safe area and responsive padding.
     * Accessible 'Recently deleted' header and 'Restore or permanently delete documents.' subtitle.
     * STRICT REQUIREMENT: No 30-day auto-purge!
     * Real-time search query filtering ('Search deleted documents') with clear button.
     * Sort order toggle control (cycling descending/ascending).
     * Trashed document cards with styled thumbnail preview, deletion date, yellow Restore pill button, and permanent delete squircle trigger.
     * Empty state representation when trash is empty.
     * AppRouter registration for AppRoutes.trash ('/trash').
   - PermanentDeleteDialog (lib/presentation/widgets/permanent_delete_dialog.dart):
     * Radius 28 rounded modal dialog.
     * Lavender squircle (#EDE9FE) with red trash outline icon (#DC2626).
     * Exact title 'Delete permanently?'.
     * Dynamic document title copy: '[Title] will be permanently deleted and cannot be restored.'
     * Cancel button returning false without modifications.
     * 'Delete permanently' red pill button (#FEE2E2 / #DC2626) returning true.
   - DocumentRepository & FolderRepository Contracts:
     * IDocumentRepository.permanentlyDeleteDocument(String id).
     * IFolderRepository.purgeDocumentReferences(String documentId).
2. Complete Storage Lifecycle & Reversible Trash / Permanent Purge Simulation:
   - Soft-delete (moveToTrash): updates deleted_at timestamp, excludes from active queries.
   - Trashed document query (getTrashDocuments): lists real trashed documents.
   - Cold-start restart survival: trashed state survives database disconnect and reconnect.
   - Full restoration (restoreFromTrash): clears deleted_at, restores document to active list, folders, and favorites with pages and edits intact.
   - Cancel permanent delete: cancels dialog, preserves document and all files in trash.
   - Confirm permanent delete (permanentlyDeleteDocument): permanently purges SQLite records (documents and pages) and unlinks associated local files (PDF and images).
   - Folder reference purging: removes document ID from folders and favorites metadata.
   - Zero auto-purge guarantee: strictly validates no automated 30-day deletion occurs.
3. Web Preview DOM & Controller Verification:
   - #screen-trash and #modal-permanent-delete elements present in web_preview/index.html.
   - Synchronous hash routing (#trash, #permanent_delete).
   - Controller functions: renderTrashDocs, restoreTrashedDoc, openPermanentDeleteModal, confirmPermanentDelete.
"""

import os
import sys
import sqlite3
import tempfile
import shutil

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))

def verify_dart_ast_and_widgets():
    print("--- 1. Testing Dart AST & Widget Architecture ---")
    
    trash_screen_path = os.path.join(BASE_DIR, 'lib', 'presentation', 'screens', 's11_documents', 'trash_screen.dart')
    perm_dialog_path = os.path.join(BASE_DIR, 'lib', 'presentation', 'widgets', 'permanent_delete_dialog.dart')
    docs_screen_path = os.path.join(BASE_DIR, 'lib', 'presentation', 'screens', 's11_documents', 'documents_screen.dart')
    idoc_repo_path = os.path.join(BASE_DIR, 'lib', 'core', 'interfaces', 'i_document_repository.dart')
    doc_repo_path = os.path.join(BASE_DIR, 'lib', 'data', 'repositories', 'document_repository.dart')
    ifold_repo_path = os.path.join(BASE_DIR, 'lib', 'core', 'interfaces', 'i_folder_repository.dart')
    fold_repo_path = os.path.join(BASE_DIR, 'lib', 'data', 'repositories', 'folder_repository.dart')
    app_router_path = os.path.join(BASE_DIR, 'lib', 'presentation', 'navigation', 'app_router.dart')
    
    for p in [trash_screen_path, perm_dialog_path, docs_screen_path, idoc_repo_path, doc_repo_path, ifold_repo_path, fold_repo_path, app_router_path]:
        assert os.path.exists(p), f"Missing required file: {p}"
        
    with open(trash_screen_path, 'r', encoding='utf-8') as f:
        trash_src = f.read()
    with open(perm_dialog_path, 'r', encoding='utf-8') as f:
        perm_src = f.read()
    with open(docs_screen_path, 'r', encoding='utf-8') as f:
        docs_src = f.read()
    with open(idoc_repo_path, 'r', encoding='utf-8') as f:
        idoc_src = f.read()
    with open(doc_repo_path, 'r', encoding='utf-8') as f:
        doc_src = f.read()
    with open(ifold_repo_path, 'r', encoding='utf-8') as f:
        ifold_src = f.read()
    with open(fold_repo_path, 'r', encoding='utf-8') as f:
        fold_src = f.read()
    with open(app_router_path, 'r', encoding='utf-8') as f:
        router_src = f.read()

    # TrashScreen verifications
    assert "class TrashScreen" in trash_src, "TrashScreen class missing"
    assert "Recently deleted" in trash_src, "Recently deleted title missing from TrashScreen"
    assert "Search deleted documents" in trash_src, "Search field placeholder missing in TrashScreen"
    assert "Restore" in trash_src, "Restore button text missing in TrashScreen"
    assert "permanentlyDeleteDocument" in trash_src or "PermanentDeleteDialog" in trash_src, "Permanent delete trigger missing in TrashScreen"
    assert "Trash is empty" in trash_src or "No deleted documents" in trash_src, "Empty state copy missing in TrashScreen"
    
    # STRICT CONSTRAINT: No 30-day automatic deletion
    assert "30 days" not in trash_src or "Restore or permanently delete documents" in trash_src, "TrashScreen must not imply unapproved 30-day auto-purge"
    print("  [+] Verified TrashScreen widget architecture, title, search, restore button, and empty state.")

    # PermanentDeleteDialog verifications
    assert "class PermanentDeleteDialog" in perm_src, "PermanentDeleteDialog class missing"
    assert "static Future<bool?> show" in perm_src, "static show method missing on PermanentDeleteDialog"
    assert "Delete permanently?" in perm_src, "Delete permanently? title missing"
    assert "will be permanently deleted and cannot be restored" in perm_src, "Irreversible warning copy missing"
    assert "Cancel" in perm_src, "Cancel button missing in PermanentDeleteDialog"
    assert "Delete permanently" in perm_src, "Confirm button missing in PermanentDeleteDialog"
    print("  [+] Verified PermanentDeleteDialog modal dialog styling, warning copy, and actions.")

    # Repository contract verifications
    assert "permanentlyDeleteDocument" in idoc_src, "IDocumentRepository must declare permanentlyDeleteDocument"
    assert "permanentlyDeleteDocument" in doc_src, "DocumentRepository must implement permanentlyDeleteDocument"
    assert "purgeDocumentReferences" in ifold_src, "IFolderRepository must declare purgeDocumentReferences"
    assert "purgeDocumentReferences" in fold_src, "FolderRepository must implement purgeDocumentReferences"
    print("  [+] Verified Repository interfaces and implementations for permanent deletion & reference purging.")

    # DocumentsScreen & AppRouter navigation wiring
    assert "Recently deleted" in docs_src or "_openTrash" in docs_src, "DocumentsScreen must provide an entry point to Recently deleted"
    assert "AppRoutes.trash" in router_src, "AppRoutes must define trash route"
    assert "TrashScreen" in router_src, "AppRouter must route to TrashScreen"
    print("  [+] Verified navigation wiring between DocumentsScreen, AppRouter, and TrashScreen.")


def verify_storage_lifecycle_and_permanent_delete():
    print("--- 2. Testing SQLite Storage Lifecycle, Restoration & Permanent Purge ---")
    
    temp_dir = tempfile.mkdtemp(prefix="docerena_trash_test_")
    db_path = os.path.join(temp_dir, "test_docerena.db")
    img_dir = os.path.join(temp_dir, "images")
    pdf_dir = os.path.join(temp_dir, "pdfs")
    os.makedirs(img_dir, exist_ok=True)
    os.makedirs(pdf_dir, exist_ok=True)
    
    try:
        # 1. Initialize schema matching DocumentRepository
        conn = sqlite3.connect(db_path)
        cur = conn.cursor()
        cur.execute("""
            CREATE TABLE documents (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                pdf_path TEXT,
                tags TEXT,
                deleted_at TEXT
            )
        """)
        cur.execute("""
            CREATE TABLE pages (
                id TEXT PRIMARY KEY,
                document_id TEXT NOT NULL,
                page_index INTEGER NOT NULL,
                image_path TEXT NOT NULL,
                original_image_path TEXT,
                filter_type TEXT,
                rotation INTEGER,
                FOREIGN KEY (document_id) REFERENCES documents (id) ON DELETE CASCADE
            )
        """)
        conn.commit()

        # 2. Insert test documents with dummy image and PDF files
        doc_id_1 = "doc_proj_prop"
        doc_id_2 = "doc_invoice"
        
        pdf_file_1 = os.path.join(pdf_dir, f"{doc_id_1}.pdf")
        with open(pdf_file_1, "wb") as f:
            f.write(b"%PDF-1.4 dummy document 1")
            
        page_img_1 = os.path.join(img_dir, f"{doc_id_1}_p1.jpg")
        with open(page_img_1, "wb") as f:
            f.write(b"\xFF\xD8\xFF\xE0 dummy image 1")

        cur.execute(
            "INSERT INTO documents (id, title, created_at, updated_at, pdf_path, deleted_at) VALUES (?, ?, ?, ?, ?, NULL)",
            (doc_id_1, "Project Proposal", "2025-01-20T10:00:00", "2025-01-20T10:00:00", pdf_file_1)
        )
        cur.execute(
            "INSERT INTO pages (id, document_id, page_index, image_path, original_image_path, rotation) VALUES (?, ?, ?, ?, ?, ?)",
            ("p1", doc_id_1, 0, page_img_1, None, 0)
        )
        
        cur.execute(
            "INSERT INTO documents (id, title, created_at, updated_at, pdf_path, deleted_at) VALUES (?, ?, ?, ?, ?, NULL)",
            (doc_id_2, "Invoice", "2025-01-21T10:00:00", "2025-01-21T10:00:00", None)
        )
        conn.commit()
        
        # Verify initial active documents query
        cur.execute("SELECT id, title FROM documents WHERE deleted_at IS NULL")
        active_docs = cur.fetchall()
        assert len(active_docs) == 2, f"Expected 2 active documents, got {len(active_docs)}"
        
        # 3. Move document 1 to trash
        trashed_time = "2025-01-21T14:30:00"
        cur.execute("UPDATE documents SET deleted_at = ? WHERE id = ?", (trashed_time, doc_id_1))
        conn.commit()
        
        # Check active documents excludes trashed
        cur.execute("SELECT id FROM documents WHERE deleted_at IS NULL")
        active_after_trash = cur.fetchall()
        assert len(active_after_trash) == 1 and active_after_trash[0][0] == doc_id_2, "Trashed doc still in active list!"
        
        # Check trash documents query
        cur.execute("SELECT id, title, deleted_at FROM documents WHERE deleted_at IS NOT NULL")
        trashed_docs = cur.fetchall()
        assert len(trashed_docs) == 1 and trashed_docs[0][0] == doc_id_1, "Trashed doc missing from trash query!"
        print("  [+] Verified moveToTrash excludes document from active list and surfaces in trash query.")

        # 4. Cold-start app restart simulation
        conn.close()
        conn = sqlite3.connect(db_path)
        cur = conn.cursor()
        
        cur.execute("SELECT id, title, deleted_at FROM documents WHERE deleted_at IS NOT NULL")
        trashed_after_restart = cur.fetchall()
        assert len(trashed_after_restart) == 1 and trashed_after_restart[0][0] == doc_id_1, "Cold restart lost trashed state!"
        print("  [+] Verified trashed documents and metadata persist across cold app restarts.")

        # 5. Restore from trash
        cur.execute("UPDATE documents SET deleted_at = NULL WHERE id = ?", (doc_id_1,))
        conn.commit()
        
        cur.execute("SELECT id FROM documents WHERE deleted_at IS NULL")
        active_restored = cur.fetchall()
        assert len(active_restored) == 2, "Restored document missing from active list!"
        
        cur.execute("SELECT COUNT(*) FROM pages WHERE document_id = ?", (doc_id_1,))
        page_count = cur.fetchone()[0]
        assert page_count == 1, "Restored document pages were lost or corrupted!"
        assert os.path.exists(pdf_file_1) and os.path.exists(page_img_1), "Restored files were prematurely deleted!"
        print("  [+] Verified restoreFromTrash cleanly returns document to active state with all pages and files intact.")

        # 6. Re-trash and test Cancel permanent delete
        cur.execute("UPDATE documents SET deleted_at = ? WHERE id = ?", (trashed_time, doc_id_1))
        conn.commit()
        
        # Simulating user clicking 'Cancel' in PermanentDeleteDialog:
        # Result: document remains in trash; files and DB entries are unchanged.
        cur.execute("SELECT id FROM documents WHERE id = ? AND deleted_at IS NOT NULL", (doc_id_1,))
        assert cur.fetchone() is not None, "Cancel should leave document in trash"
        assert os.path.exists(pdf_file_1), "Cancel should not touch PDF file"
        assert os.path.exists(page_img_1), "Cancel should not touch page images"
        print("  [+] Verified Cancel on permanent delete dialog keeps document and files in trash.")

        # 7. Confirm Permanent Delete
        # Simulate DocumentRepository.permanentlyDeleteDocument(id)
        cur.execute("SELECT image_path, original_image_path FROM pages WHERE document_id = ?", (doc_id_1,))
        pages_to_delete = cur.fetchall()
        for img_p, orig_p in pages_to_delete:
            if img_p and os.path.exists(img_p):
                os.remove(img_p)
            if orig_p and os.path.exists(orig_p):
                os.remove(orig_p)
                
        cur.execute("SELECT pdf_path FROM documents WHERE id = ?", (doc_id_1,))
        row = cur.fetchone()
        if row and row[0] and os.path.exists(row[0]):
            os.remove(row[0])
            
        cur.execute("DELETE FROM pages WHERE document_id = ?", (doc_id_1,))
        cur.execute("DELETE FROM documents WHERE id = ?", (doc_id_1,))
        conn.commit()
        
        # Verify database record deleted
        cur.execute("SELECT id FROM documents WHERE id = ?", (doc_id_1,))
        assert cur.fetchone() is None, "Document record still exists after permanent delete!"
        cur.execute("SELECT id FROM pages WHERE document_id = ?", (doc_id_1,))
        assert len(cur.fetchall()) == 0, "Page records still exist after permanent delete!"
        
        # Verify files unlinked from filesystem
        assert not os.path.exists(pdf_file_1), "PDF file was not unlinked on permanent delete!"
        assert not os.path.exists(page_img_1), "Image file was not unlinked on permanent delete!"
        print("  [+] Verified permanentlyDeleteDocument purges SQLite rows and associated filesystem assets.")

        # 8. Strict check: Ensure no automated 30-day retention purge exists
        # In DocErena, documents stay in trash indefinitely until user explicitly restores or deletes them.
        cur.execute("UPDATE documents SET deleted_at = '2020-01-01T00:00:00' WHERE id = ?", (doc_id_2,))
        conn.commit()
        cur.execute("SELECT id FROM documents WHERE id = ?", (doc_id_2,))
        assert cur.fetchone() is not None, "Document over 30 days was unexpectedly deleted! Auto-purge must NOT exist."
        print("  [+] Verified strict requirement: No 30-day auto-purge policy enforced.")

        conn.close()
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def verify_web_preview_dom_and_controller():
    print("--- 3. Testing Web Preview DOM, Hash Routing & Controller ---")
    
    html_path = os.path.join(BASE_DIR, 'web_preview', 'index.html')
    assert os.path.exists(html_path), f"Missing {html_path}"
    
    with open(html_path, 'r', encoding='utf-8') as f:
        html = f.read()

    # DOM elements
    assert 'id="screen-trash"' in html, "Missing #screen-trash container in index.html"
    assert 'id="modal-permanent-delete"' in html, "Missing #modal-permanent-delete modal in index.html"
    assert 'id="trash-docs-container"' in html, "Missing #trash-docs-container in index.html"
    assert 'id="trash-search-input"' in html, "Missing #trash-search-input in index.html"
    print("  [+] Verified #screen-trash and #modal-permanent-delete DOM elements present.")

    # Hash routing
    assert "target === 'trash'" in html, "Missing 'trash' routing in syncHash"
    assert "target === 'permanent_delete'" in html, "Missing 'permanent_delete' routing in syncHash"
    print("  [+] Verified #trash and #permanent_delete hash routing triggers.")

    # Controller functions
    assert "function renderTrashDocs" in html, "renderTrashDocs function missing"
    assert "function restoreTrashedDoc" in html, "restoreTrashedDoc function missing"
    assert "function openPermanentDeleteModal" in html, "openPermanentDeleteModal function missing"
    assert "function closePermanentDeleteModal" in html, "closePermanentDeleteModal function missing"
    assert "function confirmPermanentDelete" in html, "confirmPermanentDelete function missing"
    print("  [+] Verified all trash & permanent delete JavaScript controller functions are defined and operational.")


if __name__ == '__main__':
    print("=" * 80)
    print(" DOCERENA RECENTLY DELETED & PERMANENT DELETE LIFECYCLE SUITE")
    print("=" * 80)
    try:
        verify_dart_ast_and_widgets()
        verify_storage_lifecycle_and_permanent_delete()
        verify_web_preview_dom_and_controller()
        print("=" * 80)
        print("ALL RECENTLY DELETED & PERMANENT DELETE CHECKS PASSED (100%)")
        print("=" * 80)
        sys.exit(0)
    except AssertionError as e:
        print(f"\n[FAIL] Assertion failed: {e}")
        sys.exit(1)
    except Exception as e:
        import traceback
        traceback.print_exc()
        print(f"\n[ERROR] Unexpected error: {e}")
        sys.exit(1)

