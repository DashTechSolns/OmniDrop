# OMNIDROP PHASE 3: Transfer fix + In-app file browser + Cyber Liquid Glass

You are working on OmniDrop (Flutter, forked from LocalSend, Android is the target).
Read this whole file before editing. Do the work in the order given. The Android build is verified only by GitHub Actions, so compile-safety matters more than speed.

## 0. RULES

DO NOT TOUCH: package ID, app name, signing config in build.gradle, encryption/HTTPS logic, or the existing file-transfer protocol (prepare-upload/upload). The ONE allowed networking addition is the small "join" endpoint in section 2.

NO FAKE UI. No placeholder buttons, no mock states, no fake connection states. If a feature cannot work yet, leave it out of the UI and list it in your report.

COLORS: use lib/config/theme.dart tokens only. Dark palette: bg #05080D / #090D16, cyan #00D9FF / #06B6D4, violet #8B5CF6, green #10B981. Do not add a new palette.

COMPILE SAFETY (past builds failed on these, so check them):
- Anything that is `await`ed must return `Future`, never `void`.
- No `if (...) await ...;` inside an expression, arrow body, or ternary.
- `unawaited` needs `import 'dart:async';`.
- A `switch` must use one syntax (statement or expression) throughout.
- Balanced brackets in every edited file. Re-read every edited file fully at the end.
- Any new package in pubspec.yaml must be compatible with the repo's Flutter/Dart SDK constraints and Android minSdk 26. Prefer well-maintained packages. If none fits, write a small Kotlin MethodChannel instead.
- Flutter is not installed in the Codespace, so do a manual static review of every changed file before committing.

PERFORMANCE: the test phone is an old Android 8 device. Use `BackdropFilter` blur on at most 3 widgets per screen (app bar, bottom nav, one hero card). Inside scrolling lists use translucent gradient fills with no blur.

## 1. LAYOUT FIXES (Transfer screen)

Target layout:

```
┌────────────────────────────────────────┐
│ ⋮  (logo) OmniDrop        ≡   ⚙       │  top bar
├────────────────────────────────────────┤
│ Downloads Apps Images Videos Audio ... │  scrollable category pills
├────────────────────────────────────────┤
│ ┌────────────────────────────────────┐ │
│ │  IN-APP FILE BROWSER (inset card)  │ │  fills the space
│ │  grid / list of the chosen type    │ │
│ └────────────────────────────────────┘ │
│  [ 3 selected · 24 MB   Clear ]        │  selection bar (only if >0)
│                                        │
│     [ ▶ Send ]     [ ⬇ Receive ]       │  BOTH floating, side by side,
├────────────────────────────────────────┤  just above the bottom nav
│  WebDrop  OS Pairs  (◉)  Cloud   Me    │  floating glass bottom nav
└────────────────────────────────────────┘
```

1. Move the **Send** button down. Send and Receive sit side by side, centered, floating just above the bottom nav (same row, equal size, Send = primary gradient button, Receive = secondary glass button). Nothing Send-related stays at the top.
2. **Top bar swap**:
   - LEFT 3-dot icon (before the logo) opens the LEFT SIDE DRAWER (Theme, Color, Language, Animations, Enable 5G preference, Rating, About).
   - RIGHT "≡" icon (next to the gear) opens a dropdown with: **Scan Connect**, **Share OmniDrop**, **Copy Phone**.
   - Gear opens Settings.
3. **Share OmniDrop** must work: use the system share sheet (add `share_plus` if not already present) to share the installed app's own APK file, so a friend can install it offline. Fall back to sharing a text invite if the APK file cannot be read.
4. **Copy Phone** (see section 3, step 7): it is built on the file browser, so it is wired up there. Do not leave a "coming soon" screen.
5. Remove the old Send|Receive tabs, the "Selection" header, and the Nearby devices section from the main body, if any remain.

## 2. SEND / RECEIVE (real behavior)

Flow diagram:

```
 SENDER (shows QR)                         RECEIVER (scans QR)
 ───────────────────                       ───────────────────
 1. Stage files in browser
 2. Tap [Send]
 3. Pop-up card:
    - QR code  ───────────────────────►   4. Tap [Receive] -> camera scanner
    - Multi-receiver toggle                5. Scan OmniDrop QR
    - Connected receivers list             6. App POSTs /api/omnidrop/v1/join
 7. Sender gets "join" request  ◄────────      (alias, ip, port, https, fingerprint, sessionId)
 8. Sender validates sessionId
 9. Sender pushes staged files with the
    EXISTING send flow (prepare-upload) ──►  10. Normal receive + progress
11. Toggle OFF: QR closes after first
    receiver. Toggle ON: QR stays, each
    new scan gets the same files.
```

