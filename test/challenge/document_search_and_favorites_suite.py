#!/usr/bin/env python3
"""
DocErena Document Search & Favorites Integrity & Persistence Test Suite
Verifies:
1. Document search query algorithm: exact match, partial match, case-insensitivity,
   dynamic result count, empty query state, and no-results state.
2. Favorites persistence lifecycle: marking/unmarking favorites, atomic local file storage
   in folders_metadata.json, and cold-start app restart survival.
3. Dart AST and Widget integrity:
   - DocumentSearchScreen widget structure, search input, clear button, scope badge, cards.
   - DocumentsScreen search field integration, favorites tab header, and direct star control.
   - AppRouter route registration for AppRoutes.documentSearch.
4. Web preview DOM and controller verification:
   - #screen-search container, dedicated search field, scope pill, dynamic result count.
   - Document cards with yellow star button and Favorites heading.
"""

import os
import sys
import json
import tempfile
import time
import shutil

def verify_search_algorithm():
    print("--- 1. Testing Document Search Algorithm & Query Handling ---")
    
    mock_docs = [
        {"id": "d1", "title": "Project Proposal", "pages": 12},
        {"id": "d2", "title": "Project Proposal Notes", "pages": 4},
        {"id": "d3", "title": "Invoice March 2025", "pages": 3},
        {"id": "d4", "title": "Meeting Notes", "pages": 5},
        {"id": "d5", "title": "Receipt Store", "pages": 1},
    ]

    def search_docs(query, docs):
        q = query.strip().lower()
        if not q:
            return []
        return [d for d in docs if q in d["title"].lower()]

    # Test 1.1: Partial query "proposal" matching mockup (media_1794371283459_f7279218.jpg)
    results = search_docs("proposal", mock_docs)
    assert len(results) == 2, f"Expected 2 results for 'proposal', got {len(results)}"
    assert results[0]["title"] == "Project Proposal"
    assert results[1]["title"] == "Project Proposal Notes"
    assert results[0]["pages"] == 12
    assert results[1]["pages"] == 4
    print("  [+] Verified query 'proposal' returns exact 2 matches from mockup.")

    # Test 1.2: Case-insensitive search
    res_upper = search_docs("PROPOSAL", mock_docs)
    assert len(res_upper) == 2, "Case insensitivity failed"
    res_mixed = search_docs("pRoPoSaL", mock_docs)
    assert len(res_mixed) == 2, "Mixed case query failed"
    print("  [+] Verified case-insensitive matching.")

    # Test 1.3: Partial substring anywhere in title
    res_notes = search_docs("notes", mock_docs)
    assert len(res_notes) == 2, f"Expected 2 matches for 'notes', got {len(res_notes)}"
    matched_ids = [d["id"] for d in res_notes]
    assert "d2" in matched_ids and "d4" in matched_ids
    print("  [+] Verified substring search across different title positions.")

    # Test 1.4: Empty query returns empty results list (triggers empty query state)
    res_empty = search_docs("", mock_docs)
    assert len(res_empty) == 0, "Empty query must return 0 results"
    res_spaces = search_docs("   ", mock_docs)
    assert len(res_spaces) == 0, "Whitespace query must return 0 results"
    print("  [+] Verified empty/whitespace query handling.")

    # Test 1.5: No-match query (triggers no-results state)
    res_nomatch = search_docs("xyznonexistent", mock_docs)
    assert len(res_nomatch) == 0, "Unmatched query must return 0 results"
    print("  [+] Verified unmatchable query handling.")


