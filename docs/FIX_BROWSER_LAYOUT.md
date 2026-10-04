This is OmniDrop. This task is UI/Dart only - no native Kotlin/storage changes, no networking changes. Reference existing theme tokens in lib/config/theme.dart.

1. FILE BROWSER CARD - MINIMAL GLASS TREATMENT:
The file browser area (shown below the category tabs on the Transfer screen) currently uses the same padded glass-card treatment as other cards throughout the app. Change it to a minimal glass treatment specifically for this screen: keep a thin luminous border (consistent with the app's existing glass border styling) and a subtle blur/translucency, but significantly reduce internal padding so the browser's content effectively fills the available screen space edge-to-edge, giving it a spacious, native-file-manager feel. Do not remove the glass border/blur entirely - the goal is minimal chrome, not zero brand identity. Every other screen in the app keeps its existing full glass-card treatment unchanged; this change applies only to the file browser area.

2. APPS GRID - FORCE CONSISTENT ALIGNMENT:
The Apps grid currently renders with inconsistent spacing and does not reliably show a fixed column count - it has shown anywhere from 3 columns with large gaps to other inconsistent layouts depending on content. Fix this so the grid use a FIXED 4-column layout (not adaptive/flexible column count), with consistent, tight spacing between items (small fixed gap, not large auto-calculated gaps), and rows flowing naturally based on how many items exist (5-6+ rows as needed, scrollable). Use a GridView.builder with a SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, ...) or the equivalent fixed-column approach, not a delegate that calculates column count based on available width, to guarantee the column count never varies by screen size or content. Verify this renders as an actual straight, evenly-spaced row-and-column grid, not loosely scattered items.

GENERAL RULES:
- Reuse existing theme tokens and widgets wherever possible.
- Do not touch transfer/discovery/crypto logic, native Kotlin code, or the folder-browsing logic (being fixed separately).
- After changes, do a full static review for balanced brackets and correct imports.
- Commit with a message like "fix: minimal glass file browser + fixed 4-column grid alignment".
- Push to main. Run `git fetch && git log origin/main -1 --oneline` and paste the output.

Report back what was built and confirmation of the push with command output.
