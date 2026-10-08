import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/pages/pairing/pairing_strings.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/pairing/pairing_controller.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/device_type_ext.dart';
import 'package:localsend_app/util/qr_payload_parser.dart';
import 'package:localsend_app/widget/glass/glass_card.dart';
import 'package:localsend_isolates/rust/api/pairing.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

Future<List<PairingDeviceInfo>?> showPairingSendCard(
  BuildContext context, {
  required Future<void> Function() onSendOverLan,
}) {
  return showModalBottomSheet<List<PairingDeviceInfo>>(
    context: context,
    isScrollControlled: true,
    enableDrag: false,
    isDismissible: false,
    backgroundColor: Colors.transparent,
    builder: (_) => _PairingSheet(
      child: _SendPairingCard(onSendOverLan: onSendOverLan),
    ),
  );
}

Future<void> showPairingReceiveCard(BuildContext context, {bool allowWebDropLinks = false}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    enableDrag: false,
    isDismissible: false,
    backgroundColor: Colors.transparent,
    builder: (_) => _PairingSheet(
      child: _ReceivePairingCard(allowWebDropLinks: allowWebDropLinks),
    ),
  );
}

class _PairingSheet extends StatelessWidget {
  final Widget child;

  const _PairingSheet({required this.child});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final height = media.size.height - media.viewInsets.bottom;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: SizedBox(
          height: height * 0.92,
          child: GlassCard(
            margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            padding: EdgeInsets.zero,
            radius: glassRadiusModal,
            blur: true,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _SendPairingCard extends StatefulWidget {
  final Future<void> Function() onSendOverLan;

  const _SendPairingCard({required this.onSendOverLan});

  @override
  State<_SendPairingCard> createState() => _SendPairingCardState();
}

class _SendPairingCardState extends State<_SendPairingCard> with Refena {
  late PairingMode _mode;
  late bool _multiRecipient;
  late bool _encrypted;
  bool _pinEnabled = false;
  bool _busy = false;
  bool _autoClosed = false;
  String _pin = '';
  int _secondsLeft = 300;
  Timer? _stateTimer;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final current = ref.read(pairingControllerProvider);
    _mode = current.sessionToken != null && current.mode == PairingMode.sameNetwork ? PairingMode.sameNetwork : PairingMode.qr;
    _multiRecipient = current.sessionToken != null ? current.multiRecipient : false;
    _pinEnabled = current.sessionToken != null && current.pinRequired && _mode == PairingMode.sameNetwork;
    _pin = current.pin ?? ref.notifier(pairingControllerProvider).suggestPin();
    _encrypted = current.sessionToken != null ? current.encrypted : ref.read(serverProvider)?.https ?? ref.read(settingsProvider).https;
    _stateTimer = Timer.periodic(const Duration(seconds: 1), _onTick);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_ensureSession(_mode));
    });
  }

  @override
  void dispose() {
    _stateTimer?.cancel();
    super.dispose();
  }

  void _onTick(Timer timer) {
    if (!mounted) return;
    final state = ref.read(pairingControllerProvider);
    final expiry = state.expiresAt;
    if (expiry != null) {
      final remaining = expiry.difference(DateTime.now()).inSeconds.clamp(0, 300);
      if (remaining != _secondsLeft) setState(() => _secondsLeft = remaining);
    }
    if (!_autoClosed && !state.multiRecipient && state.phase == PairingPhase.closedForSelection && state.peers.isNotEmpty) {
      _autoClosed = true;
      Navigator.of(context).pop<List<PairingDeviceInfo>>(state.peers);
    }
  }

  Future<void> _ensureSession(PairingMode mode, {bool restart = false}) async {
    if (_busy || !mounted) return;
    final controller = ref.notifier(pairingControllerProvider);
    final current = ref.read(pairingControllerProvider);
    if (!restart && current.sessionToken != null && current.mode == mode) return;

    setState(() => _busy = true);
    try {
      if (current.sessionToken != null) await controller.stop();
      await controller.startSender(
        PairingOptions(
          mode: mode,
          multiRecipient: _multiRecipient,
          pinEnabled: mode == PairingMode.sameNetwork && _pinEnabled,
          pin: _pinEnabled ? _pin : null,
          encrypted: _encrypted,
        ),
      );
      if (mounted) {
        final expiry = ref.read(pairingControllerProvider).expiresAt;
        setState(() => _secondsLeft = expiry?.difference(DateTime.now()).inSeconds.clamp(0, 300) ?? 300);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {});
      if (ref.read(pairingControllerProvider).failureReason == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _selectMode(PairingMode mode) async {
    if (_mode == mode || _busy) return;
    setState(() => _mode = mode);
    await _ensureSession(mode);
  }

  Future<void> _changeOption({bool? multiRecipient, bool? encrypted}) async {
    if (_busy) return;
    setState(() {
      if (multiRecipient != null) _multiRecipient = multiRecipient;
      if (encrypted != null) _encrypted = encrypted;
    });
    await _ensureSession(_mode, restart: true);
  }

  Future<void> _setPinProtection(bool enabled) async {
    if (_busy) return;
    if (!enabled) {
      setState(() => _pinEnabled = false);
      await _ensureSession(_mode, restart: true);
      return;
    }

    final pinController = TextEditingController(text: _pin.isEmpty ? ref.notifier(pairingControllerProvider).suggestPin() : _pin);
    var errorText = '';
    final pin = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text(PairingStrings.enterPin),
          content: TextField(
            controller: pinController,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: PairingStrings.pinHint,
              errorText: errorText.isEmpty ? null : errorText,
              counterText: '',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text(PairingStrings.cancel)),
            FilledButton(
              onPressed: () {
                if (!PairingController.isValidPin(pinController.text)) {
                  setDialogState(() => errorText = PairingStrings.invalidPin);
                  return;
                }
                Navigator.pop(dialogContext, pinController.text);
              },
              child: const Text(PairingStrings.save),
            ),
          ],
        ),
      ),
    );
    pinController.dispose();
    if (pin == null || !mounted) return;
    setState(() {
      _pin = pin;
      _pinEnabled = true;
    });
    await _ensureSession(PairingMode.sameNetwork);
  }

  Future<void> _closeCard() async {
    final state = ref.read(pairingControllerProvider);
    if (state.multiRecipient && state.sessionToken != null) {
      Navigator.of(context).pop();
      return;
    }
    if (state.sessionToken != null) await ref.notifier(pairingControllerProvider).stop();
    if (mounted) Navigator.of(context).pop();
  }

  void _showGuide() => unawaited(showPairingConnectionGuide(context));

  Widget _multiRecipientOption() => CheckboxListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    title: const Text(PairingStrings.multiRecipients),
    value: _multiRecipient,
    onChanged: _busy ? null : (value) => _changeOption(multiRecipient: value == true),
  );

  Widget _encryptionOption() => CheckboxListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    title: const Text(PairingStrings.encryptedTransfer),
    value: _encrypted,
    onChanged: _busy ? null : (value) => _changeOption(encrypted: value == true),
  );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pairingControllerProvider);
    final device = ref.watch(deviceFullInfoProvider);
    final avatarIndex = ref.read(persistenceProvider).getProfileAvatar() % 6;
    final colors = Theme.of(context).colorScheme;
    final qrSize = (MediaQuery.sizeOf(context).width - 64).clamp(180.0, 300.0);

    return Column(
      children: [
        _CardHeader(title: PairingStrings.send, onClose: _closeCard),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<PairingMode>(
            segments: const [
              ButtonSegment(value: PairingMode.qr, label: Text(PairingStrings.qr), icon: Icon(Icons.qr_code_2)),
              ButtonSegment(value: PairingMode.sameNetwork, label: Text(PairingStrings.wifiDirect), icon: Icon(Icons.wifi)),
            ],
            selected: {_mode},
            onSelectionChanged: _busy ? null : (modes) => _selectMode(modes.first),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              children: [
                if (_mode == PairingMode.qr) ...[
                  if (state.qrPayload != null)
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints.tightFor(width: qrSize, height: qrSize),
                        child: GlassCard(
                          margin: EdgeInsets.zero,
                          padding: const EdgeInsets.all(10),
                          radius: glassRadiusCard,
                          child: PrettyQrView.data(
                            data: state.qrPayload!,
                            decoration: PrettyQrDecoration(shape: PrettyQrSmoothSymbol(color: colors.onSurface)),
                          ),
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      height: 210,
                      child: Center(
                        child: _busy || state.phase == PairingPhase.startingHotspot
                            ? const CircularProgressIndicator()
                            : Text(
                                state.failureReason ?? PairingStrings.startQr,
                                style: state.phase == PairingPhase.failed ? TextStyle(color: colors.error) : null,
                              ),
                      ),
                    ),
                  if (state.qrPayload != null) ...[
                    const SizedBox(height: 8),
                    const Text(PairingStrings.qrOnlyNotice, textAlign: TextAlign.center),
                    const SizedBox(height: 4),
                    _Countdown(seconds: _secondsLeft),
                  ],
                  if (state.expiresAt != null)
                    Text(PairingStrings.optionRestartHint, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
                  if (state.canUse5GMode)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(PairingStrings.fiveGHzMode),
                      value: false,
                      onChanged: null,
                    ),
                  _multiRecipientOption(),
                  _encryptionOption(),
                  if (state.phase == PairingPhase.closedForSelection)
                    Text(PairingStrings.selectDevices, style: Theme.of(context).textTheme.titleSmall),
                  _JoinedDevices(peers: state.peers),
                ] else ...[
                  _ProfileHeader(alias: device.alias, avatarIndex: avatarIndex),
                  Text(
                    state.sessionToken == null ? state.failureReason ?? PairingStrings.startNearby : PairingStrings.visibleToNearby,
                    style: state.phase == PairingPhase.failed
                        ? TextStyle(color: Theme.of(context).colorScheme.error)
                        : Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  if (state.expiresAt != null) ...[
                    const SizedBox(height: 4),
                    _Countdown(seconds: _secondsLeft),
                  ],
                  _multiRecipientOption(),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(PairingStrings.pinProtection),
                    value: _pinEnabled,
                    onChanged: _busy ? null : (value) => _setPinProtection(value == true),
                  ),
                  _encryptionOption(),
                  if (_pinEnabled)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(PairingStrings.senderPinLabel),
                      subtitle: SelectableText(_pin),
                    ),
                  _JoinedDevices(peers: state.peers),
                  TextButton.icon(onPressed: _showGuide, icon: const Icon(Icons.info_outline), label: const Text(PairingStrings.howToConnect)),
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await widget.onSendOverLan();
                    },
                    icon: const Icon(Icons.wifi_find),
                    label: const Text(PairingStrings.lanSend),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ReceivePairingCard extends StatefulWidget {
  final bool allowWebDropLinks;

  const _ReceivePairingCard({required this.allowWebDropLinks});

  @override
  State<_ReceivePairingCard> createState() => _ReceivePairingCardState();
}

class _ReceivePairingCardState extends State<_ReceivePairingCard> with Refena {
  PairingMode _mode = PairingMode.qr;
  late bool _encrypted;
  final TextEditingController _pinController = TextEditingController();
  int _scannerKey = 0;
  bool _handledCode = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _encrypted = ref.read(settingsProvider).https;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.notifier(pairingControllerProvider).enterReceiver());
    });
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _switchMode(PairingMode mode) async {
    if (_mode == mode) return;
    setState(() => _mode = mode);
    final controller = ref.notifier(pairingControllerProvider);
    if (mode == PairingMode.sameNetwork) {
      await controller.scanNearbyOffers();
    } else {
      await controller.enterReceiver();
    }
  }

  Future<void> _setEncryption(bool enabled) async {
    if (enabled == _encrypted) return;
    final previous = _encrypted;
    setState(() => _encrypted = enabled);
    try {
      await ref.notifier(settingsProvider).setHttps(enabled);
      if (ref.read(serverProvider) != null) {
        await ref.notifier(serverProvider).restartServerFromSettings();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _encrypted = previous);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handledCode) return;
    final value = capture.barcodes.map((barcode) => barcode.rawValue).whereType<String>().firstOrNull;
    if (value == null) return;
    final parsed = parseQrPayload(value);
    if (parsed case ParsedPairQr(:final payload)) {
      _handledCode = true;
      await ref.notifier(pairingControllerProvider).receiveQr(payload);
      return;
    }
    if (parsed is ExpiredPairQr) {
      _showNotice(PairingStrings.expired);
      return;
    }
    if (parsed case ParsedWebDropQr(:final uri)) {
      if (!widget.allowWebDropLinks) {
        _showNotice(PairingStrings.invalidQr);
        return;
      }
      final open = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text(PairingStrings.openLinkQuestion),
          content: Text(uri.toString(), maxLines: 2, overflow: TextOverflow.ellipsis),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text(PairingStrings.cancel)),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text(PairingStrings.open)),
          ],
        ),
      );
      if (open == true) await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    _showNotice(PairingStrings.invalidQr);
  }

  void _showNotice(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _retry() async {
    final state = ref.read(pairingControllerProvider);
    final controller = ref.notifier(pairingControllerProvider);
    if (state.phase == PairingPhase.manualGuide) {
      await controller.continueAfterManualWifi();
    } else if (state.phase == PairingPhase.waitingForPin || state.pinRequired) {
      await controller.submitPin(_pinController.text);
    } else {
      await controller.retry();
    }
  }

  Future<void> _scanNearby() => ref.notifier(pairingControllerProvider).scanNearbyOffers();

  Future<void> _joinOffer(PairingNearbyOffer offer) async {
    _pinController.clear();
    await ref.notifier(pairingControllerProvider).joinNearby(offer);
  }

  Future<void> _close() async {
    final state = ref.read(pairingControllerProvider);
    if (state.role == PairingRole.sender && state.sessionToken != null && !state.multiRecipient) {
      await ref.notifier(pairingControllerProvider).stop();
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pairingControllerProvider);
    return Column(
      children: [
        _CardHeader(title: PairingStrings.receive, onClose: _close),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<PairingMode>(
            segments: const [
              ButtonSegment(value: PairingMode.qr, label: Text(PairingStrings.qrScanner), icon: Icon(Icons.qr_code_scanner)),
              ButtonSegment(value: PairingMode.sameNetwork, label: Text(PairingStrings.nearby), icon: Icon(Icons.radar)),
            ],
            selected: {_mode},
            onSelectionChanged: (modes) => _switchMode(modes.first),
          ),
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: const Text(PairingStrings.encryptedTransfer),
          subtitle: const Text(PairingStrings.secureReceiveHint),
          value: _encrypted,
          onChanged: (value) => _setEncryption(value == true),
        ),
        Expanded(
          child: _mode == PairingMode.qr ? _buildQrScanner(context, state) : _buildNearby(context, state),
        ),
      ],
    );
  }

  Widget _buildQrScanner(BuildContext context, PairingState state) {
    final cameraUnavailable = !kIsWeb && (defaultTargetPlatform == TargetPlatform.linux || defaultTargetPlatform == TargetPlatform.windows);
    final showCamera = !cameraUnavailable && (state.phase == PairingPhase.scanning || !_handledCode && state.phase == PairingPhase.idle);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      children: [
        if (showCamera)
          _QrScannerView(
            key: ValueKey(_scannerKey),
            onDetect: _onDetect,
            onRetry: () => setState(() => _scannerKey++),
          )
        else if (cameraUnavailable && state.phase == PairingPhase.scanning)
          _MessagePanel(message: PairingStrings.cameraUnavailable)
        else if (state.phase == PairingPhase.enablingWifi)
          const _ProgressPanel(message: PairingStrings.enablingWifi)
        else if (state.phase == PairingPhase.joining)
          const _ProgressPanel(message: PairingStrings.joining)
        else if (state.phase == PairingPhase.connecting)
          const _ProgressPanel(message: PairingStrings.connecting)
        else if (state.phase == PairingPhase.joined)
          const _SuccessPanel(message: PairingStrings.joined)
        else if (state.phase == PairingPhase.manualGuide) ...[
          Text(PairingStrings.manualWifiHint, textAlign: TextAlign.center),
          if (state.failureReason != null)
            Text(
              state.failureReason!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
              textAlign: TextAlign.center,
            ),
          if (state.ssid != null) _CopyValueRow(label: PairingStrings.ssid, value: state.ssid!, canCopy: false),
          if (state.password != null) _CopyValueRow(label: PairingStrings.password, value: state.password!, canCopy: true),
          FilledButton(onPressed: _retry, child: const Text(PairingStrings.imConnected)),
        ] else if (state.phase == PairingPhase.waitingForPin)
          _buildPinPrompt(state)
        else if (state.phase == PairingPhase.failed && state.pinRequired) ...[
          _buildFailure(state),
          _buildPinPrompt(state),
        ] else if (state.phase == PairingPhase.failed)
          _buildFailure(state)
        else if (cameraUnavailable)
          _MessagePanel(message: PairingStrings.cameraUnavailable),
        if (state.phase == PairingPhase.joined)
          TextButton.icon(
            onPressed: () {
              _handledCode = false;
              _pinController.clear();
              setState(() => _scannerKey++);
              unawaited(ref.notifier(pairingControllerProvider).enterReceiver());
            },
            icon: const Icon(Icons.refresh),
            label: const Text(PairingStrings.scanAgain),
          ),
      ],
    );
  }

  Widget _buildNearby(BuildContext context, PairingState state) {
    final offers = [...state.offers]..sort((a, b) => a.device.alias.toLowerCase().compareTo(b.device.alias.toLowerCase()));
    final scanning = state.phase == PairingPhase.scanning;
    return Column(
      children: [
        Expanded(
          child: offers.isEmpty
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const SizedBox(height: 4),
                      _RadarView(active: scanning),
                      const SizedBox(height: 8),
                      const Text(PairingStrings.lookingForSenders, textAlign: TextAlign.center),
                      if (!scanning)
                        TextButton.icon(
                          onPressed: _scanNearby,
                          icon: const Icon(Icons.refresh),
                          label: const Text(PairingStrings.retry),
                        ),
                      TextButton(onPressed: () => unawaited(showPairingConnectionGuide(context)), child: const Text(PairingStrings.howToConnect)),
                      if (state.failureReason != null)
                        Text(
                          state.failureReason!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                          textAlign: TextAlign.center,
                        ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  children: [
                    for (final item in offers)
                      Card(
                        child: ListTile(
                          leading: CircleAvatar(child: Icon(item.device.deviceType.icon)),
                          title: Text(item.device.alias, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(item.device.deviceModel ?? PairingStrings.visibleToNearby),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _joinOffer(item),
                        ),
                      ),
                  ],
                ),
        ),
        if (offers.isNotEmpty)
          TextButton.icon(
            onPressed: scanning ? null : _scanNearby,
            icon: const Icon(Icons.refresh),
            label: const Text(PairingStrings.refresh),
          ),
        if (state.phase == PairingPhase.connecting) const _ProgressPanel(message: PairingStrings.connecting),
        if (state.phase == PairingPhase.joining) const _ProgressPanel(message: PairingStrings.joining),
        if (state.phase == PairingPhase.joined) const _SuccessPanel(message: PairingStrings.joined),
        if (state.phase == PairingPhase.waitingForPin) _buildPinPrompt(state),
        if (state.phase == PairingPhase.failed && state.pinRequired) ...[
          _buildFailure(state),
          _buildPinPrompt(state),
        ],
        if (state.phase == PairingPhase.failed && !state.pinRequired) _buildFailure(state),
      ],
    );
  }

  Widget _buildPinPrompt(PairingState state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: Column(
        children: [
          if (state.pinRequired) const Text(PairingStrings.pinRequired, textAlign: TextAlign.center),
          TextField(
            controller: _pinController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: PairingStrings.pinHint, counterText: ''),
          ),
          FilledButton(onPressed: _retry, child: const Text(PairingStrings.join)),
        ],
      ),
    );
  }

  Widget _buildFailure(PairingState state) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Text(
            state.failureReason ?? PairingStrings.failed,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
            textAlign: TextAlign.center,
          ),
          TextButton.icon(onPressed: _retry, icon: const Icon(Icons.refresh), label: const Text(PairingStrings.retry)),
        ],
      ),
    );
  }
}

