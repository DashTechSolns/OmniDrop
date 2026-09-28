import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/config/init.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/assets.gen.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/home_page_controller.dart';
import 'package:localsend_app/pages/omnidrop_drawer.dart';
import 'package:localsend_app/pages/tabs/omnidrop_tabs.dart';
import 'package:localsend_app/pages/tabs/receive_tab.dart';
import 'package:localsend_app/pages/tabs/send_tab.dart';
import 'package:localsend_app/pages/tabs/settings_tab.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/util/native/cross_file_converters.dart';
import 'package:localsend_app/widget/responsive_builder.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

enum HomeTab {
  webDrop(Icons.language),
  osPairs(Icons.devices),
  send(Icons.send),
  cloud(Icons.cloud_outlined),
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
      case HomeTab.cloud:
        return 'Cloud';
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
          return Scaffold(
            key: _scaffoldKey,
            drawer: const OmniDropDrawer(),
            appBar: AppBar(
              automaticallyImplyLeading: false,
              title: Row(
                children: [
                  ColorFiltered(
                    colorFilter: ColorFilter.mode(Theme.of(context).colorScheme.primary, BlendMode.srcATop),
                    child: Assets.img.logo512.image(width: 32, height: 32),
                  ),
                  const SizedBox(width: 8),
                  const Text('OmniDrop'),
                  IconButton(
                    tooltip: 'Open menu',
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                    icon: const Icon(Icons.more_vert),
                  ),
                ],
              ),
              actions: [
                PopupMenuButton<String>(
                  icon: const Icon(Icons.menu),
                  onSelected: (value) async {
                    if (value == 'scan') {
                      await showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Scan Connect'),
                          content: const Text('QR scanning is not available on this build.'),
                          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
                        ),
                      );
                    } else if (value == 'share') {
                      await showModalBottomSheet<void>(
                        context: context,
                        builder: (context) => SafeArea(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                title: const Text('Nearby devices'),
                                onTap: () {
                                  Navigator.pop(context);
                                  vm.changeTab(HomeTab.send);
                                },
                              ),
                              ListTile(
                                title: const Text('WebDrop'),
                                onTap: () {
                                  Navigator.pop(context);
                                  vm.changeTab(HomeTab.webDrop);
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    } else {
                      await showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Device migration'),
                          content: const Text('Device migration - coming soon'),
                          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
                        ),
                      );
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'scan', child: Text('Scan Connect')),
                    PopupMenuItem(value: 'share', child: Text('Share OmniDrop')),
                    PopupMenuItem(value: 'migration', child: Text('Copy Phone')),
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
            body: Row(
              children: [
                if (!sizingInformation.isMobile)
                  NavigationRail(
                    selectedIndex: vm.currentTab.index,
                    onDestinationSelected: (index) => vm.changeTab(HomeTab.values[index]),
                    extended: sizingInformation.isDesktop,
                    backgroundColor: Theme.of(context).cardColorWithElevation,
                    destinations: HomeTab.values.map((tab) {
                      return NavigationRailDestination(
                        icon: Icon(tab.icon),
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
                          children: const [
                            WebDropTab(),
                            OsPairsTab(),
                            _TransferTab(),
                            CloudTab(),
                            MeTab(),
                          ],
                        ),
                        if (_dragAndDropIndicator)
                          Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Theme.of(context).scaffoldBackgroundColor,
                            ),
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
            bottomNavigationBar: sizingInformation.isMobile
                ? SafeArea(
                    top: false,
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
                                  child: Icon(tab.icon),
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
                                  Icon(tab.icon, color: selected ? Theme.of(context).colorScheme.primary : null),
                                  Text(tab.label, style: Theme.of(context).textTheme.labelSmall),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
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

class _TransferTab extends StatelessWidget {
  const _TransferTab();

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Column(
      children: [
        const TabBar(tabs: [Tab(text: 'Send'), Tab(text: 'Receive')]),
        const Expanded(child: TabBarView(children: [SendTab(), ReceiveTab()])),
      ],
    ),
  );
}
