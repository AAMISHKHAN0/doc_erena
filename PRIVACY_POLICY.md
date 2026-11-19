# Privacy Policy for DocErena

**Last Updated:** November 19, 2026  
**Effective Date:** November 19, 2026  
**Application:** DocErena — Offline Document Scanner & PDF Studio  
**Package Name:** `com.digitalerena.docerena`  
**Developer / Publisher:** DigitalErena (Aamish Khan)  
**Contact Email:** privacy@digitalerena.com / aamishkhan0@gmail.com  

---

## 1. Overview & Core Privacy Guarantee

DocErena is designed and built from the ground up as a **100% Offline, Privacy-First Application**. 

We believe that your personal documents, contracts, identification cards, receipts, and sensitive files should remain completely private. **DocErena does not collect, record, track, transmit, upload, or sell any of your personal information, document scans, camera streams, or device data.**

---

## 2. Zero Network Connection Guarantee

- **No Internet Permission:** DocErena does not include the `android.permission.INTERNET` permission in its Android Manifest.
- **Offline Processing:** All document edge detection, perspective homography cropping, Magic Color image enhancement, and ISO 32000-1 binary PDF compilation run 100% locally on your device's hardware processor.
- **Zero Cloud Telemetry:** DocErena contains zero analytics trackers, zero advertising SDKs, zero third-party telemetry libraries, and zero cloud backups. No data ever leaves your device.

---

## 3. Device Permissions & How They Are Used

DocErena requests only the minimum hardware permissions necessary to provide document scanning functionality. These permissions are requested at runtime with full transparency:

### A. Camera (`android.permission.CAMERA`)
- **Purpose:** Used strictly to display the live camera viewfinder and allow you to capture physical documents, pages, books, and identification cards.
- **Privacy Enforcement:** Camera frames are processed strictly in local device memory. Camera feeds are never recorded in the background, never transmitted over any network, and never accessible to any third party.

### B. Notifications (`android.permission.POST_NOTIFICATIONS`)
- **Purpose:** On devices running Android 13 (API 33) or higher, DocErena requests this permission to notify you when an offline PDF export, page batch compilation, or backup operation finishes.
- **Privacy Enforcement:** Notification alerts are generated purely on your local operating system. No remote push notifications or cloud messaging services are used.

### C. Storage & File Access (Storage Access Framework)
- **Purpose:** When you choose to export a PDF document or import an existing image from your device, DocErena interacts with the standard Android Storage Access Framework (SAF).
- **Privacy Enforcement:** DocErena only accesses the specific files or storage folders that you explicitly select. It has no unrestricted access to your personal files, photos, or media libraries.

---

## 4. Data Storage, Retention, and Deletion

- **Local Storage Only:** All scanned pages, folders, favorites, and documents are stored exclusively within DocErena's sandboxed private application storage on your physical device.
- **User Control:** You retain full ownership and control over all documents. You can rename, reorder, export, or delete any document at any time.
- **Permanent Erasure:** When you delete a document and empty the Recycle Bin (Trash), the file data is permanently and irreversibly destroyed from your device storage.
- **App Uninstallation:** If you uninstall DocErena from your Android device, all documents and settings stored within the app sandbox are immediately and permanently erased by the Android operating system.

---

## 5. Third-Party Services & Libraries

DocErena does **not** integrate with or use any third-party services that collect personal data. Specifically:
- **No Analytics:** No Google Analytics, Firebase, Mixpanel, or Flurry.
- **No Advertising:** No Google AdMob, Unity Ads, or marketing trackers.
- **No Social Logins:** No Facebook, Google, or Twitter login requirements.
- **No External CDNs:** All code, icons, scripts, and libraries are bundled offline directly inside the application binary (`.apk` / `.aab`).

---

## 6. Children's Privacy (COPPA & GDPR Compliance)

DocErena does not address or knowingly collect information from children under the age of 13 (or under 16 in the European Union). Because DocErena collects no data whatsoever from any user, it fully complies with the Children’s Online Privacy Protection Act (COPPA), the General Data Protection Regulation (GDPR), and the California Consumer Privacy Act (CCPA).

---

## 7. Security of Your Information

Because all processing and storage occur strictly on your physical Android device:
- Your files are protected by Android's application sandboxing architecture.
- Sharing of documents only occurs when you explicitly initiate the Android system share sheet (via secure, scoped `FileProvider` URIs) to share a PDF with an app of your choice (such as Email, WhatsApp, or Drive).

---

## 8. Changes to This Privacy Policy

We may update this Privacy Policy from time to time to reflect future software enhancements or regulatory standards. Any updates will be published with an updated "Last Updated" date at the top of this document and within the repository.

---

## 9. Contact Us

If you have any questions, suggestions, or concerns regarding this Privacy Policy or DocErena's offline privacy commitments, please contact us at:

- **Developer:** Aamish Khan
- **Project Repository:** [https://github.com/AAMISHKHAN0/doc_erena](https://github.com/AAMISHKHAN0/doc_erena)
- **Support Email:** `aamishkhan0@gmail.com`
