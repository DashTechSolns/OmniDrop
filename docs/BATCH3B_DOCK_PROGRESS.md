TASK: Batch 3B - floating transfer dock + Transfer Progress Page (Dart UI only). Do NOT edit Rust, Kotlin, generated files (frb_generated.*, lib/rust, *.g.dart), the pairing controller logic, or the file browser (Batch 4). Real data only: no fake progress, no fake files.

Run git pull first. BEFORE coding PRINT: the existing progress page and progress/transfer providers (send AND receive), how staged/selected files are held, the existing floating dock (if any), home_page.dart's Stack/overlay structure and where the Send/Receive pills and bottom nav live, and the theme tokens. Use only real APIs.

All text in app/lib/pages/pairing/pairing_strings.dart or a new transfer_strings.dart (no slang). Dark AND light themes using existing tokens (cyan/violet/emerald; red only for the third node). Must fit a 360dp-wide phone.

1. FLOATING TRANSFER DOCK
- Small circular glass dock, overlay above all pages including the bottom nav. It appears when files are staged for sending (or an incoming transfer is active). Default position: just above the Receive button, clinging to the right screen edge.
- Draggable anywhere vertically and horizontally, releases with a snap animation to the nearest LEFT or RIGHT screen edge, stays clear of the status bar and nav bar. Remember its position (use the app's existing settings storage only if trivial; otherwise keep in memory and say so).
- Shows the NUMBER of selected files. Tapping while idle does nothing harmful (opens the Send flow only if that already exists).
- While a transfer is active: the whole dock rotates slowly and 3 small nodes (cyan, violet, red) orbit it, each with a fading trail. Animations must stop completely when no transfer is active or when the dock is hidden.
- Tapping during a transfer opens the Transfer Progress Page. Multi-recipient: one dock, aggregated.
- Highlighting selected files in the browser stays with Batch 4; only expose a clean selected-files provider the browser can read, and report its name.

2. TRANSFER PROGRESS PAGE
- Opens from the dock and automatically when a transfer starts; BACK or an explicit "Minimize" button returns to the app and the transfer keeps running (the dock shows it). Cancel is a separate, confirmed button. The page must never trap the user.
- Top area: a digital-cyber circular gauge drawn with CustomPainter, inspired by dark HUD gauges: a ring of ~72 tick marks, completed ticks glow cyan (violet-tinted gradient allowed), remaining ticks dim, a thin outer arc, a large percentage in the centre, an elapsed timer under it (HH:MM:SS), and a small label for the active file. Subtle glow, no heavy blur.
- Stats grid under the gauge, live: percentage, transferred bytes, total bytes, speed, files remaining, estimated time, receiving device (name + avatar). Multi-recipient: a compact list with per-device progress and status.
- Below: the per-file list with done/active/queued states (reuse existing widgets where possible).
- PERFORMANCE: throttle UI updates to at most ~10 per second, wrap the gauge and orbit in RepaintBoundary, no work in build(), dispose every AnimationController, no rebuild of the whole page per tick.
- Completed state: gauge shows 100%, a clear "Done" message and a button to close; failed/cancelled states show the real reason. Integrity wording must stay truthful (never claim "verified" unless the receiver actually verified).

3. Remove leftovers: the old blocking progress screen route, if now unused. List what you removed.

VERIFY: whole-app fvm dart analyze (cd app && fvm dart analyze lib) with zero errors; run the tests you can; git diff --check; last 15 lines of app/lib/main.dart for stray characters. Add widget tests for the dock count and drag-snap, and a painter test for gauge tick math, with real assertions.
FINISH: commit "feat: floating transfer dock and cyber progress page", git push origin main. If push fails with an auth error, STOP and say so. Show git log -1 --stat and the hash.