**QR payload** (Send pop-up): `omnidrop://pair?alias=..&ip=..&port=..&https=..&fp=..&sid=..` where `sid` is a random one-time session id created when the pop-up opens and discarded when it closes.

**Send pop-up (glass modal card, 32dp radius):** QR code, device alias + IP, a **"Multiple receivers"** toggle (this toggle lives HERE, not under Receive), a live list of receivers that have joined with per-receiver progress, and a Close button.

**Receive pop-up:** camera scanner with an animated scan line. Contains a small collapsible **"Nearby devices"** dropdown (the existing LAN discovery list) as a fallback. Selecting a nearby device only makes sense when that device has its Send pop-up open, so show a hint line explaining this.

**QR routing (one shared parser, used by Receive and by "Scan Connect"):**
- `omnidrop://pair...` -> join flow above.
- `http(s)://...` (a WebDrop link) -> only from the top-bar **Scan Connect**: show a confirm dialog "Open this link in browser?" and then open it. The **Receive** button must never open the browser.
- Anything else -> "Not an OmniDrop code" message.

**Networking addition (the only one allowed):** one small endpoint `POST /api/omnidrop/v1/join` on the existing server, reusing its existing auth, TLS, and device-info types. It is active only while a Send pop-up session is open. After it validates `sid`, it triggers the existing "send files to this device" function. Reuse as much of the existing send code as possible.

## 3. IN-APP FILE BROWSER

The category bar is horizontally scrollable, always fully functional, and in this order:

`Downloads · Apps · Images · Videos · Audio · Documents · Text · Files`

All of them feed the SAME selection state the old File/Media/Folder/App pickers used (find that provider and reuse it, so Send keeps working unchanged).

Steps:

1. **Images / Videos / Audio**: query the device media library (e.g. `photo_manager` for images and videos, a maintained audio query package or MediaStore channel for audio). Show a thumbnail grid (images, videos) or a list (audio) with a checkbox overlay. Support multi-select, long-press to start selecting, and a "select all" action.
2. **Documents**: list pdf, doc/docx, xls/xlsx, ppt/pptx, txt, csv, epub, zip, using a MediaStore Files query by mime type. Show a list with a type icon, name, size, and date.
3. **Downloads**: list the device Download folder contents (MediaStore Downloads where available), newest first.
4. **Apps**: list installed user apps with icons and names (use a maintained package such as `installed_apps`, or a small Kotlin channel using PackageManager). Selecting an app stages its APK file.
5. **Text**: the existing text composer (the old Text/Paste function), shown inline in the card.
6. **Files = mini file manager**: use a ONE-TIME folder-grant (Storage Access Framework tree permission). First tap shows a short explainer card and a "Grant access" button. After the grant, persist the URI permission and let the user browse folders (breadcrumb path, folders first, back navigation, multi-select files and folders). Do NOT use MANAGE_EXTERNAL_STORAGE. If the user denies, show the explainer again, not an error.
7. **Copy Phone** (top-bar dropdown): a real screen listing categories (Images, Videos, Audio, Documents, Downloads) with item counts and sizes and checkboxes. "Start" stages everything selected into the normal selection state and opens the Send pop-up. Do not include Apps or system data.

Permissions: declare only what is needed. Use `READ_MEDIA_IMAGES/VIDEO/AUDIO` on Android 13+ and `READ_EXTERNAL_STORAGE` (maxSdk 32) for older versions. Request them lazily, when a category is first opened, with a friendly glass explainer card.

Selection bar: when 1 or more items are selected, show a glass bar above the Send/Receive row: "N selected · total size" with a Clear button.

Empty state: if a category is empty or permission is missing, show an icon and a one-line message with the right action button.

## 4. CYBER LIQUID GLASS DESIGN SYSTEM

Build these ONCE as reusable widgets in `lib/widgets/glass/`, then use them on every screen (Transfer, WebDrop, OS Pairs, Me, Settings, drawer, dialogs, modals). No screen should keep a flat default card.

**GlassCard (standard):** fill rgba(15,28,40,0.78), 1dp border rgba(0,217,255,0.18), radius 22–26dp, blur 18–28px (only where allowed by the performance rule), shadow 0 8 30 rgba(0,0,0,0.35). Margin 16dp horizontal, 12–16dp vertical spacing, 18–20dp internal padding. Add a subtle diagonal gradient: top-left cyan at about 6–8% alpha, bottom-right blue/violet at about 6–8% alpha. The effect is "light passing through glass", never a neon sign.

**ElevatedGlass:** fill rgba(18,32,45,0.88), border rgba(0,217,255,0.25), radius 24dp. Use for modals, pop-ups, selection bar.

