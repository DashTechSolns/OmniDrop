This is OmniDrop, built on the existing app (dark cyber theme, five-tab nav, storage/thumbnail system from the prior storage batch). This task is UI/layout only - no storage, permissions, or native MediaStore/DocumentFile changes. Reference existing theme tokens in lib/config/theme.dart for all colors.

Do NOT touch: the transfer engine, discovery/networking code, encryption/HTTPS handling, the signing config, the package ID/app name, the Rust/FRB layer, or the storage/folder-grant/MediaStore logic from the previous batch (only touch how its results are DISPLAYED, not how files are fetched/granted).

FIXES TO THE RECENTLY BUILT FILE BROWSER:
1. Grid spacing: the Apps grid currently has too much gap between icons and is not rendering as the intended dense grid (target roughly 6 columns, as many rows as content needs, adjusted sensibly for different screen widths rather than a hardcoded exact count). Tighten spacing so icons sit close together like a normal app-drawer grid, not spread out.
2. Selection toggle: tapping an unselected item selects it, but tapping an already-selected item does not deselect it. Fix so tapping toggles selection both ways (select if unselected, deselect if selected).
3. Videos: these were incorrectly changed to a grid layout. Revert Videos specifically back to a linear/stacked list layout (matching whatever list style Audio or Files currently use), each item showing its real video thumbnail (already implemented in the prior batch) in a list row, not a grid. Only Apps and Images should be grid layouts; Videos and Audio should be lists.
4. File-type icons for the Files/Documents category: these are not currently showing distinguishable icons, making every file look the same. Add clear, distinct icons based on file extension/MIME type: a PDF icon for .pdf, a Word-style icon for .doc/.docx, a spreadsheet icon for .xls/.xlsx, an archive icon for .zip/.rar, an Android icon for .apk, a generic text icon for .txt, and a generic document icon as the fallback for unrecognized types. Use existing Material icons or simple iconography already available in the project's dependencies, do not import a new icon package unless genuinely necessary.

FLOATING TRANSFER DOCK:
1. Remove the current "N selected - X MB" info card entirely - it currently squeezes/shrinks the file browser card when files are selected, which is the problem being fixed here.
2. Add a small floating dock that only appears when one or more files are selected. It should sit just above the Receive button, clinging to the right edge of the screen (not full width, not squeezing any other card).
3. The dock shows only the number of files currently selected (not file size).
4. Every selected file should be visibly highlighted in the file browser (grid or list item shows a clear selected state). Highlights should disappear immediately when a file is deselected.
5. When a transfer is actively in progress, the dock should show a rotating/spinning animation to indicate activity.
6. The file browser card's size/layout must never change or shrink based on selection state or the dock's presence - the dock floats on top, it does not push or resize other content.

SETTINGS AS RIGHT-SIDE MENU:
Convert the Settings screen from its current presentation into a right-side slide-out menu/drawer, matching the existing left-side drawer's interaction pattern (opened from the gear icon in the top bar) but anchored to the right instead of the left. Preserve all existing settings content and functionality, including the Save Location setting from the prior batch - only the presentation/entry point changes.

REMOVE OFFLINE PAGE:
Remove the offline/no-connection page entirely. The app should function normally without requiring any network/internet check gate - local transfer features already work over LAN/hotspot without internet access, so there is no legitimate reason to show an offline blocker. Find wherever this offline-check screen is triggered from and remove that gate, verify no other screen accidentally still depends on it being present.

STAGED FILES CARD (WebDrop page):
1. Center-align all content within the Staged Files card.
2. Place the action buttons (Add Files, Clear staged files) side by side at the bottom of the card, not one above/below the other, and make them equal size.
3. The numbered badge at the top-left of the card (currently showing a fixed "01") should instead show the actual current count of staged files.
4. Remove the separate "(0)" count that currently appears in the card's header text, since the badge from point 3 now represents that number - do not show the count twice.

ME TAB - TRANSFER HISTORY:
Change the transfer history section from its current multi-section/scrollable presentation into a single navigation tab or table-style card. Disable horizontal scrolling for this section entirely - all history should be readable via vertical scroll only, within one consolidated card/tab.

BACKGROUNDS AND GLASS EFFECT:
I will supply two background images separately (one for dark mode, one for light mode) intended to sit behind the app's glass-card UI to enhance the glassmorphism effect with a dynamic colored background rather than a flat solid color. For this task, set up the code structure to support a background image behind the main scaffold/content area for both theme modes (dark theme uses one image, light theme uses the other), using a placeholder solid-color or gradient background if the real image assets aren't available yet. Ensure glass cards remain readable (sufficient blur/opacity) against a busier background image, not just a flat color.

LIGHT MODE TOP BAR:
Currently in light mode the top bar renders as a flat/plain light color. Fix so the top bar in light mode uses a light-mode-appropriate version of the app's accent color treatment (not pure flat white/gray), consistent with how the dark mode top bar already uses a colored/diffused treatment rather than a flat surface color.

GLOBAL CENTER-ALIGNMENT PASS:
Do a pass across the app's existing screens and ensure buttons and cards are center-aligned where appropriate (within their containers/cards), rather than left-aligned by default from unstyled widgets. Apply this consistently but do not restructure layouts that are already intentionally center-aligned from prior batches.

GENERAL RULES:
- This is a UI/Dart-only batch. If you find yourself needing to touch native Kotlin code, stop and note it in your report instead of proceeding, since that would mix risk categories we're keeping separate.
- Reuse existing theme tokens, existing widgets, and existing data layers wherever possible.
- After all changes, do a full static review of every touched file for balanced brackets and correct imports/types.
- Commit with a message like "fix: OmniDrop UI batch 2 (grid fixes, floating dock, settings drawer, offline removal, staged files, Me history, backgrounds)".
- Explicitly push to main. Run `git fetch && git log origin/main -1 --oneline` and paste the output to confirm.

Report back: what was built, anything left as a placeholder (including noting the background images are placeholders until I supply the real files), and confirmation of the push with command output.
