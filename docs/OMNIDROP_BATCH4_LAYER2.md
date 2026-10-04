This is OmniDrop. This task implements ONLY Layer 2 (Rust/FRB pairing session protocol) of the QR pairing feature. Layer 1 (Kotlin hotspot bridge) is already complete, committed as e0e7512e. Layer 3 (Dart UI) will be a separate future task - do not build any UI in this task, only the Rust backend logic and its FRB-exposed interface for Dart to eventually call.

CONFIRMED FINDINGS FROM PRIOR INVESTIGATION (do not re-investigate, use these directly):
1. The existing WebDrop server is in packages/core/src/http/server/. It uses Hyper, with routes dispatched by a central (method, path) match in mod.rs; handlers are added to that match and implemented in server modules.
2. The transfer engine currently has ONE target device per send session, and the Rust receiver has one active upload-session slot. Fan-out to multiple simultaneous recipients is NOT built in - concurrent transfers to multiple devices need separate sessions per recipient.
3. qr_payload_parser.dart requires alias, ip, port, https, fp, and sid for omnidrop://pair codes. WebDrop http(s) links use a separate payload type, so new pairing-specific fields can be added without changing WebDrop parsing or breaking existing pair codes.
4. The Dart/Kotlin bridge uses com.omnidrop.app.localsend as the channel; Dart calls named methods via MethodChannel.invokeMethod, Kotlin's MainActivity.configureFlutterEngine handles them and returns results through MethodChannel.Result. (This is the Kotlin<->Dart bridge, separate from the Rust/FRB bridge this task focuses on.)

TASK - IMPLEMENT LAYER 2:

1. SESSION STATE:
In the Rust core package, add an in-memory pairing session manager (a new module is fine, e.g. packages/core/src/pairing/ or similar, following this codebase's existing module organization). It should support:
   - Creating a new pairing session: generates a random, sufficiently unguessable session token (session ID), records the sender's identity/device info, and timestamps creation.
   - Sessions expire automatically after 5 minutes if never used (either via a background cleanup check or lazy expiry check on access - whichever fits this codebase's existing patterns for similar time-based state, if any exist).
   - Tracking MULTIPLE joined devices per session (not just one) - this session state must be a collection (e.g. a list/map of joined device info) since multi-recipient is simultaneous, per earlier requirements. Each joined device entry should record at minimum: device identity/name, join timestamp, and connection info needed to later send it files.
   - A method to finalize/close a session (stop accepting new joins), callable once the sender proceeds to transfer.

2. HTTP JOIN ROUTE:
Add a new route to the existing server at a path like /api/omnidrop/v1/join (POST), following the existing route-dispatch pattern found in mod.rs. This endpoint should:
   - Accept a JSON body containing the session token and the joining device's identity info.
   - Validate the token against the session manager from step 1 (exists, not expired, still accepting joins).
   - On success: record the joining device in that session's joined-devices list, return a success response (e.g. confirmation + sender's info so the joining device can display "connected to X").
   - On failure (invalid/expired/closed token): return an appropriate error response with a clear reason (e.g. "session not found", "session expired", "session closed").
   - This must be safe for CONCURRENT joins - multiple devices may call this endpoint for the same session token around the same time, and all valid ones should succeed and be tracked, not just the first (reflecting simultaneous multi-recipient).

3. FRB EXPOSURE (Rust <-> Dart bridge, separate from the Kotlin channel):
Expose the following to Dart via this codebase's existing Flutter-Rust-Bridge pattern (find and follow however other Rust functions are currently exposed to Dart in this codebase, likely via #[frb] annotated functions or a similar existing convention):
   - A function to create a new pairing session, returning the session token.
   - A stream or callback mechanism Dart can listen to for "device joined" events for a given session (so the UI can update in real time as devices join, needed for the multi-recipient QR flow to show joined devices accumulating).
   - A function to finalize a session (stop accepting joins) given its token.
   - A function to retrieve the current list of joined devices for a session (for cases where Dart needs a snapshot rather than just the stream).

4. TRANSFER FAN-OUT (minimum viable approach, per earlier guidance):
Since the transfer engine doesn't natively support fan-out, implement the pragmatic approach already pre-approved: provide a Rust/FRB function that, given a session's list of joined devices and a set of staged files, initiates the EXISTING single-receiver transfer logic once per joined device, running these concurrently (not sequentially) rather than attempting a deeper transfer-engine redesign. Document this clearly with a code comment explaining this is a concurrent-sessions approach, not true protocol-level fan-out, in case the transfer engine is redesigned to support real fan-out later.

GENERAL RULES:
- Do NOT build any Dart UI in this task - FRB exposure only, no screens, no pop-ups. That is a separate future task.
- Do NOT touch the Kotlin hotspot bridge (already complete) or qr_payload_parser.dart's existing WebDrop handling.
- Follow this codebase's existing Rust code style, error handling patterns, and module organization - match what's already there rather than introducing a different style.
- Since Flutter/Cargo/the FRB code generator are unavailable in this container (confirmed from the prior task), you cannot run cargo build or regenerate FRB bindings here. Write the Rust code and the #[frb]-annotated function signatures as correctly as you can based on the existing codebase's patterns, commit and push it regardless, and note clearly in your report that FRB binding regeneration itself could not be verified or run - this will need to happen via GitHub Actions or a future session with the toolchain available, and may need a follow-up fix round, which is expected and fine.
- Do a full static review of every touched file for balanced parentheses/braces and correct Rust syntax before committing, to the best extent possible without a compiler.
- Commit with a message like "feat: implement Rust/FRB pairing session protocol (Layer 2)".
- Explicitly push to main. Run `git fetch && git log origin/main -1 --oneline` and paste the output.

Report back: what was implemented, which parts could not be verified due to missing toolchain (expected), and confirmation of the push with command output.
