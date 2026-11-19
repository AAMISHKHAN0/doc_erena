package com.digitalerena.docerena;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;
import android.webkit.MimeTypeMap;

import java.io.File;
import java.io.FileNotFoundException;
import java.io.IOException;

/**
 * Hardened DocErenaFileProvider implementing Android ContentProvider.
 * Provides secure content:// URIs for document sharing and export
 * with strict canonical path traversal validation and zero unbundled dependencies.
 */
public class DocErenaFileProvider extends ContentProvider {
    public static final String AUTHORITY = "com.digitalerena.docerena.fileprovider";

    @Override
    public boolean onCreate() {
        return true;
    }

    @Override
    public Cursor query(Uri uri, String[] projection, String selection, String[] selectionArgs, String sortOrder) {
        if (projection == null) {
            projection = new String[]{OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE};
        }
        MatrixCursor cursor = new MatrixCursor(projection, 1);
        try {
            File file = getFileForUri(uri);
            if (file != null && file.exists()) {
                MatrixCursor.RowBuilder row = cursor.newRow();
                for (String col : projection) {
                    if (OpenableColumns.DISPLAY_NAME.equals(col)) {
                        row.add(col, file.getName());
                    } else if (OpenableColumns.SIZE.equals(col)) {
                        row.add(col, file.length());
                    } else {
                        row.add(col, null);
                    }
                }
            }
        } catch (Exception e) {
            // Return empty cursor on security or file exception
        }
        return cursor;
    }

    @Override
    public String getType(Uri uri) {
        if (uri == null) return "application/octet-stream";
        String path = uri.getPath();
        if (path != null) {
            int dotIndex = path.lastIndexOf('.');
            if (dotIndex >= 0) {
                String ext = path.substring(dotIndex + 1).toLowerCase();
                String mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext);
                if (mime != null) return mime;
            }
            if (path.endsWith(".pdf")) return "application/pdf";
            if (path.endsWith(".png")) return "image/png";
            if (path.endsWith(".jpg") || path.endsWith(".jpeg")) return "image/jpeg";
            if (path.endsWith(".txt")) return "text/plain";
        }
        return "application/octet-stream";
    }

    @Override
    public Uri insert(Uri uri, ContentValues values) {
        throw new UnsupportedOperationException("Insert not supported by DocErenaFileProvider");
    }

    @Override
    public int delete(Uri uri, String selection, String[] selectionArgs) {
        try {
            File file = getFileForUri(uri);
            if (file != null && file.exists()) {
                return file.delete() ? 1 : 0;
            }
        } catch (Exception e) {
            return 0;
        }
        return 0;
    }

    @Override
    public int update(Uri uri, ContentValues values, String selection, String[] selectionArgs) {
        throw new UnsupportedOperationException("Update not supported by DocErenaFileProvider");
    }

    @Override
    public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        File file = getFileForUri(uri);
        if (file == null || !file.exists()) {
            throw new FileNotFoundException("File not found for URI: " + uri);
        }
        int fileMode = ParcelFileDescriptor.MODE_READ_ONLY;
        if ("w".equals(mode) || "rw".equals(mode) || "rwt".equals(mode)) {
            fileMode = ParcelFileDescriptor.MODE_READ_WRITE;
        }
        return ParcelFileDescriptor.open(file, fileMode);
    }

    public static Uri getUriForFile(Context context, String authority, File file) {
        if (file == null) return null;
        return new Uri.Builder()
            .scheme("content")
            .authority(authority)
            .path(file.getName())
            .build();
    }

    private File getFileForUri(Uri uri) throws SecurityException {
        if (uri == null || uri.getPath() == null || getContext() == null) {
            return null;
        }
        String path = uri.getPath();
        while (path.startsWith("/")) {
            path = path.substring(1);
        }

        // Strip subfolder prefixes if present
        if (path.startsWith("app_files/")) {
            path = path.substring("app_files/".length());
        } else if (path.startsWith("app_cache/")) {
            path = path.substring("app_cache/".length());
        }

        File cacheDir = getContext().getCacheDir();
        File filesDir = getContext().getFilesDir();
        File docsDir = getContext().getExternalFilesDir(android.os.Environment.DIRECTORY_DOCUMENTS);

        // Check cache directory first (e.g. exports, shared PDFs)
        File candidate = new File(cacheDir, path);
        if (!isSafePath(candidate, cacheDir)) {
            // Also check shared_docs subfolder in cache
            File sharedDocsDir = new File(cacheDir, "shared_docs");
            candidate = new File(sharedDocsDir, path);
            if (!isSafePath(candidate, sharedDocsDir)) {
                // Check filesDir
                candidate = new File(filesDir, path);
                if (!isSafePath(candidate, filesDir)) {
                    if (docsDir != null) {
                        candidate = new File(docsDir, path);
                        if (!isSafePath(candidate, docsDir)) {
                            throw new SecurityException("Directory traversal attack blocked: " + path);
                        }
                    } else {
                        throw new SecurityException("Directory traversal attack blocked: " + path);
                    }
                }
            }
        }

        return candidate;
    }

    private boolean isSafePath(File target, File baseDir) {
        try {
            String targetCanonical = target.getCanonicalPath();
            String baseCanonical = baseDir.getCanonicalPath();
            return targetCanonical.startsWith(baseCanonical);
        } catch (IOException e) {
            return false;
        }
    }
}
