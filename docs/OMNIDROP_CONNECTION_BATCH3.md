This is OmniDrop, built on LocalSend's existing architecture (Dart/Flutter app, Kotlin native layer, Rust backend for transfer/crypto, theme tokens in lib/config/theme.dart). This task implements real QR pairing and Wi-Fi Direct connection methods for the Send flow. This is genuinely difficult native networking work - take it seriously, do not fake or mock any part of it.

IMPORTANT CONTEXT: An earlier phase attempted this and explicitly reported it could NOT be completed or verified, because it requires Rust backend changes plus regenerating Flutter-Rust-Bridge (FRB) bindings, and this Codespace container has no Rust/FRB/Flutter toolchain to run that codegen step locally. Given that limitation, your instruction this time is different: ATTEMPT the implementation fully, COMMIT and PUSH it even if you cannot verify it compiles locally. The actual verification will happen via GitHub Actions (the real build pipeline), and any errors will be read from its build log and fixed in a focused follow-up, the same iterative process already used successfully for multiple previous rounds in this project. Do not refuse to commit working code just because you can't test it here - that caution was right once, but it's now the blocker, and we have a working alternate verification path.

Do NOT touch: encryption/HTTPS handling internals, the signing config, the package ID/app name, or anything unrelated to the connection flow described below. Reuse the existing QR payload parsing code from an earlier batch (qr_payload_parser.dart) rather than rebuilding it, if it already covers what's needed here.

SEND BUTTON POP-UP CARD:
When the "Send" button is tapped (with files already staged/selected), show a pop-up card with two tabs at the top: "Scan QR" and "Wi-Fi Direct". Use the app's existing glass-card styling for this pop-up.

TAB 1 - QR PAIRING MODE:
1. On opening this tab, automatically start a local-only Wi-Fi hotspot using Android's WifiManager.startLocalOnlyHotspot() API (this is the correct, app-scoped, Play-Store-safe hotspot API - NOT a request for the user's system-wide Personal Hotspot, and NOT MANAGE_WIFI_STATE-broad control). This works without special restricted permissions and is appropriate for Android 8.0+.
2. Generate and display a QR code encoding the hotspot's SSID, password, and enough session/pairing information for a receiving device (using OmniDrop's existing Receive QR-scanner flow, already built in an earlier batch) to join the hotspot and establish a transfer session automatically - no manual Wi-Fi settings navigation required on either side.
3. Below the QR code, also display the network name and password as plain text (as a fallback for manual entry), matching this layout: QR code, "Scan this QR code from the other device", a divider with "Or", then the network name/password shown as text, then a Cancel button.
4. Below that, show three toggle/checkbox options:
   a. "Multi-recipients" - when OFF (default), the QR/pop-up closes automatically once one device connects and pairs, then proceeds to file selection/transfer. When ON, the QR code remains active and visible so multiple devices can scan and connect before proceeding.
   b. "5GHz mode" - when enabled, prefer/prioritize the 5GHz Wi-Fi band for the hotspot if the device's hardware supports it (check Wi-Fi capability before allowing this toggle to be enabled at all; if the device doesn't support 5GHz, disable/hide this toggle rather than showing a non-functional option). Do not attempt to control cellular network generation, this refers only to the Wi-Fi band.
   c. "Encrypted device-to-device transfer" - this should reflect/control the app's existing end-to-end encryption for the transfer session (reuse whatever encryption toggle/state already exists elsewhere in the app if one does, rather than creating a separate disconnected setting).
5. Once a connection is established (or connections, if multi-recipient), proceed with the actual file transfer using the app's existing transfer engine - the pairing/QR flow's job is only to establish the connection, the existing transfer code should handle moving the files once connected.

TAB 2 - WI-FI DIRECT MODE:
1. This tab should use the app's EXISTING LAN/network device discovery mechanism (whatever mDNS or local network scanning this LocalSend-based app already uses to find nearby devices) to show a list of discoverable nearby devices, each with their avatar/icon and device name. Do NOT implement a separate true Android Wi-Fi Direct P2P (WifiP2pManager) system from scratch - reuse the existing discovery mechanism already present in this codebase for this tab's device list, since building genuine P2P discovery as a parallel system would be a much larger undertaking than intended here. If you find the existing discovery mechanism is insufficient for this use case, stop and note that clearly in your report rather than building a parallel P2P system.
2. Tapping a discovered device initiates a connection/pairing to that specific device using the app's existing connection logic.
3. Below the device list, show three toggle options:
   a. "Multi-recipients" - when enabled, allows selecting and sending to multiple discovered devices simultaneously, rather than only one.
   b. "Pairing PIN protection" - when enabled, show a pop-up prompting "Enter PIN" with a text input pre-filled with a random 6-digit PIN. The user can press Enter/confirm to accept the pre-filled PIN, or clear the field and type their own 6-digit PIN. This PIN must then be required on the receiving device to complete pairing.
   c. "Encrypted device-to-device transfer" - same as in the QR tab, reflects/controls the app's existing encryption state.
4. Once paired, proceed with the existing transfer engine the same way as the QR tab.

GENERAL RULES:
- This task spans Dart/Flutter UI, Kotlin native code (hotspot control), and likely Rust/FRB layer changes (for the join/pairing session protocol) - keep these clearly separated in your implementation so each layer's changes are easy to reason about independently in the build log if something fails.
- Reuse existing theme tokens, existing QR parsing code, existing device discovery code, and existing transfer engine code wherever possible. Do not duplicate functionality that already exists elsewhere in the app.
- Do a full static review of every touched file for balanced brackets, correct imports, and correct types before committing - Kotlin type mismatches and Dart syntax errors have been the main build failure causes in this project, be careful.
- Commit with a message like "feat: implement QR pairing and Wi-Fi Direct connection methods".
- Explicitly push to main even if local verification is incomplete, per the instruction above. Run `git fetch && git log origin/main -1 --oneline` and paste the output to confirm.

Report back: what was actually implemented at each layer (Dart/Kotlin/Rust), anything genuinely left as a placeholder with a clear reason why, and confirmation of the push with command output.
