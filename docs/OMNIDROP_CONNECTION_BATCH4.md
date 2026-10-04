This is OmniDrop, built on LocalSend's existing architecture. This task implements real QR pairing with simultaneous multi-recipient support, and refines the Wi-Fi Direct tab (already partially improved in a prior commit, b77ca813). This is genuinely difficult native networking work spanning three layers: Kotlin (hotspot control), Rust/FRB (pairing session protocol + existing local server), and Dart (orchestration + UI). Do not fake, mock, or skip any layer - if a layer's work is incomplete, say so explicitly in your report rather than fabricating behavior, exactly as the previous attempt correctly did. This time, however, the architecture is specified explicitly below rather than left for you to design, which should make full implementation achievable.

STEP 0 - INVESTIGATE FIRST:
Before writing any code, investigate and report on:
1. The existing local HTTP server used for WebDrop (find it in the Rust/packages layer) - what routes does it currently expose, what web framework/router does it use, and how are new routes typically added in this codebase's existing pattern?
2. The existing transfer engine - when a transfer session starts, does it currently support sending the same file set to multiple simultaneously-connected receivers (fan-out), or is it built assuming one sender-to-one receiver per session? This matters a lot for the simultaneous multi-recipient requirement below - state clearly what you find.
3. The existing qr_payload_parser.dart format - what fields does it currently encode/decode, and can it be extended with hotspot SSID/password/session-token fields without breaking existing QR flows (like WebDrop's QR)?
4. The existing MainActivity.kt MethodChannel pattern - confirm the channel name and how Dart currently calls into Kotlin and receives results back, so the new hotspot bridge follows the same pattern.

Print your findings for all four before proceeding to implementation.

LAYER 1 - KOTLIN (hotspot bridge):
Add a focused native module (in MainActivity.kt or a new dedicated Kotlin file if cleaner, following this codebase's existing file organization) that:
1. Starts a local-only hotspot via WifiManager.startLocalOnlyHotspot(), returning the generated SSID and passphrase to Dart via the existing MethodChannel.
2. On Android 11+ (API 30+), accept a "prefer5GHz" parameter and attempt to configure the hotspot's SoftApConfiguration to prefer the 5GHz band if the device hardware supports it (check WifiManager.is5GHzBandSupported() first). On Android versions below 11, ignore this parameter and let the system choose the band automatically - do not attempt band control on older versions, it is not supported by the OS.
3. Reports failure back to Dart with a clear reason if the hotspot fails to start (e.g. certain radios already active, hardware doesn't support it).
4. Provides a stop/cleanup method callable from Dart to tear down the hotspot when the pairing pop-up closes or the session ends.

LAYER 2 - RUST/FRB (pairing session protocol):
Based on what Step 0 finds about the existing server and transfer engine:
1. Add a new route to the existing local server (do not create a second server) at a path like /api/omnidrop/v1/join that accepts a session token and device identity from a joining device.
2. Implement an in-memory pairing session state: when the QR pop-up opens, generate a short-lived random session token (expires after a reasonable timeout, e.g. 5 minutes, if never used). Store it alongside the sender's device info.
3. When a receiving device calls the join endpoint with a valid matching token, mark that device as paired/joined for this session. Since multi-recipient is SIMULTANEOUS (not sequential), the session must support multiple devices joining the same token/session, each tracked independently, not just the first one accepted.
4. Expose this session state to Dart via FRB (session token generation, a stream/callback of devices joining, and a way to finalize/start the transfer once the sender proceeds).
5. For the actual file transfer to multiple simultaneously joined devices: if Step 0 found the transfer engine already supports fan-out to multiple receivers, wire this pairing session into that existing mechanism. If it does NOT already support this, implement the minimum necessary extension to send the same staged files to each joined device concurrently (not sequentially) - this may mean running the existing single-receiver transfer logic in parallel once per joined device, which is an acceptable approach if a deeper engine change isn't feasible in this task. State clearly which approach you took and why.

LAYER 3 - DART (orchestration + UI):
1. Send button pop-up card with two tabs: "Scan QR" and "Wi-Fi Direct", using existing glass-card styling.
2. QR tab: on open, call the Kotlin hotspot bridge (Layer 1) to start the hotspot and get SSID/password. Call the Rust layer (Layer 2) to generate a session token. Encode SSID, password, and session token into the QR payload (extend qr_payload_parser.dart per Step 0's findings). Display: QR code, "Scan this QR code from the other device", divider "Or", network name/password as text fallback, Cancel button.
3. Below the QR: three toggles - "Multi-recipients" (when OFF, close the QR and proceed to transfer as soon as the first device joins per Layer 2's stream; when ON, keep QR open, show joined devices accumulating, proceed only when the user explicitly confirms "start transfer" with however many have joined), "5GHz mode" (only enabled/shown if Layer 1 reports the device supports it; disabled/hidden otherwise), "Encrypted device-to-device transfer" (reuse the app's existing encryption state/toggle if one already exists elsewhere, do not create a disconnected duplicate setting).
4. On Cancel or pop-up dismissal, call Layer 1's cleanup to stop the hotspot and invalidate the Rust session token.
5. Wi-Fi Direct tab: use the existing device discovery mechanism (already improved in commit b77ca813) to list nearby devices. Add the three toggles described in the original spec (Multi-recipients - enabling multi-select from the device list for simultaneous send; Pairing PIN protection - 6-digit PIN popup, pre-filled random, editable; Encrypted device-to-device transfer - same shared state as the QR tab). Tapping a device (or confirming multi-select) connects using existing connection logic.
6. Once paired (either tab), proceed using the transfer engine per Layer 2's wiring.

GENERAL RULES:
- Follow the investigate-then-implement order above strictly. Do not skip Step 0.
- Keep the three layers clearly separated in your implementation and in your final report, so if GitHub Actions reports a build failure, we can immediately tell which layer it's in.
- Reuse existing theme tokens, QR parsing, device discovery, MethodChannel patterns, and transfer engine code - do not duplicate existing functionality.
- Do a full static review of every touched file (Kotlin and Dart) for balanced brackets, correct imports, and correct types before committing.
- Commit with a message like "feat: QR pairing with simultaneous multi-recipient and Wi-Fi Direct refinement".
- Explicitly push to main, even if local verification is incomplete due to missing Flutter/Rust/FRB tooling in this container - GitHub Actions will be the real verifier, as it has been for prior successful rounds. If, after genuine effort across all three layers, something is truly not achievable without fabrication, say so plainly for that specific piece only - do not let one hard piece block committing the rest of the genuinely completed work.
- Run `git fetch && git log origin/main -1 --oneline` after pushing and paste the output.

Report back: Step 0's findings, what was implemented at each layer, any part genuinely deferred with a clear technical reason, and confirmation of the push with command output.
