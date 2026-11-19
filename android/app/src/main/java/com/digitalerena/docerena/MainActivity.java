package com.digitalerena.docerena;

import android.Manifest;
import android.app.Activity;
import android.content.ClipData;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.util.Base64;
import android.view.View;
import android.view.Window;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.PermissionRequest;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.Toast;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;

/**
 * DocErena MainActivity.
 * Hosts the offline document scanner and PDF studio web application in an
 * optimized, secure, edge-to-edge hardware-accelerated Android WebView with native bridges.
 * Hardened for release: WebView debugging disabled, broadcast receiver removed, deep-links strictly validated.
 */
public class MainActivity extends Activity {
    private static final int FILE_CHOOSER_REQUEST = 1001;
    private static final int CAMERA_PERMISSION_REQUEST = 1002;

    private static final Set<String> VALID_SCREENS = new HashSet<>(Arrays.asList(
        "splash", "welcome", "onboarding", "onboarding-edit", "home", "camera", "crop", "enhance", "organizer",
        "save", "viewer", "export", "share", "documents", "folder", "create-folder",
        "folders", "favorites", "menu", "action_sheet",
        "search", "trash", "pdf-tools", "merge-pdf", "split-pdf", "compress-pdf",
        "settings", "add-text", "edit-pdf-text", "create-signature", "place-signature",
        "extract-text-ocr", "ocr-result", "annotate-pdf", "protect-pdf", "backup-restore",
        "scan-id-card", "scan-book", "notifications"
    ));

    private WebView webView;
    private ValueCallback<Uri[]> filePathCallback;

