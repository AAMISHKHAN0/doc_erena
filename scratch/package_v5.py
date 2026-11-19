#!/usr/bin/env python3
"""
DocErena v5.0 Phone-Test Release Review Package Packaging Script
Creates DocErena_Review_Package_v5.0.zip and validates archive integrity.
"""

import os
import zipfile
import hashlib
import shutil

ROOT_DIR = r"D:\camscanner"
REVIEW_DIR = os.path.join(ROOT_DIR, "review_package")
OUT_ZIPS = [
    os.path.join(ROOT_DIR, "DocErena_Review_Package_v5.0.zip"),
    os.path.join(ROOT_DIR, "web_preview", "DocErena_Review_Package_v5.0.zip")
]

print("=" * 80)
print(" PACKAGING DOCERENA V5.0 REVIEW PACKAGE ARCHIVE")
print(" Source Directory: D:\\camscanner\\review_package")
print("=" * 80)

primary_zip = OUT_ZIPS[0]
if os.path.exists(primary_zip):
    os.remove(primary_zip)

file_count = 0
total_uncompressed_bytes = 0

with zipfile.ZipFile(primary_zip, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
    for root, dirs, files in os.walk(REVIEW_DIR):
        for f in files:
            full_path = os.path.join(root, f)
            rel_path = os.path.relpath(full_path, ROOT_DIR)
            zf.write(full_path, rel_path)
            file_count += 1
            total_uncompressed_bytes += os.path.getsize(full_path)

# Integrity test
with zipfile.ZipFile(primary_zip, 'r') as zf:
    corrupt = zf.testzip()
    assert corrupt is None, f"Zip integrity check failed on file: {corrupt}"

zip_size = os.path.getsize(primary_zip)
with open(primary_zip, 'rb') as f:
    zip_sha256 = hashlib.sha256(f.read()).hexdigest()

# Copy to web_preview
shutil.copy(primary_zip, OUT_ZIPS[1])

print(f"\n[Integrity Verification]")
print(f"  * Total Files Archived:      {file_count}")
print(f"  * Uncompressed Size:         {total_uncompressed_bytes:,} bytes ({total_uncompressed_bytes/(1024*1024):.2f} MB)")
print(f"  * Compressed Archive Size:   {zip_size:,} bytes ({zip_size/(1024*1024):.2f} MB)")
print(f"  * SHA-256 Digest:            {zip_sha256}")
print(f"  * testzip() CRC-32 Check:    100% CLEAN (0 corrupt files)")
print(f"  * Web Preview Copy:          {OUT_ZIPS[1]}")
print("=" * 80)
