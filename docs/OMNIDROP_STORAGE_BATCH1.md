This is OmniDrop, built on LocalSend's existing architecture (Dart/Flutter app, Kotlin native layer for Android-specific features like Copy Phone/MediaStore access, Rust backend for transfer/crypto, theme tokens in lib/config/theme.dart). This task fixes the in-app file browser's storage/permissions layer and redesigns its Apps/Images layout. Do NOT touch the transfer engine, discovery/networking code, encryption/HTTPS handling, the signing config, the package ID/app name, or the Rust/FRB layer.

CONTEXT - CURRENT BROKEN STATE:
The in-app file browser currently has these problems:
1. The Downloads, Images, Videos, and Audio categories show "No video/audio/image/download found" or "access was not granted" errors and do not actually list files.
2. The Files category works but re-prompts for storage access every single time it's opened, instead of remembering a previous grant.
3. Only Text, Apps, and Files partially work, and not in the layout described below.
4. No file in the browser shows a real thumbnail; investigate what, if anything, currently shows per item.

PART A - STORAGE ARCHITECTURE (fixes the permission/access bugs):

Implement a one-time folder-grant storage system using Android's Storage Access Framework, specifically the persisted-permission folder-tree approach (ACTION_OPEN_DOCUMENT_TREE + ContentResolver.takePersistableUriPermission), NOT the broad MANAGE_EXTERNAL_STORAGE permission (that permission is restricted by Google Play policy to dedicated file-manager apps and would risk store rejection).

1. On first use of the file browser (or from a Settings entry point, add both), prompt the user once via the system folder picker to select a root folder (defaulting to suggesting "Internal storage" if the picker allows a default hint). Persist this permission using takePersistableUriPermission so it survives app restarts and never needs to be requested again for that tree.
2. Once granted, use the DocumentFile API (androidx.documentfile) to browse, read, and write within that granted tree. This must work identically on Android 8.0 (API 26) through the latest Android version — no separate code paths for old vs new Android, this API works consistently across that whole range.
3. Auto-create (if not already present) a folder structure at the root of the granted tree: a parent folder named "OmniDrop" containing subfolders: image, video, audio, app, folder, other. Use DocumentFile creation APIs for this, check for existing folders before creating to avoid duplicates on repeat app launches.
4. Add a "Save Location" setting (in the existing Settings screen) letting the user choose between "Internal storage" and "SD card" for where received files get routed by category into the folder structure above. The "SD card" option must only appear if the device actually has removable/secondary storage available (check via Android's storage volume APIs); hide it entirely on devices without a card slot, do not show a non-functional option.
5. Fix the Downloads/Images/Videos/Audio category browsers to actually query and list real files using Android's MediaStore API (MediaStore.Images, MediaStore.Video, MediaStore.Audio, and MediaStore.Downloads as appropriate) combined with the granted folder-tree access from above where needed. These categories should show real files from the device, not just files inside the OmniDrop app folder - MediaStore queries the whole device's media library (subject to normal Android scoped-storage visibility rules), which is the correct behavior for a "browse my phone's photos/videos/audio/downloads" feature.
6. Fix the Files category to stop re-prompting for access every time - it should reuse the persisted folder-tree permission from step 1 rather than requesting a fresh SAF picker each time it's opened.

PART B - REAL THUMBNAILS:

1. Images: show actual real thumbnail previews (small, memory-efficient decoded bitmaps, not full-resolution images) using Android's ThumbnailUtils or MediaStore's built-in thumbnail loading APIs. Do not load full images into memory for a grid view, use proper thumbnail-sized decoding.
2. Videos: show actual real video frame thumbnails using the same MediaStore thumbnail APIs (MediaStore.Video.Thumbnails or the modern loadThumbnail() API depending on Android version available).
3. Audio: show embedded album art when the audio file actually has it (via MediaMetadataRetriever or similar). When a file has no embedded album art, fall back to a clean generic music-note icon, do not show a broken image or blank space.
4. Documents and generic files (PDF, Word, zip, APK, text, etc.): do NOT attempt to render real content previews, that is out of scope and expensive. Instead show a clean, recognizable file-type icon based on file extension/MIME type (a PDF icon for .pdf, a Word-style icon for .doc/.docx, an archive icon for .zip, an Android icon for .apk, a generic document icon for unrecognized types, etc.). Reuse Material icons or simple existing iconography already available in the project's dependencies rather than importing new icon packs if avoidable.
5. All thumbnail/icon loading must be efficient for a grid view with many items (use lazy loading / proper widget recycling patterns already idiomatic in Flutter, e.g. GridView.builder, not GridView with a fully materialized list) - this app needs to stay fast on older/lower-end Android 8 devices per existing project priorities.

PART C - APPS AND IMAGES GRID LAYOUT:

1. Apps category: currently shows APKs as a linear stack with a '+' button per item, aligned to the right edge, and the app name shown across two rows (display name, then package name below it). Change this to: a grid layout (approximately 4 rows by 6 columns, adjust to fit the screen width sensibly on different device sizes rather than a hardcoded exact count if that fits better with Flutter's grid widgets), showing the app's real icon plus only its main display name (not the package name) underneath, no linear stacking, no per-item '+' button - use the existing selection mechanism (whatever marks an item as selected elsewhere in the file browser, e.g. a highlight/checkmark) instead of a separate '+' button per item.
2. Images category: once Part A's fix makes images actually load, display them in a similar grid layout (not linear/list), using the real thumbnails from Part B.
3. Keep Videos and Audio in whatever list or grid format is already idiomatic for this app's existing file browser UI, just ensure they show real thumbnails per Part B - only Apps and Images need the specific grid restructuring described here unless you find Videos/Audio already use a comparable linear-stack layout that has the same readability problem, in which case apply the same grid fix there too and note that you did so.

GENERAL RULES:
- Reuse existing theme tokens, existing widgets, and existing permission/dialog patterns where they already exist in this codebase, rather than inventing new ones.
- This task touches native Android (Kotlin) code for MediaStore/DocumentFile/thumbnail access, and Dart/Flutter code for the browser UI and grid layout. Keep the native-layer changes and the UI-layer changes clearly separated in your implementation so they're easy to reason about independently.
- Do not modify transfer/discovery/crypto logic, the Rust layer, or anything unrelated to the file browser and storage system described above.
- After all changes, do a full static review of every touched file for balanced brackets, correct imports, and correct types (Kotlin type mismatches and Dart syntax errors have been the main build failure causes in recent rounds, be careful here).
- Commit with a clear message like "feat: storage architecture overhaul (folder grant, MediaStore fixes, real thumbnails, Apps/Images grid)".
- Explicitly push to main. Run `git fetch && git log origin/main -1 --oneline` and paste the output to confirm.

Report back: what was built, any part left as a placeholder or deferred with a clear reason why, and confirmation of the push with the command output.
