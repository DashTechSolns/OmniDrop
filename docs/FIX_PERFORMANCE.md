This is OmniDrop. The app feels heavy/slow, especially on: the opening splash animation, the Apps page, the Settings drawer, and the Downloads page. This task investigates and fixes the actual cause on each, rather than guessing. UI/Dart work only - no networking changes, no changes to the transfer engine or Rust layer.

For each of the four areas below, first investigate and state what you actually found, then fix it:

1. OPENING SPLASH ANIMATION:
Find the splash/launch animation code (added in an earlier batch - the 3D logo with sequential node illumination and wordmark fade-in). Confirm how long it currently runs and whether it blocks or delays the app's actual initialization (it should play WHILE the app loads, never gate or add time on top of real startup). Per the original request, this animation should be removed or cut down to be effectively instant - shorten it significantly (under ~500ms, or remove the sequential/staged timing entirely and just show the logo briefly) so it does not read as a delay before the app becomes usable.

2. APPS PAGE:
Investigate what's actually happening when the Apps grid loads - is it querying installed packages and loading each app icon synchronously/on the main thread? Is it re-querying the full app list and re-decoding icons on every widget rebuild instead of caching results? Print the actual relevant code. Fix so package querying happens off the main thread (via an isolate or async method appropriately), app icons are decoded once and cached (in memory for the session, not re-fetched on every rebuild), and the grid uses proper lazy/builder-based rendering so only visible items are processed.

3. SETTINGS DRAWER:
Investigate what happens when the right-side Settings drawer opens - is anything expensive (disk reads, provider rebuilds, synchronous calls) happening every time it opens rather than being cached/loaded once? Print the actual relevant code. Fix any unnecessary repeated work so opening the drawer is immediate.

4. DOWNLOADS PAGE:
Investigate the Downloads category's MediaStore query and thumbnail loading (built in an earlier storage batch). Confirm thumbnails are genuinely being decoded at thumbnail size (not full resolution) and are cached rather than re-decoded on every scroll/rebuild. Check whether the MediaStore query itself is paginated/lazy or loading the entire result set at once for potentially large download folders. Print the actual relevant code and fix whichever of these is the real cause.

5. GENERAL SWEEP:
While in these files, do a brief check for other common Flutter performance mistakes that may be contributing: missing `const` constructors on static widgets, expensive work inside `build()` methods that should be cached/memoized instead, and any other synchronous file/disk I/O happening on the main thread during widget builds. Fix any clear instances found in the four areas above; do not do a sweeping refactor of unrelated screens.

GENERAL RULES:
- Do not change what these features do, only how efficiently they do it. No visible behavior should change except that things load/respond faster.
- Do not touch transfer/discovery/crypto logic, native Kotlin storage code beyond what's needed for the Downloads/Apps fixes above, or anything unrelated to these four areas.
- After changes, do a full static review of every touched file for balanced brackets and correct imports/types.
- Commit with a message like "perf: fix splash animation delay, Apps/Downloads loading, Settings drawer overhead".
- Push to main. Run `git fetch && git log origin/main -1 --oneline` and paste the output.

Report back: what you actually found as the cause in each of the four areas (not assumed, what you found in the real code), what you fixed, and confirmation of the push with command output.
