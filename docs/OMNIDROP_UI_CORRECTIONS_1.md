This is OmniDrop, built on the existing UI overhaul (bottom nav, top bar, Me profile, OS Pairs, side menu, WebDrop). This task corrects specific layout, styling, and theme issues found after reviewing the built app. Reference the existing theme tokens in lib/config/theme.dart for all colors — do not invent new colors.

Do NOT touch: the transfer engine, discovery/networking code, encryption/HTTPS handling, the signing config, or the package ID/app name.

THEME FIX (do this first, it affects everything below):
The app is currently rendering in a flat light/white theme instead of the intended dark cyber theme (Background #090D16, Primary #06B6D4, Secondary #8B5CF6, Success/Accent #10B981) on most screens (drawer, Me, OS Pairs, Settings, WebDrop). Investigate why: check whether the app's theme mode defaults to system/light instead of the dark cyber theme, and whether the AppBar and BottomNavigationBar widgets across these screens are pulling their background color from the theme's color scheme or falling back to Flutter/Material defaults. Fix so that:
- The dark cyber theme renders correctly and consistently across every screen, not just the original Transfer screen.
- The AppBar and BottomNavigationBar specifically use a background derived from the app's primary/secondary palette (a subtle gradient or diffused tone is fine) rather than a plain flat light surface, so the app has a clear, consistent visual signature top and bottom.
- Confirm light theme still works too when explicitly selected, it should just no longer be the accidental default.

TRANSFER SCREEN:
1. Move the top-bar 3-dot options icon so it sits immediately adjacent to (behind) the OmniDrop logo/wordmark, closing the current gap between them.
2. Remove the "Send | Receive" segmented tab bar entirely.
3. Add a floating "Send" button/card that hovers near the top of the screen (replacing the removed tab bar's space), which on tap shows a pop-up card with a temporary QR code and the three toggle options already specified in the earlier OMNIDROP_UI_SPEC (connection mode toggle, multiple-recipients toggle, and the applicable mode-specific option).
4. Add a floating "Receive" button that hovers just above the bottom navigation bar.
5. Convert the 6 selection buttons (File, Media, Paste, Text, Folder, App) from a 2x3 grid into a single row of horizontally scrollable pill/badge-style buttons that function as their own mini-tabs.
6. Make the selection area's background transparent so it takes on the screen's theme background rather than a distinct card color.
7. Turn the "Selection" section into an inset layer card that hosts an in-app file browser (this may currently be a placeholder if the storage/file-browser overhaul hasn't landed yet — if so, leave a clear placeholder here and note it in your report; do not attempt the full file-browser rebuild in this task, that is a separate upcoming task).

WEBDROP SCREEN:
1. Remove the standalone "Receive from browser" button. The WebDrop page itself should already support both upload and download in one flow; this separate button is redundant.
2. Turn the "Staged files" section into an inset layer card with two explicit buttons: "Add/select files" and "Clear staged files" (replacing the current plain text link).
3. Add a floating "Start WebDrop" button that hovers just above the bottom navigation bar, matching the style of the Send/Receive floating buttons on the Transfer screen.

SETTINGS SCREEN:
1. Remove the "General" section header/card wrapper.
2. Remove the "Auto Finish" toggle from the UI. Files should always finish/save automatically without a manual accept/confirm step, with no user-facing setting for this.
3. Do NOT remove the checksum verification behavior. Remove the "Verify checksums when receiving files" (and the equivalent sending-side toggle if present) from the visible UI, but keep the underlying checksum verification always running silently in the background on every transfer. This is a safety check, not a user-facing option; hide the toggle, keep the behavior.
Note: leave the "Save to folder" setting as-is for now, it will be replaced in a separate upcoming storage task, do not modify it in this pass.

ME (PROFILE) TAB:
1. Redesign the layout so all elements (avatar, device name, stats) are horizontally centered rather than left-aligned/scattered.
2. Convert the stats section (Total sent, Total received, Unique senders, Total data transferred) from a vertical stacked list into a horizontally scrollable row of cards/tabs.

GENERAL RULES:
- Reuse existing theme tokens, existing widgets/components, and existing data layers wherever possible.
- Keep changes scoped to layout, styling, and the specific items listed above. Do not modify transfer/discovery/crypto logic or the storage/permissions system.
- After all changes, run whatever checks you can in this container (Flutter/Rust CLIs are expected to be unavailable, that's fine, just do your best static review).
- Commit with a clear message like "fix: OmniDrop UI corrections (theme consistency, floating actions, layout fixes)".
- Explicitly PUSH the commit to main and confirm the push succeeded with the new commit hash. Do not just report a local commit.

Report back: what was built, anything left as a placeholder, and confirmation the push completed.