    private String sanitizeScreenName(String screen) {
        if (screen == null) return null;
        String trimmed = screen.trim().toLowerCase();
        if (VALID_SCREENS.contains(trimmed)) {
            return trimmed;
        }
        return null;
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // Create root layout
        FrameLayout rootLayout = new FrameLayout(this);
        rootLayout.setBackgroundColor(Color.parseColor("#FCFAFD"));

        // Initialize WebView
        webView = new WebView(this);
        webView.setBackgroundColor(Color.parseColor("#FCFAFD"));
        webView.setOverScrollMode(View.OVER_SCROLL_NEVER);

        // Configure hardware acceleration
        webView.setLayerType(View.LAYER_TYPE_HARDWARE, null);

        // Security Hardening: Disable WebView debugging in production release
        WebView.setWebContentsDebuggingEnabled(false);

        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        settings.setAllowFileAccess(true);
        settings.setAllowContentAccess(true);
        settings.setAllowFileAccessFromFileURLs(true);
        settings.setAllowUniversalAccessFromFileURLs(true);
        settings.setMediaPlaybackRequiresUserGesture(false);
        settings.setUseWideViewPort(true);
        settings.setLoadWithOverviewMode(true);
        settings.setSupportZoom(false);
        settings.setBuiltInZoomControls(false);
        settings.setDisplayZoomControls(false);
        settings.setCacheMode(WebSettings.LOAD_DEFAULT);

        // Native bridge for JavaScript <-> Android communication
        webView.addJavascriptInterface(new DocErenaBridge(), "DocErenaNative");

        // WebChromeClient for Camera permissions & File uploads
        webView.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onPermissionRequest(final PermissionRequest request) {
                runOnUiThread(() -> {
                    for (String res : request.getResources()) {
                        if (PermissionRequest.RESOURCE_VIDEO_CAPTURE.equals(res)) {
                            request.grant(new String[]{PermissionRequest.RESOURCE_VIDEO_CAPTURE});
                            return;
                        }
                    }
                    request.grant(request.getResources());
                });
            }

            @Override
            public boolean onShowFileChooser(WebView view, ValueCallback<Uri[]> callback, FileChooserParams params) {
                if (filePathCallback != null) {
                    filePathCallback.onReceiveValue(null);
                }
                filePathCallback = callback;

                Intent chooserIntent = params.createIntent();
                try {
                    startActivityForResult(chooserIntent, FILE_CHOOSER_REQUEST);
                } catch (Exception e) {
                    filePathCallback = null;
                    return false;
                }
                return true;
            }
        });

        // WebViewClient with strict navigation sandboxing
        webView.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri uri = request.getUrl();
                if (uri != null) {
                    String uriStr = uri.toString();
                    if (uriStr.startsWith("file:///android_asset/")) {
                        return false;
                    }
                    // Outside links open in system browser to protect local storage
                    if ("http".equals(uri.getScheme()) || "https".equals(uri.getScheme())) {
                        try {
                            Intent browserIntent = new Intent(Intent.ACTION_VIEW, uri);
                            startActivity(browserIntent);
                            return true;
                        } catch (Exception ignored) {
                        }
                    }
                }
                return super.shouldOverrideUrlLoading(view, request);
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                super.onPageFinished(view, url);
                Intent curIntent = getIntent();
                if (curIntent != null && curIntent.hasExtra("screen")) {
                    String targetScreen = sanitizeScreenName(curIntent.getStringExtra("screen"));
                    if (targetScreen != null && !targetScreen.isEmpty()) {
                        view.evaluateJavascript("if (typeof navigateTo === 'function') navigateTo('" + targetScreen + "');", null);
                    }
                }
            }
        });

        rootLayout.addView(webView, new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ));

        // Set content view before configuring window decor
        setContentView(rootLayout);

        // Edge-to-Edge System Bar Configuration
        setupEdgeToEdge();

        // Check camera permission
        checkCameraPermission();

        // Load offline DocErena studio with validated screen routing intent support
        Intent intent = getIntent();
        String initialScreen = null;
        if (intent != null && intent.hasExtra("screen")) {
            initialScreen = sanitizeScreenName(intent.getStringExtra("screen"));
        }
        String startUrl = "file:///android_asset/index.html";
        if (initialScreen != null && !initialScreen.isEmpty()) {
            startUrl += "#" + initialScreen;
        }
        webView.loadUrl(startUrl);
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        if (webView != null && intent != null && intent.hasExtra("screen")) {
            String targetScreen = sanitizeScreenName(intent.getStringExtra("screen"));
            if (targetScreen != null && !targetScreen.isEmpty()) {
                webView.post(() -> {
                    webView.evaluateJavascript("if (typeof navigateTo === 'function') navigateTo('" + targetScreen + "');", null);
                });
            }
        }
    }

    private void setupEdgeToEdge() {
        try {
            Window window = getWindow();
            if (window == null) return;

            View decor = window.getDecorView();

            window.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS);
            window.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_NAVIGATION);
            window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS);
            window.setStatusBarColor(Color.TRANSPARENT);
            window.setNavigationBarColor(Color.TRANSPARENT);

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                WindowInsetsController controller = window.getInsetsController();
                if (controller != null) {
                    int appearance = WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS
                                   | WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS;
                    controller.setSystemBarsAppearance(appearance, appearance);
                }
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                if (decor != null) {
                    decor.setSystemUiVisibility(
                        View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                        | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                        | View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
                        | View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
                    );
                }
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                if (decor != null) {
                    decor.setSystemUiVisibility(
                        View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                        | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                        | View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
                    );
                }
            }
        } catch (Throwable ignored) {
        }
    }

    private void checkCameraPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
                requestPermissions(new String[]{Manifest.permission.CAMERA}, CAMERA_PERMISSION_REQUEST);
            }
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == CAMERA_PERMISSION_REQUEST) {
            isRequestingCameraPermission = false;
            boolean granted = (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED)
                    || (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED);
            if (pendingPermissionRequest != null) {
                if (granted) {
                    pendingPermissionRequest.grant(pendingPermissionRequest.getResources());
                } else {
                    pendingPermissionRequest.deny();
                }
                pendingPermissionRequest = null;
            }
            if (webView != null) {
                webView.post(() -> {
                    webView.evaluateJavascript("if (typeof window.onCameraPermissionResult === 'function') { window.onCameraPermissionResult(" + granted + "); } else if (window.onCameraPermissionGranted && " + granted + ") { window.onCameraPermissionGranted(); }", null);
                });
            }
        }
        if (requestCode == NOTIFICATION_PERMISSION_REQUEST) {
            boolean granted = (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED);
            if (webView != null) {
                webView.post(() -> {
                    webView.evaluateJavascript("if (typeof window.onNotificationPermissionResult === 'function') { window.onNotificationPermissionResult(" + granted + "); }", null);
                });
            }
        }
    }

    private void dummyEnd() {
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == FILE_CHOOSER_REQUEST) {
            if (filePathCallback != null) {
                Uri[] results = null;
                if (resultCode == Activity.RESULT_OK && data != null) {
                    if (data.getData() != null) {
                        results = new Uri[]{data.getData()};
                    } else if (data.getClipData() != null) {
                        ClipData clip = data.getClipData();
                        results = new Uri[clip.getItemCount()];
                        for (int i = 0; i < clip.getItemCount(); i++) {
                            results[i] = clip.getItemAt(i).getUri();
                        }
                    }
                }
                filePathCallback.onReceiveValue(results);
                filePathCallback = null;
            }
        } else {
            super.onActivityResult(requestCode, resultCode, data);
        }
    }

    @Override
    public void onBackPressed() {
        if (webView != null) {
            webView.evaluateJavascript("typeof window.handleHardwareBack === 'function' ? window.handleHardwareBack() : false", value -> {
                if ("false".equals(value) || "null".equals(value)) {
                    if (webView.canGoBack()) {
                        webView.goBack();
                    } else {
                        MainActivity.super.onBackPressed();
                    }
                }
            });
        } else {
            super.onBackPressed();
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (webView != null) webView.onResume();
    }

    @Override
    protected void onPause() {
        if (webView != null) webView.onPause();
        super.onPause();
    }

    @Override
    protected void onDestroy() {
        if (webView != null) {
            webView.destroy();
            webView = null;
        }
        super.onDestroy();
    }

    /**
     * Native JavaScript interface exposed to the WebView under 'DocErenaNative'.
     */
    public class DocErenaBridge {
        @JavascriptInterface
        public void showToast(String message) {
            runOnUiThread(() -> Toast.makeText(MainActivity.this, message, Toast.LENGTH_SHORT).show());
        }

        @JavascriptInterface
        public String getAppVersion() {
            return "3.0.0-release";
        }

        @JavascriptInterface
        public void sharePdf(String base64Data, String filename, String title) {
            runOnUiThread(() -> {
                try {
                    File sharedDocsDir = new File(getCacheDir(), "shared_docs");
                    if (!sharedDocsDir.exists()) {
                        sharedDocsDir.mkdirs();
                    }

                    String safeName = (filename != null && !filename.trim().isEmpty()) ? filename.trim() : "DocErena_Export.pdf";
                    if (!safeName.toLowerCase().endsWith(".pdf")) {
                        safeName += ".pdf";
                    }

                    File pdfFile = new File(sharedDocsDir, safeName);
                    byte[] data = Base64.decode(base64Data, Base64.DEFAULT);
                    FileOutputStream fos = new FileOutputStream(pdfFile);
                    fos.write(data);
                    fos.flush();
                    fos.close();

                    Uri contentUri = Uri.parse("content://com.digitalerena.docerena.fileprovider/" + safeName);

                    Intent shareIntent = new Intent(Intent.ACTION_SEND);
                    shareIntent.setType("application/pdf");
                    shareIntent.putExtra(Intent.EXTRA_STREAM, contentUri);
                    shareIntent.putExtra(Intent.EXTRA_SUBJECT, safeName);
                    shareIntent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);

                    Intent chooser = Intent.createChooser(shareIntent, title != null ? title : "Share PDF Document");
                    chooser.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                    startActivity(chooser);
                } catch (Exception e) {
                    Toast.makeText(MainActivity.this, "Sharing error: " + e.getMessage(), Toast.LENGTH_LONG).show();
                }
            });
        }

        @JavascriptInterface
        public void savePdf(String base64Data, String filename) {
            runOnUiThread(() -> {
                try {
                    File docsDir = getExternalFilesDir(Environment.DIRECTORY_DOCUMENTS);
                    if (docsDir == null) {
                        docsDir = getFilesDir();
                    }
                    String safeName = (filename != null && !filename.trim().isEmpty()) ? filename.trim() : "DocErena_Export.pdf";
                    if (!safeName.toLowerCase().endsWith(".pdf")) {
                        safeName += ".pdf";
                    }
                    File pdfFile = new File(docsDir, safeName);
                    byte[] data = Base64.decode(base64Data, Base64.DEFAULT);
                    FileOutputStream fos = new FileOutputStream(pdfFile);
                    fos.write(data);
                    fos.flush();
                    fos.close();

                    Toast.makeText(MainActivity.this, "PDF saved to: " + pdfFile.getAbsolutePath(), Toast.LENGTH_LONG).show();
                } catch (Exception e) {
                    Toast.makeText(MainActivity.this, "Save error: " + e.getMessage(), Toast.LENGTH_LONG).show();
                }
            });
        }

        @JavascriptInterface
        public String protectPdf(String base64Data, String password, String filename) {
            final String safeName = (filename != null && !filename.trim().isEmpty()) ? filename.trim() : "DocErena_Protected.pdf";
            final String finalName = safeName.toLowerCase().endsWith(".pdf") ? safeName : (safeName + ".pdf");
            File docsDir = getExternalFilesDir(Environment.DIRECTORY_DOCUMENTS);
            if (docsDir == null) {
                docsDir = getFilesDir();
            }
            final File pdfFile = new File(docsDir, finalName);
            try {
                byte[] data = Base64.decode(base64Data, Base64.DEFAULT);
                FileOutputStream fos = new FileOutputStream(pdfFile);
                fos.write(data);
                fos.flush();
                fos.close();
                final String path = pdfFile.getAbsolutePath();
                runOnUiThread(() -> Toast.makeText(MainActivity.this, "Protected PDF saved: " + finalName, Toast.LENGTH_LONG).show());
                return path;
            } catch (Exception e) {
                runOnUiThread(() -> Toast.makeText(MainActivity.this, "Protect PDF error: " + e.getMessage(), Toast.LENGTH_LONG).show());
                return "";
            }
        }

        @JavascriptInterface
        public void shareText(String text, String title) {
            runOnUiThread(() -> {
                try {
                    Intent intent = new Intent(Intent.ACTION_SEND);
                    intent.setType("text/plain");
                    intent.putExtra(Intent.EXTRA_TEXT, text);
                    startActivity(Intent.createChooser(intent, title != null ? title : "Share"));
                } catch (Exception e) {
                    Toast.makeText(MainActivity.this, "Share error: " + e.getMessage(), Toast.LENGTH_SHORT).show();
                }
            });
        }
    }
}
