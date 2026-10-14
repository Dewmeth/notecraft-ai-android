# NoteCraft AI — handwritten note scanner for Android

**This is editable Flutter source code, not a finished/tested APK.**

## What it currently implements

- Android camera capture, import multiple pictures from gallery
- A notebook page organizer (tap to open, long-press/drag to reorder, remove)
- Four enhancement styles: Clean paper, Color boost, Black ink, Original
- Background-isolate processing to avoid freezing the Flutter UI
- Rotate each page by 90° increments
- On-device ML Kit Latin OCR with editable transcription
- Offline keyword-based rough topic classification and explanatory study tips
- Optional AI endpoint for deeper explanations using OCR text and scan images
- Multi-page PDF export and JPEG sharing via the Android share sheet
- Locally persisted scan sessions (app-private documents and preferences)

**Engineering honesty:** The app preserves handwritten strokes and diagrams and cleans the pixels; it does NOT generate new handwriting, reconstruct missing mathematical symbols, infer full diagram meaning offline, auto-crop page edges, or fully deskew perspective. Handwritten OCR is fallible. AI explanations are optional and require a server.

## Generate an actual Android APK — GitHub Actions (no development software needed)

1. Sign into [GitHub](https://github.com/), and create a **new private repository** (e.g., `notecraft-ai`).
2. Extract this ZIP. Upload **all extracted contents**, including `.github/workflows/build-android-apk.yml`, into the repository root. To preserve hidden folders, prefer using Git (`git add -A && git commit && git push`) rather than dragging files from Explorer.
3. Open your repository's **Actions** tab, select **Build Android APK**, and select **Run workflow**. On first use, enable Actions for your private repo if asked. A push to main also runs it.
4. When the workflow finishes successfully, open that run and download `NoteCraft-AI-Android-APK` from the Artifacts section.
5. Unzip it and transfer `app-debug.apk` to your Android phone. Tap to install; approve installing from this source when Android asks.
6. If the workflow fails, read the failed step's log. File an issue or share the log; it is not yet tested on a real phone.

**Avoid exposing private note images to online AI unless you trust the server.** The OCR and image cleanup work locally in the phone app, but first install of ML Kit may require dependencies when building the APK. Do not upload source archives containing `.env` or API keys.

## Build locally (Windows / macOS / Linux)

Install [Flutter](https://docs.flutter.dev/get-started/install), Android Studio and Android SDK, with a JDK and licensed Android SDK:

```bash
flutter doctor
cd notecraft_ai
flutter create . --platforms=android --project-name=notecraft_ai --org=com.notecraft
python scripts/patch_android.py
flutter pub get
flutter analyze
flutter test
flutter run
flutter build apk --debug
```

APK location: `build/app/outputs/flutter-apk/app-debug.apk`

You may later sign a release APK using `flutter build apk --release` and your own persistent signing key. Avoid distributing debug APKs as production releases; different build machines can use different debug signatures, requiring uninstall before upgrades.

## Which code changes affect the final app?

| Desired change | File and section |
|---|---|
| App colors, typography and navigation | `lib/main.dart`, `Ink` class, `NoteCraftApp` |
| Camera/photo import | `lib/main.dart`, `_camera`, `_gallery` |
| Better scanning / ink appearance | `lib/services/enhancement.dart`, `_processPixels` |
| Capture more pages, reorder / remove | `lib/main.dart`, `_addFiles`, page organizer |
| OCR text + correcting errors | `lib/main.dart`, `_addFiles`, `_editOcr` |
| Offline topics and tips | `lib/services/note_insights.dart`, `categories`, `guides` |
| AI explanations | `lib/services/ai_service.dart`, `backend/server.py` |
| PDF / JPEG image export | `lib/services/export_service.dart` |
| APK display name, Android icon, permission configuration | `scripts/patch_android.py`, `resources/icons/` |
| Automated APK build | `.github/workflows/build-android-apk.yml` |

The source includes inline comments explaining what each stage does to the resulting note scan.

## Optional AI setup (for deeper subject identification and explanations)

The offline scan / PDF / OCR features do not need a key or backend. For optional AI:

1. Create a server or VM with HTTPS and an HTTPS reverse proxy.
2. In `backend/`, install: `pip install -r requirements.txt`.
3. Set `OPENAI_API_KEY` **on the server only**. Optional `OPENAI_MODEL` environment variable.
4. Start the server: `uvicorn server:app --host 127.0.0.1 --port 8000`.
5. Add **authentication, rate limits, logging redaction and network access controls** before exposing to the public Internet. The included FastAPI server is a development example, not a hardened deployment.
6. Enter `https://your-own-server.example/explain` in the app's Settings. In Insights, tap **Explain with AI**; confirm image/text transfer.

The app sends a maximum of 3 reduced-size images and up to 12,000 OCR characters. This request consumes API usage, may have costs, and may contain sensitive notes. Verify all AI-generated facts and formulas.

## Existing limitations / next development milestones

- **High priority:** camera on-device test; solve any ML Kit/Gradle compatibility issues from build logs.
- Add automatic corner detection, crop and perspective deskew.
- Add multi-page photo capture directly within a custom camera preview.
- Add region-based separation of handwriting and diagrams; optionally AI-redraw diagrams after user confirmation.
- Add secure AI login to a rate-limited backend and optional on-device handwriting models.
- Add image-to-searchable-text layer in PDFs, if desired.

## Troubleshooting

- If a previous experimental version with the same name was installed, uninstall it before installing this independent Flutter debug build.
- If Flutter cannot resolve dependencies, update Flutter stable: `flutter upgrade`.
- If Google ML Kit cannot build, verify Android `minSdk` >= 23 and `compileSdk` >= 36 after `flutter create .`.
- If AI doesn't work, the app is still fully usable offline; AI requires a reachable HTTPS server and API provider account.
- If scanning handwritten formulas poorly, correct OCR in the Insights screen; the exported graphic remains intact.

### One-click local build scripts

If you have Flutter and the Android SDK on your computer, double-click `BUILD_WINDOWS.bat` on Windows, or run `./BUILD_MAC_LINUX.sh` on macOS/Linux. These run `flutter create`, configure Android SDK targets, resolve dependencies, and build a debug APK. An initial build may take several minutes and download libraries.

### Source ownership and licenses

The NoteCraft prototype source created here is provided for you to edit and extend. Third-party Flutter packages and Android SDK components retain their own licenses. Use original images, fonts, app names and model providers responsibly before publishing.

## Extra: one-command GitHub APK builder for Windows

This project includes `BUILD_APK_ON_GITHUB.bat` (double-click on Windows) and `BUILD_APK_ON_GITHUB.ps1`. It creates a **new, private** GitHub repository (never modifies your existing repos), uploads the Flutter source, waits for the cloud Android build, and downloads the compiled APK into the project folder as `NoteCraft_AI.apk`.

Requirements: Git for Windows, [GitHub CLI](https://cli.github.com/) (`winget install --id GitHub.cli`), an account that can create a private GitHub repo, and an internet connection. In PowerShell, from the extracted folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\BUILD_APK_ON_GITHUB.ps1
```

If the default repo name already exists, choose another: `powershell -ExecutionPolicy Bypass -File .\BUILD_APK_ON_GITHUB.ps1 -RepositoryName notecraft-build-2`.

This script is provided as an automation for building the APK; it does **not** mean the APK has been compiled or device-tested by the author. If GitHub Actions reports an error, use the logs to determine which package/build issue needs fixing.
