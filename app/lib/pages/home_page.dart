import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/config/init.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/copy_phone_page.dart';
import 'package:localsend_app/pages/home_page_controller.dart';
import 'package:localsend_app/pages/omnidrop_drawer.dart';
import 'package:localsend_app/pages/pairing/pairing_page.dart';
import 'package:localsend_app/pages/pairing/pairing_strings.dart';
import 'package:localsend_app/pages/tabs/omnidrop_tabs.dart';
import 'package:localsend_app/pages/tabs/send_tab.dart';
import 'package:localsend_app/pages/tabs/send_tab_vm.dart';
import 'package:localsend_app/pages/tabs/settings_tab.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/scan_facade.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/util/native/channel/android_channel.dart' as android_channel;
import 'package:localsend_app/util/native/cross_file_converters.dart';
import 'package:localsend_app/widget/animated_press.dart';
import 'package:localsend_app/widget/dialogs/add_file_dialog.dart';
import 'package:localsend_app/widget/dialogs/receive_pairing_dialog.dart';
import 'package:localsend_app/widget/glass/glass_card.dart';
import 'package:localsend_app/widget/list_tile/device_list_tile.dart';
import 'package:localsend_app/widget/omnidrop_logo.dart';
import 'package:localsend_app/widget/responsive_builder.dart';
import 'package:localsend_isolates/model/session_status.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

enum HomeTab {
  webDrop(Icons.language),
  osPairs(Icons.devices),
  send(Icons.send),
  me(Icons.person_outline)
  ;

  const HomeTab(this.icon);

  final IconData icon;

  String get label {
    switch (this) {
      case HomeTab.webDrop:
        return 'WebDrop';
      case HomeTab.osPairs:
        return 'OS Pairs';
      case HomeTab.send:
        return 'Transfer';
      case HomeTab.me:
        return 'Me';
    }
  }
}

class HomePage extends StatefulWidget {
  final HomeTab initialTab;

  /// It is important for the initializing step
  /// because the first init clears the cache
  final bool appStart;

