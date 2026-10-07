TASK: Batch 3A - Send/Receive pairing CARDS (Dart UI only). The PairingController (Batch 2B) already holds all state and logic. Do NOT edit Rust, Kotlin, generated files, or the controller's logic (only add small read-only getters if truly required, and list them). Do NOT touch the file browser, the floating dock or the transfer progress page (Batch 3B/4).

Run git pull first. BEFORE coding PRINT: PairingController's public states/actions/options, the current Send entry (home_page.dart), pairing_page.dart, the receive page/nearby UI, the existing theme tokens (cyan/violet/emerald, glass style) and the existing QR + mobile_scanner usage. Use only real APIs.

All text goes in app/lib/pages/pairing/pairing_strings.dart (no slang). Support dark AND light themes using existing tokens. Layout must work on small phones (360dp wide) without overflow.

SEND CARD (tap Send, opens a bottom glass card, NO file required):
- Segmented tabs: "QR" (DEFAULT, selected on open) and "Wi-Fi Direct".
- QR tab: on open, controller starts hotspot + session automatically. Show a large QR only (never show SSID/password on the sender), a 5-minute countdown, a live list of joined devices (avatar/icon + name), and a Close button. Checkboxes below the QR: "Multi-recipients" and "Encrypted device-to-device transfer". Show a "5G mode" checkbox ONLY when controller.canUse5GMode is true (it is false today, so it must not appear).
- Single-recipient behaviour: on the controller's closedForSelection state, close the card automatically so the user can pick files. Multi-recipient: Close only hides the card; the session keeps running and a slim "Pairing active - N devices - Disconnect" bar stays visible above the bottom nav until Disconnect.
- Wi-Fi Direct tab (same-network mode): show my avatar/image + device name with a "Visible to nearby devices" state and countdown. Checkboxes: "Multi-recipients", "Pairing pin protection", "Encrypted device-to-device transfer". Enabling the PIN checkbox opens an "Enter PIN" dialog prefilled with the controller's random 6-digit PIN; the user can accept it or clear and type their own (exactly 6 digits, validate); the PIN is then shown on the card. A "How to connect" button opens a step-by-step guide sheet: (1) both phones on the same Wi-Fi/LAN, or (2) on Phone A use the QR tab, which turns the hotspot on for you, and join it from Phone B; (3) open Receive -> Nearby and tap the sender. Also keep the classic "send to a nearby device" LAN flow reachable from this tab.
- Remove the old small QR-icon entry on the old Nearby sheet; the new card replaces that entry point, existing LAN send logic stays intact.

RECEIVE CARD (tap Receive, bottom glass card): on open, call the controller's enable-Wi-Fi step.
- Tabs: "QR Scanner" and "Nearby".
- QR Scanner: camera view with a scanning animation (corner brackets + sweeping line), camera-permission-denied state, and controller states shown clearly: connecting, joining, joined, failed (real reason + Retry). If the offer needs a PIN, show a 6-digit PIN prompt. If auto-connect fails show the manual fallback: SSID, password with a Copy button and "I'm connected" button.
- Nearby: a radar scanning animation (pulsing concentric rings) while searching, discovered SENDING devices appear as cards (avatar + name), tap to join, PIN prompt when required, states as above. Empty state: "Looking for senders" plus a "How to connect" link opening the same guide. Remove the irrelevant text currently shown there.
- Checkboxes on the Receive card: show "Encrypted device-to-device transfer" (receiver requires the secure option). "Multi-recipients" is a sender option, so it must not appear on Receive. Say in your report exactly what each shown option does.

Rules: no fake devices, no fake success, no hardcoded colors outside the theme tokens, animations must stop when the card closes (no leaks), no work in build().

VERIFY: whole-app fvm dart analyze (cd app && fvm dart analyze lib) with zero errors; run the tests you can; git diff --check; last 15 lines of app/lib/main.dart for stray characters.
FINISH: commit "feat: send/receive pairing cards, scanner and radar animations, connection guide", git push origin main. If push fails with an auth error, STOP and say so. Show git log -1 --stat and the hash.
