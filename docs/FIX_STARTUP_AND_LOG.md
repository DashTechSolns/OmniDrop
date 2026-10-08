TASK: Fix (1) app stuck on a white screen at launch since the dock build, (2) Pairing log page error. Dart only. Do NOT edit Rust, Kotlin, or generated files (frb_generated.*, lib/rust, *.g.dart).

Run git pull first.

A. CRASH-PROOF BOOTSTRAP (do this first, it makes any future crash visible)
- In main (and the init code it calls): wrap everything in runZonedGuarded; set FlutterError.onError and PlatformDispatcher.instance.onError.
- If anything throws BEFORE runApp, call runApp with a minimal, self-contained CrashScreen (plain MaterialApp, no Refena or providers) showing the exception text, the stack trace, and a Copy button.
- Errors after runApp: write the last crash (time, error, stack) to a text file in the app support directory, and show it at the top of the Pairing log screen.
- Never include passwords, tokens or PINs.

B. FIND THE WHITE-SCREEN CAUSE (evidence only, no guessing)
- PRINT git diff --stat between d99ec4a8 and HEAD, then the full diff of every file on the startup path: main.dart, init code, the root app widget, home_page.dart, and every provider that is created or read at launch.
- Check and report file:line for each: (1) Refena/context read before the widget is ready (initState/constructor), (2) Overlay or OverlayEntry used before MaterialApp exists, (3) MediaQuery/Theme/Directionality used above MaterialApp, (4) a startup await with no timeout (platform channels, storage, native calls), (5) provider cycles or providers that throw on first read, (6) AnimationControllers created without a TickerProvider or not disposed.
- Fix the real cause. Then make the dock fail safe: mount it only after the first frame (addPostFrameCallback or inside the MaterialApp builder), wrap its init in try/catch so a dock failure logs the error and the app still opens without the dock. Add a timeout to any startup await you find.
- If you cannot prove a single cause by reading the code, say so, apply every defensive fix above, and list what you changed.

C. PAIRING LOG PAGE
- Error: dependOnInheritedWidgetOfExactType<RefenaInheritedWidget>() called before _PairingLogPageState.initState() completed.
- Fix with ensureRef or didChangeDependencies or a post-frame callback.
- Then grep the WHOLE app for the same mistake (context.ref / context.read / context.watch / Theme.of / MediaQuery.of used in initState, constructors, or late fields initialised there) and fix every instance. List them.

VERIFY: whole-app fvm dart analyze (cd app && fvm dart analyze lib) with zero errors; git diff --check; last 15 lines of app/lib/main.dart for stray characters. Do not claim tests passed if they cannot run.
FINISH: commit "fix: crash-proof startup, safe dock mount, pairing log init", git push origin main. If push fails with an auth error, STOP and say so. Show git log -1 --stat and the hash, and your conclusion for B.