  const HomePage({
    required this.initialTab,
    required this.appStart,
    super.key,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with Refena {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _transferTabKey = GlobalKey<_TransferTabState>();
  bool _dragAndDropIndicator = false;

  @override
  void initState() {
    super.initState();

    ensureRef((ref) async {
      ref.redux(homePageControllerProvider).dispatch(ChangeTabAction(widget.initialTab));
      await postInit(context, ref, widget.appStart);
    });
  }

  @override
  Widget build(BuildContext context) {
    Translations.of(context); // rebuild on locale change
    final vm = context.watch(homePageControllerProvider);

    return DropTarget(
      onDragEntered: (_) {
        setState(() {
          _dragAndDropIndicator = true;
        });
      },
      onDragExited: (_) {
        setState(() {
          _dragAndDropIndicator = false;
        });
      },
      onDragDone: (event) async {
        // the drop may contain a mix of files and directories
        final droppedDirectories = event.files.where((file) => Directory(file.path).existsSync()).toList();
        final droppedFiles = event.files.where((file) => !Directory(file.path).existsSync()).toList();

        for (final directory in droppedDirectories) {
          await ref.redux(selectedSendingFilesProvider).dispatchAsync(AddDirectoryAction(directory.path));
        }

        if (droppedFiles.isNotEmpty) {
          await ref
              .redux(selectedSendingFilesProvider)
              .dispatchAsync(
                AddFilesAction(
                  files: droppedFiles,
                  converter: CrossFileConverters.convertXFile,
                ),
              );
        }
        vm.changeTab(HomeTab.send);
      },
      child: ResponsiveBuilder(
        builder: (sizingInformation) {
          final colors = Theme.of(context).colorScheme;
          final light = Theme.of(context).brightness == Brightness.light;
          return Scaffold(
            key: _scaffoldKey,
            drawer: const OmniDropDrawer(),
            endDrawer: Drawer(
              backgroundColor: Colors.transparent,
              child: GlassCard(
                margin: EdgeInsets.zero,
                padding: EdgeInsets.zero,
                radius: 0,
                blur: true,
                child: SafeArea(child: const SettingsTab()),
              ),
            ),
            appBar: AppBar(
              automaticallyImplyLeading: false,
              backgroundColor: Colors.transparent,
              flexibleSpace: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      colors.primary.withValues(alpha: light ? 0.24 : 0.16),
                      colors.secondary.withValues(alpha: light ? 0.16 : 0.08),
                    ],
                  ),
                ),
              ),
              leading: IconButton(
                tooltip: 'Open navigation drawer',
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                icon: const Icon(Icons.more_vert),
              ),
              title: Row(
                children: [
                  const OmniDropLogo(size: 32),
                  const SizedBox(width: 8),
                  const Text('OmniDrop'),
                ],
              ),
              actions: [
                PopupMenuButton<String>(
                  tooltip: 'More actions',
                  icon: const Icon(Icons.menu),
                  onSelected: (value) async {
                    if (value == 'scan') {
                      await showReceivePairingDialog(context, allowWebDropLinks: true);
                    } else if (value == 'share') {
                      final shared = await android_channel.shareInstalledApkAndroid();
                      if (!shared) await android_channel.shareTextInviteAndroid();
                    } else {
                      final started = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(builder: (_) => const CopyPhonePage()),
                      );
                      if (started == true && context.mounted) {
                        vm.changeTab(HomeTab.send);
                        final transferState = _transferTabKey.currentState;
                        if (transferState != null) await transferState._startSend();
                      }
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'scan', child: Text('Scan Connect')),
                    PopupMenuItem(value: 'share', child: Text('Share OmniDrop')),
                    PopupMenuItem(value: 'copy', child: Text('Copy Phone')),
                  ],
                ),
                IconButton(
                  tooltip: 'Settings',
                  onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                  icon: const Icon(Icons.settings_outlined),
                ),
              ],
            ),
            body: Stack(
              fit: StackFit.expand,
              children: [
                _OmniDropBackground(colors: colors, light: light),
                Row(
                  children: [
                    if (!sizingInformation.isMobile)
                      NavigationRail(
                        selectedIndex: vm.currentTab.index,
                        onDestinationSelected: (index) => vm.changeTab(HomeTab.values[index]),
                        extended: sizingInformation.isDesktop,
                        backgroundColor: Colors.transparent,
                        destinations: HomeTab.values.map((tab) {
                          return NavigationRailDestination(
                            icon: tab == HomeTab.send ? const OmniDropLogo(size: 24) : Icon(tab.icon),
                            label: Text(tab.label),
                          );
                        }).toList(),
                      ),
                    Expanded(
                      child: SafeArea(
                        left: sizingInformation.isMobile,
                        child: Stack(
                          children: [
                            PageView(
                              controller: vm.controller,
                              physics: const NeverScrollableScrollPhysics(),
                              children: [
                                const WebDropTab(),
                                const OsPairsTab(),
                                _TransferTab(key: _transferTabKey),
                                const MeTab(),
                              ],
                            ),
                            if (_dragAndDropIndicator)
                              Container(
                                width: double.infinity,
                                decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.file_download, size: 128),
                                    const SizedBox(height: 30),
                                    Text(t.sendTab.placeItems, style: Theme.of(context).textTheme.titleLarge),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            bottomNavigationBar: sizingInformation.isMobile
                ? SafeArea(
                    top: false,
                    child: GlassCard(
                      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      padding: EdgeInsets.zero,
                      radius: 30,
                      blur: true,
                      child: SizedBox(
                        height: 68,
                        child: Row(
                          children: HomeTab.values.map((tab) {
                            final selected = vm.currentTab == tab;
                            if (tab == HomeTab.send) {
                              return Expanded(
                                child: Center(
                                  child: FloatingActionButton(
                                    heroTag: 'transfer-tab',
                                    onPressed: () => vm.changeTab(tab),
                                    child: const OmniDropLogo(size: 28),
                                  ),
                                ),
                              );
                            }
                            return Expanded(
                              child: InkWell(
                                onTap: () => vm.changeTab(tab),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(tab.icon, color: selected ? colors.primary : null),
                                    Text(tab.label, style: Theme.of(context).textTheme.labelSmall),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  )
                : null,
          );
        },
      ),
    );
  }
}

const String? _darkBackgroundImage = null;
const String? _lightBackgroundImage = null;

class _OmniDropBackground extends StatelessWidget {
  final ColorScheme colors;
  final bool light;

  const _OmniDropBackground({required this.colors, required this.light});

  @override
  Widget build(BuildContext context) {
    final image = light ? _lightBackgroundImage : _darkBackgroundImage;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: light ? const Color(0xFFEAF5FA) : glassBackground,
          image: image == null ? null : DecorationImage(image: AssetImage(image), fit: BoxFit.cover),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.85, -0.8),
                  radius: 1.0,
                  colors: [colors.primary.withValues(alpha: light ? 0.20 : 0.22), Colors.transparent],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.9, 0.9),
                  radius: 1.0,
                  colors: [colors.secondary.withValues(alpha: light ? 0.12 : 0.18), Colors.transparent],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransferTab extends StatefulWidget {
  const _TransferTab({super.key});

  @override
  State<_TransferTab> createState() => _TransferTabState();
}

class _TransferTabState extends State<_TransferTab> with Refena {
  Future<void> _startSend() async {
    var files = ref.read(selectedSendingFilesProvider);
    if (files.isEmpty) {
      await AddFileDialog.open(context: context, options: pickerOptions);
      files = ref.read(selectedSendingFilesProvider);
    }
    if (!mounted || files.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (_) => Consumer(
        builder: (dialogContext, ref) {
          final vm = ref.watch(sendTabVmProvider);
          final nearbyState = ref.watch(nearbyDevicesProvider);
          final devices = vm.nearbyDevices.toList()..sort((a, b) => a.alias.toLowerCase().compareTo(b.alias.toLowerCase()));
          final isScanning = nearbyState.runningFavoriteScan || nearbyState.runningIps.isNotEmpty;
          final dialogHeight = (MediaQuery.sizeOf(dialogContext).height * 0.72).clamp(180.0, 600.0).toDouble();

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: SizedBox(
                height: dialogHeight,
                child: GlassCard(
                  margin: EdgeInsets.zero,
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Nearby devices', style: Theme.of(dialogContext).textTheme.titleLarge),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Choose a device on your local network to send the staged files.',
                                    style: Theme.of(dialogContext).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            if (isScanning)
                              const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                              )
                            else
                              IconButton(
                                tooltip: 'Scan again',
                                onPressed: () async {
                                  dialogContext.redux(nearbyDevicesProvider).dispatch(ClearFoundDevicesAction());
                                  await dialogContext.global.dispatchAsync(StartSmartScan());
                                },
                                icon: const Icon(Icons.refresh),
                              ),
                            IconButton(
                              tooltip: PairingStrings.pairFiles,
                              onPressed: () async {
                                Navigator.of(dialogContext).pop();
                                await vm.onTapPairing(context);
                              },
                              icon: const Icon(Icons.qr_code_2),
                            ),
                            IconButton(
                              tooltip: 'Close',
                              onPressed: () => Navigator.of(dialogContext).pop(),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: devices.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isScanning ? Icons.wifi_find : Icons.devices_other,
                                        size: 36,
                                        color: Theme.of(dialogContext).colorScheme.secondary,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(isScanning ? 'Scanning for nearby devices...' : 'No nearby devices found.'),
                                      const SizedBox(height: 8),
                                      TextButton(
                                        onPressed: () async {
                                          dialogContext.redux(nearbyDevicesProvider).dispatch(ClearFoundDevicesAction());
                                          await dialogContext.global.dispatchAsync(StartSmartScan());
                                        },
                                        child: const Text('Scan again'),
                                      ),
                                      TextButton(
                                        onPressed: () async {
                                          Navigator.of(dialogContext).pop();
                                          await vm.onTapAddress(context);
                                        },
                                        child: const Text('Enter device address'),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                itemCount: devices.length,
                                itemBuilder: (context, index) {
                                  final device = devices[index];
                                  return DeviceListTile(
                                    device: device,
                                    onTap: () async {
                                      Navigator.of(dialogContext).pop();
                                      await vm.onTapDevice(context, device);
                                    },
                                  );
                                },
                              ),
                      ),
                      if (devices.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                          child: SizedBox(
                            width: double.infinity,
                            child: TextButton(
                              onPressed: () async {
                                Navigator.of(dialogContext).pop();
                                await vm.onTapAddress(context);
                              },
                              child: const Text('Enter device address'),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedFiles = context.watch(selectedSendingFilesProvider);
    final sessions = context.watch(sendProvider);
    final transferInProgress = sessions.values.any((session) => session.status == SessionStatus.sending);
    final colors = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 68),
            child: const SendTab(),
          ),
        ),
        Positioned(
          bottom: 10,
          left: 16,
          right: 16,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Row(
                children: [
                  Expanded(
                    child: AnimatedPress(
                      child: FilledButton.icon(
                        onPressed: _startSend,
                        icon: const Icon(Icons.send),
                        label: const Text('Send'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton.filledTonal(
                    tooltip: PairingStrings.pairFiles,
                    onPressed: () async => context.push(() => const PairingPage()),
                    icon: const Icon(Icons.qr_code_2),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: AnimatedPress(
                      child: FilledButton.tonalIcon(
                        onPressed: () => showReceivePairingDialog(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: colors.secondaryContainer,
                          foregroundColor: colors.onSecondaryContainer,
                        ),
                        icon: const Icon(Icons.download),
                        label: const Text('Receive'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (selectedFiles.isNotEmpty)
          Positioned(
            right: 16,
            bottom: 66,
            child: ElevatedGlass(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              radius: glassRadiusPill,
              blur: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (transferInProgress) ...[
                    SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text('${selectedFiles.length} selected', style: Theme.of(context).textTheme.labelLarge),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
