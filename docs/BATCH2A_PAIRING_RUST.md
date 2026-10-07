TASK: Batch 2A - pairing logic in RUST (plus tiny Dart-side test fix). Do NOT edit generated files (frb_generated.*, lib/rust, *.g.dart). Do NOT build UI.

Run git pull first. BEFORE changing anything, PRINT: the pairing session code in Rust (session manager, join route, send-offer route, events), the FRB-exposed pairing API signatures, and the current Dart callers. Use only real code.

1. PIN PROTECTION: a session can be created with an optional 6-digit PIN. When set, the join request must carry the PIN. Verify with a constant-time compare. After 5 wrong attempts lock the session (no more joins) and emit an event. Generate the suggested random PIN with a cryptographically secure RNG in Rust (expose a small function). Never log PINs, tokens or passwords.
2. SINGLE vs MULTI: session option multi_recipient. If false, after the FIRST successful join the session stops accepting new joins and emits a Paired event (the UI will use it to close the QR card); the session stays alive for the transfer. If true, joins stay open until the session is stopped.
3. ENCRYPTED FLAG: print how transfers are secured today (HTTPS/self-signed, fingerprint). Map the "Encrypted device-to-device transfer" option to the existing mechanism only. Do not invent crypto, and do not call anything verified or end-to-end unless it is. Report exactly what the flag guarantees in one short paragraph.
4. CHECKSUM SCREEN: find the blocking "Calculating checksum" step (Dart) that appears before sending. Print what the hash is used for. Make the transfer start immediately: hash in the background or only where the protocol truly needs it. Keep integrity verification honest: if it is skipped, nothing may claim "verified".
5. SEND WITH NO FILES: find any gating that stops pairing/Send when no file is staged and list it (the Dart change comes in Batch 2B).
6. TESTS: fix test/.../qr_payload_parser_test.dart (references removed PairQrPayload.sessionId). Add Rust tests for: PIN accept/reject/lockout, single-vs-multi join behaviour, constant-time compare helper.

BINDINGS RULE: if you change any #[frb] function signature, type or event, you cannot regenerate the bindings here. Do NOT hand-write generated code. Make the Rust change compile (cargo check -p rust_lib_localsend_app and cargo test for the pairing tests), and list EVERY changed FRB signature in your final report, because the Regenerate FRB bindings workflow must run before any Dart can call them.

VERIFY: cargo check; cargo test (pairing tests); git diff --check; last 15 lines of app/lib/main.dart for stray characters.
FINISH: commit "feat: pairing PIN, single/multi sessions, encryption flag, no blocking checksum", git push origin main. If push fails with an auth error, STOP and say so. Show git log -1 --stat, the hash, and the list of changed FRB signatures.
