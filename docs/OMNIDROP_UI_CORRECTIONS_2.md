This is OmniDrop, built on the existing app (dark cyber theme, five-tab nav, Transfer/WebDrop/OS Pairs/Cloud/Me screens). This task makes specific corrections and adds a new logo, glass/animation styling, and a full OS Pairs redesign. Reference the existing theme tokens in lib/config/theme.dart for all colors — do NOT introduce a new color palette or change existing hex values. Keep the app's current color identity as the foundation; this task adapts visual style on top of it, it does not replace it.

Do NOT touch: the transfer engine, discovery/networking code, encryption/HTTPS handling, the signing config, the package ID/app name, or the in-app file browser placeholder on the Transfer screen (that is a separate upcoming task, leave its current placeholder state as-is).

LOGO:
A new logo is being added: three connected circular nodes arranged in a triangle inside a ring. Two versions are needed:
1. A flat/vector version that can be tinted programmatically to match the app's current primary theme color (default cyan, but must follow whatever primary/accent color the user selects in the existing theme Color setting). Use this version for in-toolbar and in-navigation icon usage.
2. A glossy 3D-rendered version (static image asset) for the splash screen and any About/branding screen. This version can default to cyan regardless of the user's chosen theme color, since it's a static asset.
I will provide the actual image assets separately; for this task, set up the code structure to use these two logo variants in the appropriate places (tintable vector in the app bar/toolbar, static 3D render on the splash screen), using placeholder assets if needed until the real files are supplied.

GLASSMORPHISM, ANIMATION, AND STACKED-CARD STYLING (apply on top of the existing theme, do not replace it):
1. Apply a subtle glass treatment to existing cards across the app: slight translucency, a thin luminous border using the existing primary/secondary theme colors, a soft glow, and rounded "bubble" edges (increase corner radius on cards and buttons for a softer, more rounded look consistent with a "liquid glass" feel). Do not make cards fully transparent or hard to read; keep text contrast strong.
2. Add subtle micro-animations: a pulsing effect on connection/status indicator dots, an animated scanning line on the QR scanner screen, a small scale-down/scale-up press animation on primary buttons, and a smooth animated transfer progress bar.
3. Add a splash screen animation on app launch: the logo (3D version) appears, its three nodes illuminate in sequence, the "OmniDrop" wordmark fades in, then transitions to the home screen. Keep this under approximately 1.5 seconds total, and make sure it does not delay real app startup/initialization, it should play while the app is loading, not block it.
4. Apply the stacked-card layout philosophy already partially present in the app consistently across screens: cards with consistent spacing, subtle elevation, and the glass/border treatment described above.

TRANSFER SCREEN CORRECTIONS:
1. Move the top-bar 3-dot options icon to the far left end of the bar, before the OmniDrop logo/wordmark (currently it sits to the right of the logo).
2. Remove the "Selection" header text above the file-type category row entirely.
3. Move the horizontal file-type category row (File, Media, Paste, Text, Folder, App) up so it sits directly beneath the top bar.
4. Remove the "Nearby devices" section from the main Transfer screen body. Instead, add it as a small collapsible dropdown inside the Receive button's pop-up card (see below).
5. Clarify and fix the Send/Receive button behavior:
   - The Send button should open a pop-up card showing a QR CODE that other devices can scan to connect to this device and receive the staged files.
   - The Receive button should open a pop-up card with a QR CODE SCANNER (using the device camera) that lets this device scan another device's QR code to connect and receive files from them. The "Nearby devices" list (as a small dropdown) belongs inside this Receive pop-up, not on the main screen.
6. With the "Selection" header removed and Nearby Devices relocated, the remaining screen space below the file-category row should be left clear for the in-app file browser (still a placeholder for now, per the exclusion above).

WEBDROP SCREEN CORRECTIONS:
1. Redesign the WebDrop pop-up shown after tapping "Start WebDrop" to include: an active/online status indicator, the QR code, the local URL displayed as text with copy and open buttons, a "Pairing PIN Protection" toggle, and a "Connected Browser Clients" count/list section.
2. WebDrop must NOT be receive-only. Users must be able to add files to the Staged Files card and send them out through WebDrop to a connected browser, in addition to receiving files from a browser. Verify and fix the underlying flow so sending actually works end to end, not just the staged-files display.
3. "Start WebDrop" must remain clickable and functional even when zero files are staged (for pure receive-from-browser use).
4. Redesign the Staged Files card to include: a numbered badge (e.g. "01"), a title ("Staged Files (N)"), a subtitle, an empty-state message when there are no files, an "+ Add Files" button, and a "Clear staged files" BUTTON (not a text link — style it as an actual button, visually secondary/less prominent than "+ Add Files" but still a proper tappable button).
5. The Staged Files card should be the only card visible before WebDrop is started; once started, it appears below the WebDrop status card described in point 1.

OS PAIRS SCREEN REDESIGN:
Rebuild this screen to match this structure:
1. A header card acting as a "Cross-Platform Pairing Hub," showing a short description and a badge with the total number of supported OS pairs.
2. Each OS pair (Android, iOS, macOS, Windows, Linux combinations) shown as its own expandable/collapsible card containing: a numbered badge, icons for both platforms in the pair with a connector symbol between them, a title (e.g. "iOS ↔ Android"), a short description, a speed badge and an encryption badge, a "HOW TO PAIR & TRANSFER" numbered step-by-step walkthrough specific to that OS pair (using the app's actual transfer/WebDrop methods, do not invent unsupported steps), and a button to open the relevant QR/pairing screen for that pair.
3. Cards should be collapsible/expandable (tap to expand and see the full walkthrough, tap again to collapse), with the first one expanded by default.

GENERAL RULES:
- Reuse existing theme tokens, existing data layers, and existing components wherever possible.
- Keep changes scoped to the items listed above. Do not modify transfer/discovery/crypto logic beyond what's needed to fix WebDrop's send capability described above.
- After all changes, run whatever checks you can in this container (Flutter/Rust CLIs are expected to be unavailable, that's fine, do your best static review).
- Commit with a clear message like "feat: OmniDrop UI corrections round 2 (logo, glass styling, transfer/webdrop/os-pairs fixes)".
- Explicitly PUSH the commit to main and confirm the push succeeded with the new commit hash. Do not just report a local commit.

Report back: what was built, anything left as a placeholder (including noting that logo image assets are placeholders until I supply the real files), and confirmation the push completed.
