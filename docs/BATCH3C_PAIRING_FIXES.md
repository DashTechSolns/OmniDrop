TASK: Batch 3C - pairing fixes from device testing. Fix in the pairing controller + cards + dock only. Do NOT touch the file browser (Batch 4). If a root cause is in Rust or Kotlin, fix it minimally, never hand-edit generated files (frb_generated.*, lib/rust, *.g.dart), and list any changed #[frb] signature in your report (the FRB workflow must run before Dart can use it).

Run git pull first. BEFORE changing anything PRINT: PairingController (states/actions), pairing_cards.dart, receive dialog, the dock overlay and how it is mounted (main.dart, MaterialApp.builder, transfer_dock_overlay.dart), the Nearby/discovery and send-offer code, the join code, the home_page Send/Receive pills. Evidence only: cite file:line for every cause you claim.

A. CRASH: "Duplicate GlobalKeys detected... LabeledGlobalKey<_OverlayEntryWidgetState>". Find every OverlayEntry/Overlay mount. Make the dock a single instance (one widget in one Stack layer, or one OverlayEntry guarded by `entry.mounted` and removed in dispose). Never re-insert the same entry. Print the cause.

B. CARD SIZE/POSITION (Send and Receive cards): never taller than 2/3 of the screen height, vertically and horizontally centered (dialog-style glass card, not a full bottom sheet), max width ~92% of the screen. Content inside scrolls if needed; the QR scales to fit. Works on 360dp phones, light and dark.

C. PIN DOES NOT SAVE: the "Pairing pin protection" checkbox and the PIN do not stick. Persist the checkbox states (multi-recipients, pin protection, encrypted) in the app's existing settings storage so they survive closing the card and restarting. The PIN value itself lives only in controller state for the session (not stored on disk): when the user accepts the suggested PIN or types their own (exactly 6 digits), use THAT PIN in create_pairing_session_with_options, show it on the card, and keep it until the session ends. Prove with a test that edited PIN reaches the session options.

D. QR/PAIRING EXPIRY: 2 minutes for a PENDING pairing (QR + countdown + Rust session expiry). When it expires, the pending session stops and the UI says so. Expiry must never tear down an ALREADY PAIRED connection.

E. STOP BUTTON: add a "Stop" button on the Send card and the Receive card while pairing is pending. Sender: stops hotspot + session + service. Receiver: stops scanning/connecting/joining. Both return to idle with the card closed or reset.

F. AFTER PAIRING, BOTH PHONES: on successful pairing, the Send card AND the Receive card close and the user lands on the normal file browser (no file picker, no panel opens). Single-recipient: sender card closes by itself. Multi-recipient: Close only hides the card; the session keeps running. Closing a card must NEVER stop a paired session (the 20-second `dart_stop` in the log is probably this; find and fix).

G. CONNECTED STATE: create one provider/state "pairing connection" (connected peers, role, active transfer count) that the rest of the app can read. While connected: hide the Send and Receive pills and show a single "Disconnect" pill in their place (shows the peer name, or "N devices"). The connection stays alive after transfers end until Disconnect is tapped. Keep the foreground service alive while connected.
SEND TARGET PICKER: when files are selected and the user taps SEND(N) (or Send) while connected:
 - ONE connected peer: send directly to it, no picker.
 - TWO OR MORE connected peers: open a compact glass picker (same size and position rules as the cards: max 2/3 of screen height, centered, scrolls if needed) listing every connected device (avatar, name, connection status) with a checkbox each, plus an "All devices" row at the top.
   - "All devices" toggles every row on/off; unticking any single row unticks "All devices"; ticking every row ticks it.
   - The confirm button reads "Send to N device(s)" (or "Send to all") and is disabled until at least one is ticked.
   - Confirming starts one transfer per ticked device simultaneously through the existing transfer path, shown in the dock and the progress page.
   - Remember the last ticked set for the current connection only, and drop devices that disconnected meanwhile.
   - A peer that disconnects while the picker is open is removed from the list and cannot be selected.
 - Add widget tests for the All/individual toggle logic and for the single-peer direct path, if tests can run.
H. DISCONNECT: tap Disconnect. If no transfer is running: disconnect immediately. If a transfer is running: dialog "A transfer is still in progress" with buttons [Disconnect anyway] (cancels transfers, tears everything down) and [Cancel] (closes the dialog, transfers continue). Teardown must stop session, hotspot, network binding and the service on both roles, and restore the Send/Receive pills.

I. NEARBY AND WI-FI DIRECT DO NOT CONNECT: diagnose with evidence. Add step logging to the Pairing log (never passwords/tokens/PINs): discovery started, each device found (ip, port, protocol), send-offer request (url, status, error text), join request (status, error), PIN result. Check specifically: (1) is the sender's HTTP server actually running and reachable while in Wi-Fi Direct mode, (2) http vs https mismatch caused by the "Encrypted" checkbox or fingerprint pinning, (3) discovery on a hotspot subnet with the receiver bound to that network (multicast lock, HTTP subnet scan fallback), (4) receiver offers filtered out by an overly strict check, (5) PIN required but not asked. Fix every proven cause. If something cannot be proven by reading code, say so and list the logs that will prove it on the next test.

VERIFY: cd app && fvm dart analyze lib zero errors (repo-pinned Dart SDK if fvm is missing); git diff --check; last 15 lines of app/lib/main.dart; add tests for D, C and the single/multi/disconnect transitions that can run. If the test compiler crashes, say so and do not claim tests passed. If you changed Rust, cargo check and cargo test the pairing tests.
FINISH: commit "fix: pairing UX (card size, pin, expiry, stop, connected state, disconnect, nearby)", git push origin main. If push fails with an auth error, STOP and say so. Show git log -1 --stat, the hash, the root cause for A and I, and any changed FRB signatures.