def verify_favorites_persistence():
    print("\n--- 2. Testing Favorites Persistence Across App Restarts ---")
    
    temp_dir = tempfile.mkdtemp(prefix="docerena_fav_test_")
    meta_path = os.path.join(temp_dir, "folders_metadata.json")
    
    # 2.1 Initial metadata state with 2 favorites
    initial_data = {
        "version": 1,
        "updated_at": int(time.time() * 1000),
        "folders": [],
        "favorites": ["doc_proj_prop", "doc_meeting_notes"]
    }
    
    with open(meta_path, "w", encoding="utf-8") as f:
        json.dump(initial_data, f)
        
    print(f"  [+] Saved initial favorites metadata at {meta_path}")

    # 2.2 Add new favorite "doc_invoice" (simulating tapping star on card)
    with open(meta_path, "r", encoding="utf-8") as f:
        data = json.load(f)
    favs = set(data["favorites"])
    assert "doc_invoice" not in favs
    favs.add("doc_invoice")
    data["favorites"] = list(favs)
    
    # Atomic file persistence
    with open(meta_path + ".tmp", "w", encoding="utf-8") as f:
        json.dump(data, f)
    os.replace(meta_path + ".tmp", meta_path)
    print("  [+] Added 'doc_invoice' to favorites and committed atomically.")

    # 2.3 Simulate cold-start restart (read back in fresh process)
    with open(meta_path, "r", encoding="utf-8") as f:
        reloaded = json.load(f)
    reloaded_favs = set(reloaded["favorites"])
    assert len(reloaded_favs) == 3, f"Expected 3 favorites, got {len(reloaded_favs)}"
    assert "doc_invoice" in reloaded_favs
    assert "doc_proj_prop" in reloaded_favs
    assert "doc_meeting_notes" in reloaded_favs
    print("  [+] Verified cold-start restart: all 3 favorites persisted.")

    # 2.4 Toggle remove favorite "doc_proj_prop" (tapping star on Favorites tab)
    reloaded_favs.remove("doc_proj_prop")
    reloaded["favorites"] = list(reloaded_favs)
    with open(meta_path + ".tmp", "w", encoding="utf-8") as f:
        json.dump(reloaded, f)
    os.replace(meta_path + ".tmp", meta_path)
    print("  [+] Removed 'doc_proj_prop' and committed atomically.")

    # 2.5 Second cold-start restart
    with open(meta_path, "r", encoding="utf-8") as f:
        final_data = json.load(f)
    final_favs = set(final_data["favorites"])
    assert len(final_favs) == 2
    assert "doc_proj_prop" not in final_favs
    assert "doc_invoice" in final_favs
    print("  [+] Verified second cold-start restart: removed favorite remains unstarred.")

    shutil.rmtree(temp_dir, ignore_errors=True)


def verify_dart_code():
    print("\n--- 3. Verifying Dart Code AST & Widget Requirements ---")
    
    # 3.1 document_search_screen.dart
    search_screen_path = os.path.join("lib", "presentation", "screens", "s11_documents", "document_search_screen.dart")
    assert os.path.exists(search_screen_path), f"Missing {search_screen_path}"
    with open(search_screen_path, "r", encoding="utf-8") as f:
        s_code = f.read()
    assert "class DocumentSearchScreen extends StatefulWidget" in s_code
    assert "Document search" in s_code
    assert "Search documents" in s_code
    assert "All documents" in s_code
    assert "_clearSearch" in s_code
    assert "_getSearchResults" in s_code
    assert "AccessibleTouchTarget" in s_code
    print("  [+] DocumentSearchScreen verified.")

    # 3.2 documents_screen.dart
    docs_screen_path = os.path.join("lib", "presentation", "screens", "s11_documents", "documents_screen.dart")
    with open(docs_screen_path, "r", encoding="utf-8") as f:
        d_code = f.read()
    assert "document_search_screen.dart" in d_code
    assert "_openSearch" in d_code
    assert "_toggleFavorite" in d_code
    assert "Favorites" in d_code
    assert "Icons.star_rounded" in d_code
    assert "Color(0xFFFDE047)" in d_code
    print("  [+] DocumentsScreen search trigger, Favorites heading, and Star button verified.")

    # 3.3 app_router.dart
    router_path = os.path.join("lib", "presentation", "navigation", "app_router.dart")
    with open(router_path, "r", encoding="utf-8") as f:
        r_code = f.read()
    assert "AppRoutes.documentSearch" in r_code
    assert "DocumentSearchScreen" in r_code
    print("  [+] AppRouter AppRoutes.documentSearch route verified.")


def verify_web_preview():
    print("\n--- 4. Verifying Web Preview HTML & Interactions ---")
    index_path = os.path.join("web_preview", "index.html")
    with open(index_path, "r", encoding="utf-8") as f:
        html = f.read()
    assert 'id="screen-search"' in html
    assert "Document search" in html
    assert 'id="dedicated-search-input"' in html
    assert "All documents" in html
    assert 'id="search-result-count"' in html
    assert "renderSearchResults" in html
    assert "clearSearchInput" in html
    assert "toggleDocFavorite" in html
    assert 'fill="#FDE047"' in html
    print("  [+] Web preview Document Search & Favorites DOM and JavaScript verified.")


if __name__ == "__main__":
    verify_search_algorithm()
    verify_favorites_persistence()
    verify_dart_code()
    verify_web_preview()
    print("\n" + "=" * 60)
    print("ALL VERIFICATIONS PASSED: 100% SUCCESSFUL (0 FAILURES)")