class _QrScannerView extends StatefulWidget {
  final void Function(BarcodeCapture capture) onDetect;
  final VoidCallback onRetry;

  const _QrScannerView({required this.onDetect, required this.onRetry, super.key});

  @override
  State<_QrScannerView> createState() => _QrScannerViewState();
}

class _QrScannerViewState extends State<_QrScannerView> with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(vsync: this, duration: const Duration(milliseconds: 1900))..repeat();

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(glassRadiusCard),
      child: SizedBox(
        height: 250,
        child: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              onDetect: widget.onDetect,
              errorBuilder: (context, error) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.no_photography_outlined, color: colors.secondary, size: 34),
                      const SizedBox(height: 8),
                      Text(
                        error.errorCode == MobileScannerErrorCode.permissionDenied ? PairingStrings.cameraPermissionDenied : error.toString(),
                        textAlign: TextAlign.center,
                      ),
                      if (error.errorCode == MobileScannerErrorCode.permissionDenied)
                        Column(
                          children: [
                            const Text(PairingStrings.cameraPermissionHint, textAlign: TextAlign.center),
                            TextButton.icon(
                              onPressed: widget.onRetry,
                              icon: const Icon(Icons.refresh),
                              label: const Text(PairingStrings.retry),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
            IgnorePointer(
              child: AnimatedBuilder(
                animation: _sweep,
                builder: (context, child) => CustomPaint(
                  painter: _ScannerOverlayPainter(progress: _sweep.value, primary: colors.primary, accent: colors.tertiary),
                ),
              ),
            ),
            const Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(PairingStrings.scanSweepLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  final double progress;
  final Color primary;
  final Color accent;

  const _ScannerOverlayPainter({required this.progress, required this.primary, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final inset = 22.0;
    final width = size.width - inset * 2;
    final height = size.height - inset * 2;
    final corner = Paint()
      ..color = primary
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final rect = Rect.fromLTWH(inset, inset, width, height);
    final path = Path()
      ..moveTo(rect.left, rect.top + 24)
      ..lineTo(rect.left, rect.top)
      ..lineTo(rect.left + 24, rect.top)
      ..moveTo(rect.right - 24, rect.top)
      ..lineTo(rect.right, rect.top)
      ..lineTo(rect.right, rect.top + 24)
      ..moveTo(rect.left, rect.bottom - 24)
      ..lineTo(rect.left, rect.bottom)
      ..lineTo(rect.left + 24, rect.bottom)
      ..moveTo(rect.right - 24, rect.bottom)
      ..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.right, rect.bottom - 24);
    canvas.drawPath(path, corner);
    final y = rect.top + height * progress;
    final line = Paint()
      ..color = accent.withValues(alpha: 0.85)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(rect.left + 8, y), Offset(rect.right - 8, y), line);
  }

  @override
  bool shouldRepaint(_ScannerOverlayPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.primary != primary || oldDelegate.accent != accent;
}

class _RadarView extends StatefulWidget {
  final bool active;

  const _RadarView({required this.active});

  @override
  State<_RadarView> createState() => _RadarViewState();
}

class _RadarViewState extends State<_RadarView> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void initState() {
    super.initState();
    if (widget.active) unawaited(_pulse.repeat());
  }

  @override
  void didUpdateWidget(covariant _RadarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_pulse.isAnimating) {
      unawaited(_pulse.repeat());
    } else if (!widget.active && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 180,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) => CustomPaint(
          painter: _RadarPainter(progress: _pulse.value, primary: colors.primary, accent: colors.tertiary),
          child: Center(child: Icon(Icons.wifi_tethering, color: colors.secondary, size: 42)),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double progress;
  final Color primary;
  final Color accent;

  const _RadarPainter({required this.progress, required this.primary, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.shortestSide * 0.46;
    for (var index = 0; index < 3; index++) {
      final phase = (progress + index / 3) % 1;
      final radius = maxRadius * phase;
      final paint = Paint()
        ..color = (index.isEven ? primary : accent).withValues(alpha: (1 - phase) * 0.62)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_RadarPainter oldDelegate) => oldDelegate.progress != progress || oldDelegate.primary != primary || oldDelegate.accent != accent;
}

class _CardHeader extends StatelessWidget {
  final String title;
  final Future<void> Function() onClose;

  const _CardHeader({required this.title, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
      child: Row(
        children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
          IconButton(tooltip: PairingStrings.close, onPressed: onClose, icon: const Icon(Icons.close)),
        ],
      ),
    );
  }
}

class _Countdown extends StatelessWidget {
  final int seconds;

  const _Countdown({required this.seconds});

  @override
  Widget build(BuildContext context) {
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return Text('${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')} ${PairingStrings.remaining}');
  }
}

class _JoinedDevices extends StatelessWidget {
  final List<PairingDeviceInfo> peers;

  const _JoinedDevices({required this.peers});

  @override
  Widget build(BuildContext context) {
    if (peers.isEmpty) return Padding(padding: const EdgeInsets.all(14), child: Text(PairingStrings.noJoinedDevices));
    return Column(
      children: [
        for (final peer in peers)
          ListTile(
            dense: true,
            leading: const CircleAvatar(child: Icon(Icons.devices)),
            title: Text(peer.alias, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: peer.deviceModel == null ? null : Text(peer.deviceModel!),
          ),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final String alias;
  final int avatarIndex;

  const _ProfileHeader({required this.alias, required this.avatarIndex});

  static const _avatarIcons = [Icons.person, Icons.face, Icons.account_circle, Icons.pets, Icons.rocket_launch, Icons.bolt];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          CircleAvatar(radius: 30, child: Icon(_avatarIcons[avatarIndex.clamp(0, _avatarIcons.length - 1)], size: 28)),
          const SizedBox(height: 8),
          Text(alias, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _CopyValueRow extends StatelessWidget {
  final String label;
  final String value;
  final bool canCopy;

  const _CopyValueRow({required this.label, required this.value, required this.canCopy});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: SelectableText(value, maxLines: 1),
      trailing: canCopy
          ? IconButton(
              tooltip: PairingStrings.copy,
              icon: const Icon(Icons.copy),
              onPressed: () => Clipboard.setData(ClipboardData(text: value)),
            )
          : null,
    );
  }
}

class _MessagePanel extends StatelessWidget {
  final String message;

  const _MessagePanel({required this.message});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Text(message, textAlign: TextAlign.center),
  );
}

class _ProgressPanel extends StatelessWidget {
  final String message;

  const _ProgressPanel({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Text(message),
        ],
      ),
    );
  }
}

class _SuccessPanel extends StatelessWidget {
  final String message;

  const _SuccessPanel({required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, color: colors.tertiary),
          const SizedBox(width: 8),
          Text(message),
        ],
      ),
    );
  }
}

Future<void> showPairingConnectionGuide(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => SafeArea(
      child: GlassCard(
        margin: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(PairingStrings.howToConnect, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            _GuideStep(number: '1', text: PairingStrings.guideStepOne),
            _GuideStep(number: '2', text: PairingStrings.guideStepTwo),
            _GuideStep(number: '3', text: PairingStrings.guideStepThree),
          ],
        ),
      ),
    ),
  );
}

class _GuideStep extends StatelessWidget {
  final String number;
  final String text;

  const _GuideStep({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 13, child: Text(number)),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
