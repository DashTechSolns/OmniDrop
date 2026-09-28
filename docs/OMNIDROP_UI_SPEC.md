This is OmniDrop, a rebrand of LocalSend, currently building successfully. The app's color palette and theme are already defined in lib/config/theme.dart (Background #090D16, Primary #06B6D4, Secondary #8B5CF6, Success/Accent #10B981). Use that existing theme system for every screen below — do not hardcode new colors, and do not introduce a different palette anywhere.

Do NOT touch: the transfer engine, LAN discovery/networking code, encryption/HTTPS handling, the signing config in build.gradle, or the package ID/app name work already done.

Build the following UI/navigation overhaul:

1. BOTTOM NAVIGATION
Replace the current bottom navigation with 5 tabs in this order: WebDrop, OS Pairs, Transfer (center, styled as a raised/elevated FAB-style button rather than a flat tab), Cloud, Me. "Me" replaces the previous History tab — its content should be the new profile screen described in item 4 (which still includes historical transfer stats, so no data/functionality is lost, just relocated).

2. TOP BAR
Redesign the top app bar with:
- Left: the OmniDrop logo, with a 3-dot vertical icon button next to it. Tapping it opens a left-side drawer/menu (see item 6).
- Right: a 3-line ("hamburger"-style) icon button that opens a dropdown with three items: "Scan Connect" (opens the QR scanner), "Share OmniDrop" (opens a share sheet/side panel with app share options), "Copy Phone" (for now, this can open a placeholder screen saying "Device migration — coming soon," since this is a larger feature we're building separately later). Rightmost: a settings gear icon.

3. TRANSFER SCREEN
Keep the existing Send/Receive functionality intact, but ensure the screen lets users browse and select any file type (documents, media, folders, etc.) without leaving the app, using Android's existing Storage Access Framework/Photo Picker integration already in the codebase — just make sure the selection UI is exposed cleanly here rather than requiring an app-external redirect. Do not build a fully custom file browser that bypasses SAF; use what the app already has.

4. ME (PROFILE) TAB
Build a profile screen showing: editable device name, editable profile image/avatar, and historical stats already tracked by the app's existing transfer history data (total sent, total received, number of unique devices connected, total data transferred). Pull this from the existing history/database layer — do not invent new tracking, surface what's already recorded.

5. OS PAIRS TAB
Build a simple picker screen showing the supported OS combination pairs (Android, iOS, macOS, Windows, Linux) as visual cards/tiles a user can tap to see a short walkthrough of how to connect between those two platforms using the app's existing transfer/WebDrop methods. This is an informational/navigation screen, not new transfer logic.

6. LEFT SIDE MENU
Build a left-side drawer menu (opened from the top-bar logo's 3-dot button) containing: Theme, Color, Language, Animations, Enable 5G (as a labeled toggle — note in a comment that this only affects UI messaging/preference storage, not actual radio/network control, since apps cannot force cellular generation), Rating, About. Move any "general settings" currently elsewhere in the app into this menu instead of duplicating them.

7. WEBDROP REBRAND FIX
Find wherever the WebDrop web portal's HTML/CSS/JS assets live (a static web-assets folder, likely under app or a shared assets directory) and update all instances of "LocalSend" branding/name/logo there to "OmniDrop," applying the same theme colors from theme.dart to that web page's styling. Also combine the web portal into a single view supporting both upload and download (sending and receiving) rather than receive-only, and add a "staged files" panel where a user can pre-select files before activating the WebDrop session.

GENERAL RULES:
- Reuse existing theme tokens, existing data layers (history, preferences, device info), and existing file-picker/SAF code wherever possible. Don't rebuild what already works.
- Keep changes scoped to navigation, screens, and the web portal's static assets. Do not modify transfer/discovery/crypto logic.
- After all changes, commit with a clear message like "feat: OmniDrop UI/navigation overhaul (bottom nav, top bar, Me profile, OS Pairs, side menu, WebDrop rebrand)".
- Explicitly PUSH the commit to main and confirm the push succeeded with the new commit hash — do not just report a local commit.

Report back: what was built, anything left as a placeholder or unclear, and confirmation the push completed.
