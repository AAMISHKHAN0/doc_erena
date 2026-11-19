# Google Play Console Upload Guide — DocErena AAB

This guide provides complete, step-by-step instructions for uploading and publishing the **DocErena** Android App Bundle (`.aab`) to the **Google Play Console**.

---

## 1. Release Files & Metadata

Your compiled, signed, and validated release files are located in your workspace:

| File Name | File Path | File Size | Description |
| :--- | :--- | :--- | :--- |
| **`docerena_release.aab`** | `d:\camscanner\docerena_release.aab` | 7.25 MB | **Primary File to Upload** (Google Play Store format) |
| **`docerena_v5_phonetest.aab`** | `d:\camscanner\docerena_v5_phonetest.aab` | 7.25 MB | Identical binary with build version tag |
| **`docerena_v5_phonetest.apk`** | `d:\camscanner\docerena_v5_phonetest.apk` | 7.26 MB | Standalone APK for direct phone sideloading |
| **Signing Keystore** | `d:\camscanner\build_apk\docerena.jks` | 2.6 KB | Keystore used to sign the bundle |

### Key Bundle Metadata:
- **Package Name (Application ID)**: `com.digitalerena.docerena`
- **Version Name**: `5.0.0-phonetest`
- **Version Code**: `5`
- **Target SDK**: `36` (Android 16 — well exceeds Google's minimum requirement of API 34+)
- **Minimum SDK**: `24` (Android 7.0 Nougat — supports 95%+ of active Android devices)
- **Signature Schemes**: Signed with v1, v2, and v3 schemes via `docerena.jks` (alias: `docerena`)

---

## 2. Prerequisites Before Uploading

1. **Google Play Developer Account**:
   - If you do not have one yet, sign up at [play.google.com/console](https://play.google.com/console).
   - Requires a one-time \$25 USD registration fee and identity verification.
2. **Store Listing Assets** (Ready in your repository):
   - **App Icon**: 512 × 512 px PNG (32-bit color, no transparency) — available at `build_apk/assets/docerena-logo.png`.
   - **Feature Graphic**: 1024 × 500 px PNG/JPEG — available at `build_apk/assets/welcome_illustration.png`.
   - **Screenshots**: At least 2 phone screenshots (16:9 or 18:9 aspect ratio) — available in `review_package/02_SCREENSHOTS/` and `verification/screenshots/`.

---

## 3. Step-by-Step Upload Instructions

### Step 1: Create Your App in Google Play Console
1. Log in to [Google Play Console](https://play.google.com/console).
2. On the top right of the dashboard, click the blue **"Create app"** button.
3. Fill in the initial app details:
   - **App name**: `DocErena - Document Scanner & PDF` (or `DocErena`)
   - **Default language**: English (United States)
   - **App or game**: Select **App**
   - **Free or paid**: Select **Free**
4. Check the declarations:
   - Check **Developer Program Policies**
   - Check **US export laws**
5. Click **"Create app"** at the bottom right.

---

### Step 2: Set Up Play App Signing
Google Play requires Play App Signing for all new apps:
1. In the left navigation menu, go to **Release** > **Setup** > **App integrity**.
2. Under **Play App Signing**:
   - Google recommends: **"Use Google-generated key"** (Default).
   - If you want to use the existing `docerena.jks` upload key: select **"Export and upload a key from Java keystore"** and follow the prompt with `build_apk/docerena.jks`.
   - Otherwise, letting Google manage the app signing key while using `docerena.jks` as your upload key is the simplest, standard path.

---

### Step 3: Complete App Content Declarations (Crucial for Fast Approval)

In the left menu, scroll down to **Policy and programs** > **App content**. Complete each of the required declaration tasks:

#### A. Privacy Policy
- Provide a link to your public privacy policy URL (e.g., your GitHub Pages, website, or DocErena privacy policy page).
- *Sample Privacy Policy statement*: "DocErena is a 100% offline document scanner. It does not collect, transmit, or share any personal data, scan images, or telemetry. All processing occurs locally on the user's device."

#### B. App Access
- Select: **"All functionality is available without special access"** (DocErena requires no account or login).

#### C. Ads
- Select: **"No, my app does not contain ads"**.

#### D. Content Rating
- Click **"Start questionnaire"**.
- Enter your email address.
- Category: Select **"Utility, Productivity, Communication, or other"**.
- Answer the questionnaire (violence: No, sexual content: No, offensive language: No, controlled substances: No).
- Click **Save**, then **Next**, then **Submit** to receive your **PEGI 3 / Everyone** rating.

#### E. Target Audience and Content
- Target age group: Select **18 and over** (and/or 13–17).
- Appeals to children: Select **"No"**.

#### F. News Apps / COVID-19 / Financial / Government Apps
- Answer **"No"** to each of these specific categories.

#### G. Data Safety (Most Important!)
Because DocErena is **100% offline** and has **zero internet permissions**, completing Data Safety is simple and safe:
1. Does your app collect or share any of the required user data types?  
   👉 Select **"No"**.
2. Is all of the user data collected by your app encrypted in transit?  
   👉 Select **"Not applicable (no data collected)"**.
3. Do you provide a way for users to request that their data be deleted?  
   👉 Select **"Yes"** (Users delete documents locally inside the app / Recycle Bin).
4. Review and **Submit**.

---

### Step 4: Set Up Main Store Listing
In the left menu, go to **Grow** > **Store presence** > **Main store listing**:
1. **App details**:
   - **Short description** (up to 80 chars):  
     `Fast, 100% offline document scanner and PDF studio with zero cloud tracking.`
   - **Full description** (up to 4000 chars):  
     ```markdown
     DocErena is a powerful, privacy-first mobile document scanner and complete PDF studio designed for high-resolution scanning, edge adjustment, and offline document management.

     KEY FEATURES:
     • 100% Offline Privacy: Zero cloud tracking, zero external network requests. Your documents never leave your phone.
     • High-Resolution Scanner: Live viewfinder with Single, Batch, ID Card (front & back on 1 page), Book spread, and Timestamp modes.
     • Smart Edge Detection & Homography: Draggable 4-corner perspective correction with automatic distortion rectification.
     • Magic Color Enhancement: Contrast-stretching filter removes shadows and optimizes document legibility.
     • Complete PDF Studio: Merge multiple PDFs, split page ranges, compress file size, and export standard ISO 32000-1 PDF files.
     • Local Document Library: Custom colored folders, favorites, instant title search, and a safe two-stage recycle bin.
     • No Account Required: Start scanning immediately as a guest.
     ```
2. **Graphics**:
   - **App icon**: Upload `build_apk/assets/docerena-logo.png` (512 × 512 px).
   - **Feature graphic**: Upload `build_apk/assets/welcome_illustration.png` or an export banner (1024 × 500 px).
   - **Phone screenshots**: Upload at least 2–4 screenshots from `review_package/02_SCREENSHOTS/` (e.g., Welcome, Home Dashboard, Camera Viewfinder, Review Pages).
3. Click **"Save"** at the bottom.

---

### Step 5: Create a Release and Upload the AAB

Google Play provides multiple release tracks:
- **Internal Testing**: Available immediately to you and your test team (no review delay). **Recommended first!**
- **Closed Testing (Alpha/Beta)**: Available to invited testers.
- **Production**: Available to everyone on Google Play worldwide.

#### Uploading to Internal Testing (Recommended First Step):
1. In the left menu, under **Release**, select **Testing** > **Internal testing**.
2. In the top right, click **"Create new release"**.
3. Under **App bundles**:
   - Drag and drop **`d:\camscanner\docerena_release.aab`** (or `docerena_v5_phonetest.aab`).
   - The upload will process and verify your bundle:
     * *Package name*: `com.digitalerena.docerena`
     * *Version code*: `5`
     * *Version name*: `5.0.0-phonetest`
4. **Release details**:
   - **Release name**: `5.0.0 (5)`
   - **Release notes**:  
     ```
     Initial release of DocErena 5.0.0:
     - 100% offline document scanner and PDF studio
     - High-precision 4-corner perspective crop and Magic Color enhancement
     - Single, Batch, ID Card, Book, and Timestamp capture modes
     - Standard ISO 32000-1 PDF export with custom page sizes and compression
     ```
5. Click **"Next"** at the bottom right.
6. Review any warnings (standard recommendations) and click **"Save and publish"** (or **"Start rollout to Internal testing"**).

#### Promoting to Production (Full Public Release):
1. After testing your internal release on your physical phone, go to **Release** > **Production**.
2. Click **"Create new release"**.
3. You can either select your tested AAB from **Add from library** or upload `docerena_release.aab` directly.
4. Click **"Next"**, review the summary, and click **"Send for review"**.
5. Google will review the app (typically 1–3 business days for new accounts). Once approved, DocErena will be live on Google Play!

---

## 4. Why DocErena Passes Google Play Review Easily

DocErena is designed to adhere to Google Play Developer Policies:
1. **Target SDK 36**: Modern Android 16 target exceeds Google's API 34+ requirement.
2. **Zero Internet Permission**: Eliminates the most common cause of policy flags, spyware audits, and COPPA/GDPR compliance friction.
3. **No Background Services / No Receivers**: Clean manifest with zero hidden broadcast receivers.
4. **Scoped File Sharing**: Uses standard Android `FileProvider` (`androidx.core.content.FileProvider`) for private cache sharing.
5. **Clear Permission Justification**:
   - `android.permission.CAMERA`: Used exclusively when the user opens the scanner viewfinder.
   - `android.permission.POST_NOTIFICATIONS`: Requests standard Android 13+ runtime permission for scan/export alerts.

---

## 5. Quick Verification Commands

To verify your AAB locally before uploading:

```powershell
# Validate AAB bundle structure using bundletool
java -jar "d:\camscanner\build_apk\bundletool-all.jar" validate --bundle="d:\camscanner\docerena_release.aab"

# Extract APK set from AAB to verify device compatibility
java -jar "d:\camscanner\build_apk\bundletool-all.jar" build-apks --bundle="d:\camscanner\docerena_release.aab" --output="d:\camscanner\scratch\docerena_extracted.apks" --ks="d:\camscanner\build_apk\docerena.jks" --ks-pass="pass:docerena" --ks-key-alias="docerena" --key-pass="pass:docerena"

# Check bundle checksum
python -c "import hashlib; print(hashlib.sha256(open('d:\\camscanner\\docerena_release.aab', 'rb').read()).hexdigest())"
```
