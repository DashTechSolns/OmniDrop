TASK: Batch 2B - Dart STATE/LOGIC layer for pairing. NO visual redesign yet (cards, animations, dock come in Batch 3). Do NOT edit Rust or generated files (frb_generated.*, lib/rust, *.g.dart).

Run git pull first. BEFORE changing anything, PRINT: the regenerated Dart bindings for generate_pairing_pin, create_pairing_session_with_options, listen_pairing_control_events, join_pairing_with_pin (confirm they exist; if any is missing STOP and report); the Kotlin platform-channel API in android_channel.dart (connect, disconnect, enable wifi, 5GHz, pairing log, foreground service); pairing_page.dart; the app's state-management pattern (refena or similar) and how send_provider/send_tab_vm gate on staged files.

1. PairingController (one provider, no UI inside) that owns the full lifecycle for both roles and exposes plain states:
   SENDER: idle -> startingHotspot -> sessionReady(qrPayload, pin?, multi, expiry) -> peerJoined(list) -> closedForSelection (single-recipient, on the Paired control event) -> transferring -> stopped. Options: multiRecipient, pinEnabled (use generate_pairing_pin for the suggestion; user-edited PIN allowed, must be exactly 6 digits), encrypted (maps to existing https setting only), mode = qr | sameNetwork. Use create_pairing_session_with_options. Stop must tear down session AND hotspot/service, only on explicit stop/Disconnect/expiry, never on widget dispose or lifecycle events.
   RECEIVER: idle -> enablingWifi -> scanning -> connecting -> joining -> joined | failed(reason). After a QR scan: native auto-connect, then join_pairing_with_pin (ask for a PIN state when the offer says pin required), explicit failure reasons, retry, and manual-guide fallback state (SSID shown, password copy only).
   Consume listen_pairing_control_events (paired, lockedOut, finalized) and map them to states.
2. NO-FILES GATES: remove the "send files first" gates in pairing_page.dart, home_page.dart and send_tab_vm.dart ONLY for starting/hosting pairing. Normal send of staged files must still require files. After pairing with nothing staged, the state is peerJoined and files are chosen afterwards. Print each gate and what you changed.
3. SAME-NETWORK mode: reuse existing LocalSend discovery. Sender advertises the open session (existing send-offer route); receiver lists offers. Expose both as controller states. No hotspot in this mode.
4. WIFI: on Receive entry call the native enable-Wi-Fi method; handle both result paths.
5. DIAGNOSTICS: a "Pairing log" screen (Settings -> Advanced) that merges the native log buffer and a Dart-side step log with timestamps and a Copy button. Never log passwords, tokens or PINs.
6. 5G: expose a boolean canUse5GMode (= native canRequest5GHz). It is currently false, so nothing 5G is shown or enabled. No fake behaviour.
7. Unit tests for the controller state transitions (single vs multi, pin invalid, failure + retry, teardown only on explicit stop). Real assertions only.

VERIFY: fvm dart analyze on the WHOLE app (cd app && fvm dart analyze lib) with zero errors; run the tests you can; git diff --check; last 15 lines of app/lib/main.dart for stray characters.
FINISH: commit "feat: pairing controller (qr + same-network), pin, diagnostics", git push origin main. If push fails with an auth error, STOP and say so. Show git log -1 --stat and the hash.
