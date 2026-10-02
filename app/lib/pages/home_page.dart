import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/config/init.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/home_page_controller.dart';
import 'package:localsend_app/pages/copy_phone_page.dart';
import 'package:localsend_app/pages/omnidrop_drawer.dart';
import 'package:localsend_app/pages/tabs/omnidrop_tabs.dart';
import 'package:localsend_app/pages/tabs/send_tab.dart';
import 'package:localsend_app/pages/tabs/settings_tab.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/pages/tabs/send_tab_vm.dart';
import 'package:localsend_app/util/native/cross_file_converters.dart';
import 'package:localsend_app/util/native/channel/android_channel.dart' as android_channel;
import 'package:localsend_app/util/native/file_picker.dart';
import 'package:localsend_app/widget/dialogs/add_file_dialog.dart';
import 'package:localsend_app/widget/dialogs/receive_pairing_dialog.dart';
import 'package:localsend_app/widget/animated_press.dart';
import 'package:localsend_app/widget/omnidrop_logo.dart';
import 'package:localsend_app/widget/glass/glass_card.dart';
import 'package:localsend_app/widget/list_tile/device_list_tile.dart';
import 'package:localsend_app/widget/responsive_builder.dart';
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
          return Scaffold(
            key: _scaffoldKey,
            drawer: const OmniDropDrawer(),
            appBar: AppBar(
              automaticallyImplyLeading: false,
              backgroundColor: Colors.transparent,
              flexibleSpace: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      colors.primary.withValues(alpha: 0.16),
                      colors.secondary.withValues(alpha: 0.08),
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
                  onPressed: () async => await context.push(
                    () => Scaffold(
                      appBar: AppBar(title: const Text('Settings')),
                      body: const SettingsTab(),
                    ),
                  ),
                  icon: const Icon(Icons.settings_outlined),
                ),
              ],
            ),
            body: Stack(
              fit: StackFit.expand,
              children: [
                IgnorePointer(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(-0.85, -0.8),
                            radius: 1.0,
                            colors: [colors.primary.withValues(alpha: 0.08), Colors.transparent],
                          ),
                        ),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(0.9, 0.9),
                            radius: 1.0,
                            colors: [colors.secondary.withValues(alpha: 0.07), Colors.transparent],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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

class _TransferTab extends StatefulWidget {
  const _TransferTab({super.key});

  @override
  State<_TransferTab> createState() => _TransferTabState();
}

class _TransferTabState extends State<_TransferTab> with Refena {
  late final StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    final connectivity = Connectivity();
    connectivity.checkConnectivity().then(_updateConnectivity);
    _connectivitySubscription = connectivity.onConnectivityChanged.listen(_updateConnectivity);
  }

  void _updateConnectivity(List<ConnectivityResult> results) {
    final hasLocalNetwork = results.any((result) => result == ConnectivityResult.wifi || result == ConnectivityResult.ethernet);
    final offline = !hasLocalNetwork;
    if (mounted && offline != _offline) setState(() => _offline = offline);
  }

  @override
  void dispose() {
    unawaited(_connectivitySubscription.cancel());
    super.dispose();
  }

  Future<void> _startSend() async {
    if (_offline) return;
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
          return AlertDialog(
            title: const Text('Choose a device'),
            content: SizedBox(
              width: 420,
              child: vm.nearbyDevices.isEmpty
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('No nearby devices found.'),
                        TextButton(
                          onPressed: () async {
                            Navigator.of(dialogContext).pop();
                            await vm.onTapAddress(context);
                          },
                          child: const Text('Enter device address'),
                        ),
                      ],
                    )
                  : SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final device in vm.nearbyDevices)
                            DeviceListTile(
                              device: device,
                              onTap: () async {
                                Navigator.of(dialogContext).pop();
                                await vm.onTapDevice(context, device);
                              },
                            ),
                        ],
                      ),
                    ),
            ),
            actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Close'))],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 68),
            child: _offline ? _buildOfflineCard() : const SendTab(),
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
                        onPressed: _offline ? null : _startSend,
                        icon: const Icon(Icons.send),
                        label: const Text('Send'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: AnimatedPress(
                      child: FilledButton.tonalIcon(
                        onPressed: _offline ? null : () => showReceivePairingDialog(context),
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
      ],
    );
  }

  Widget _buildOfflineCard() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 86),
    child: GlassCard(
      margin: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("You're offline. OmniDrop requires a local network connection for device discovery."),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: defaultTargetPlatform == TargetPlatform.android ? () async => android_channel.openWifiSettingsAndroid() : null,
            icon: const Icon(Icons.wifi),
            label: const Text('Open Wi-Fi Settings'),
          ),
          const SizedBox(height: 16),
          const Text('1. Turn on Wi-Fi or connect to the other device\'s hotspot.'),
          const SizedBox(height: 8),
          const Text('2. Return to OmniDrop.'),
          const SizedBox(height: 8),
          const Text('3. Tap Send or Receive.'),
        ],
      ),
    ),
  );
}