**SecurityGlass:** fill rgba(0,55,48,0.55), border rgba(0,229,154,0.30). Use for encryption/security info.

**Corner radius system:** 8 small elements · 12 buttons · 16 inputs · 20 small cards · 24 major cards · 28 hero cards · 32 modals/large containers · 999 pills. Define these as constants.

**Buttons:**
- Primary: cyan->blue gradient, white text, 14–16dp radius, 48–52dp height, press-scale animation.
- Secondary: transparent glass with a thin cyan border.
- Tertiary: text only ("View Details →").
- Destructive: transparent red glass ("Cancel Transfer").

**Bottom nav:** floating, keep the current height, 12dp side margin, 10–14dp from the bottom, 30dp radius, glass fill. The center OmniDrop button stays raised.

**App bar:** glass, with palette-derived gradient. Logo slightly luminous: cyan core, blue secondary glow, dark translucent outer ring. The logo vector follows the user's chosen primary color.

**Background:** the page background is #05080D with two very soft radial glows (cyan top-left, violet bottom-right at about 10% alpha) so the glass has something to refract. No pure black everywhere.

**Light mode: OmniDrop Light Glass.** A SEPARATE theme, not an inversion. Frosted white fills rgba(255,255,255,0.72), border rgba(0,150,190,0.25), soft cool-gray shadow, dark navy text (#0B1B2B), same radii and button system, background a pale blue-white gradient. Verify text contrast in both modes. Dark Cyber Liquid Glass is the default and flagship.

**Animations (short, subtle):** pulsing status dots, scan line on the scanner, button press-scale, animated progress bars, card fade/slide on entry.

**Never:** flat white cards, fully opaque gray cards, excessive neon, huge shadows, sharp rectangles, tiny unreadable text, overcrowded screens, decorative components with no purpose.

## 5. SETTINGS (restructure into 4 glass sections)

Place EXISTING settings into these sections. Only show an entry if it maps to a real setting or a real working action. List anything skipped in your report.

```
GENERAL      Notifications (opens Android app notification settings)
             Storage (save location setting)
             Permissions (opens Android app permission settings)
             Sound/Vibration (only if an existing setting exists)
CONNECTION   Wi-Fi (opens Android Wi-Fi settings)
             Device Discovery (existing port / multicast / network filter / alias settings)
             WebDrop (existing web share settings: PIN, encryption, port)
SECURITY     Encryption (existing HTTPS toggle)
             Trusted Devices (the existing Favorites list)
             (Safety Numbers and Bluetooth: OMIT for now)
ABOUT        OmniDrop, Version (read from package info), Open Source
             (licenses page and the Apache 2.0 attribution to LocalSend)
```

Remove the old "General" wrapper card and the Auto Finish toggle. Keep checksum verification running silently, with no toggle.

## 6. OFFLINE STATE

When no local network connection exists, Send/Receive show a glass card:
"You're offline. OmniDrop requires a local network connection for device discovery."
Button: **Open Wi-Fi Settings** (system intent). Below it, a short 3-step walkthrough: 1) Turn on Wi-Fi or connect to the other device's hotspot. 2) Return to OmniDrop. 3) Tap Send or Receive. Detect state with a connectivity check and update live.

## 7. SPLASH + LOGO

Background #05080D with a soft cyan/blue atmospheric glow. Sequence, under about 1.5 seconds total, running while the app initializes (never blocking startup):

```
logo appears -> three nodes light up in sequence -> "OmniDrop" fades in
-> tagline "Wireless. Private. Instant." -> "● Initializing..." -> Home
```

Use the existing logo assets in the repo (tintable vector for bars, 3D render for the splash and About). Do not generate new image files.

## 8. REAL-TIME TRANSFER PROGRESS

On the existing progress screen/card (GlassCard) show: percentage, transferred bytes, total bytes, current speed, files remaining, estimated time left, and the other device's name. Compute these from the existing progress data. Do not fake values.

## 9. WEBDROP + OS PAIRS + ME

Apply the glass system and corner radius system to these screens. Keep the functionality already built there. Do not redesign flows beyond styling. Standard cards, pills, and buttons must match section 4.

## 10. FINISH

1. Static review pass over EVERY changed Dart and Kotlin file (brackets, imports, Future types, switch syntax, null-safety, unused imports).
2. Update stale tests that expect the "LocalSend" name where trivial.
3. Commit: "feat: OmniDrop phase 3 (send/receive fix, in-app file browser, glass system, settings, splash)".
4. Push to main. Then run `git fetch && git log origin/main -1 --oneline` and `git diff --stat HEAD~1` and paste both outputs.

REPORT (paste real output, not summaries): files changed, what was skipped and why, any package added with its version, and the pushed commit hash.
