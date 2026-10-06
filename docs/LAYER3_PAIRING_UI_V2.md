TASK: Build the pairing feature (Rust small addition + Dart UI). Layers 1 (Kotlin hotspot bridge) and 2 (Rust pairing session, join route, FRB bindings) exist and compile.

RULES
- Run git pull first.
- No slang/translations: put all new text as const English strings in app/lib/pages/pairing/pairing_strings.dart.
- No build_runner / dart_mappable models. Plain Dart classes.
- No fake success, no fake devices. Every state reflects real results.
- You may edit Rust ONLY in the pairing/server area and ONLY as described below. Regenerate FRB bindings with the real codegen after Rust changes (cargo check and codegen worked last time). Never hand-edit generated files.
- FIRST PRINT the real APIs you will use: Dart pairing bindings, listen_pairing_session and events, the Layer 1 hotspot channel (methods, returns, permissions), the current Send and Receive pages and their navigation, existing nearby/discovery code, how the Me profile stores device name and avatar, the transfer start call, and how mobile_scanner/QR packages are already used.

SENDER (Send page): two tabs, "QR" (DEFAULT, opens first) and "Wi-Fi Direct". Existing normal LAN send must stay reachable.

METHOD 1 - QR (hotspot):
- Opening the QR tab auto-starts the hotspot (Layer 1) then a pairing session (Layer 2), and shows a QR containing SSID, password, host IP, port, session token, device fingerprint, expiry. Live 5-minute countdown, Stop button.
- Receiver: Receive page gets "QR Scanner" (mobile_scanner). On valid QR: auto-connect to hotspot where possible (Android 10+ via existing/Layer 1 method); otherwise show SSID+password with Copy and an "I'm connected" button. Then call join. States: scanning, connecting, joining, joined, failed (real error + Retry). Reject expired/invalid QR. Handle camera permission denied.

METHOD 2 - WI-FI DIRECT (same-network discovery, all OS):
- Sender "Wi-Fi Direct" tab: Start button opens an "open" pairing session WITHOUT hotspot and shows my device name + avatar with a "Visible to nearby devices" state, countdown, Stop.
- Rust (small): make the open session discoverable. Do NOT change the LocalSend multicast protocol. Add a lightweight HTTP route, e.g. GET /api/omnidrop/v1/send-offer, returning {alias, avatar info, session id, join token, expiry} ONLY while an open session is active (404 otherwise). Reuse the existing join route and session manager. Keep it backward compatible with plain LocalSend.
- Receiver: Receive page gets "Nearby". Use the existing discovery to find devices, query send-offer on each in parallel (short timeout), and list only devices with an active offer, showing name + avatar. Tap one -> join -> "joined". If avatar cannot be transmitted, show a generated initials avatar and tell me.
- Make sure none of this uses Android-only APIs, so iOS/desktop can use Nearby and the scanner.

BOTH METHODS
- Sender lists joined devices live (name, avatar/icon, status) with a Remove option. Stop/close/background tears down session AND hotspot.
- Multi-recipient: "Send to all" / selected devices starts one transfer per device SIMULTANEOUSLY through the existing transfer path, shown in the floating transfer dock.
- No 5GHz toggle. Light/dark themes with existing cyan/violet/emerald tokens and glassmorphism. Small phone screens.

VERIFY (all must pass before commit)
- cargo check for the Rust crate; fvm dart analyze on every touched Dart file; git diff --check.
- Check the last 15 lines of app/lib/main.dart for stray characters.
- Print git diff --stat.

FINISH
Commit "feat: pairing UI (QR + Wi-Fi Direct) and send-offer route", git push origin main. If push fails with an auth error, STOP and say so. Show git log -1 --stat and the hash.
