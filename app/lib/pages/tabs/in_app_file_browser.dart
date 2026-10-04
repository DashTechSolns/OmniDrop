import 'dart:typed_data';

import 'package:device_apps/device_apps.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/util/native/channel/android_channel.dart' as android_channel;
import 'package:localsend_app/util/native/cross_file_converters.dart';
import 'package:localsend_app/widget/glass/glass_card.dart';
import 'package:localsend_isolates/util/file_size_helper.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

enum _BrowserCategory { downloads, apps, images, videos, audio, documents, text, files }

extension on _BrowserCategory {
  String get label => switch (this) {
    _BrowserCategory.downloads => 'Downloads',
    _BrowserCategory.apps => 'Apps',
    _BrowserCategory.images => 'Images',
    _BrowserCategory.videos => 'Videos',
    _BrowserCategory.audio => 'Audio',
    _BrowserCategory.documents => 'Documents',
    _BrowserCategory.text => 'Text',
    _BrowserCategory.files => 'Files',
  };

  IconData get icon => switch (this) {
    _BrowserCategory.downloads => Icons.download_outlined,
    _BrowserCategory.apps => Icons.apps_outlined,
    _BrowserCategory.images => Icons.image_outlined,
    _BrowserCategory.videos => Icons.movie_outlined,
    _BrowserCategory.audio => Icons.audio_file_outlined,
    _BrowserCategory.documents => Icons.description_outlined,
    _BrowserCategory.text => Icons.notes_outlined,
    _BrowserCategory.files => Icons.folder_outlined,
  };
}

class InAppFileBrowser extends StatefulWidget {
  const InAppFileBrowser({super.key});

  @override
  State<InAppFileBrowser> createState() => _InAppFileBrowserState();
}

class _InAppFileBrowserState extends State<InAppFileBrowser> with Refena {
  _BrowserCategory _category = _BrowserCategory.downloads;
  final _textController = TextEditingController();
  Future<List<AssetEntity>>? _assetsFuture;
  Future<List<Application>>? _appsFuture;
  Future<List<android_channel.FileInfo>>? _systemFilesFuture;
  final Map<String, Future<Uint8List?>> _thumbnailFutures = {};
  final Set<String> _selectedAssets = {};
  final Set<String> _selectedTreeFiles = {};
  final Set<String> _selectedTreeFolders = {};
  final Map<String, android_channel.FileInfo> _treeFileEntries = {};
  final List<(String, String)> _treeBreadcrumbs = [];
  String? _treeRootUri;
  String? _currentFolderUri;
  Future<List<android_channel.AndroidBrowseEntry>>? _treeEntriesFuture;
  bool _assetSelectionMode = false;
  String _saveLocation = 'internal';

  @override
  void initState() {
    super.initState();
    _systemFilesFuture = Future.value([]);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeStorageTree());
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _openCategory(_BrowserCategory category) async {
    setState(() {
      _category = category;
      _assetSelectionMode = false;
      _selectedAssets.clear();
    });
    if (category == _BrowserCategory.images || category == _BrowserCategory.videos || category == _BrowserCategory.audio) {
      if (defaultTargetPlatform == TargetPlatform.android) {
        _systemFilesFuture = _loadSystemFiles(category);
      } else {
        _assetsFuture = _loadAssets(category);
      }
    } else if (category == _BrowserCategory.apps) {
      _appsFuture = DeviceApps.getInstalledApplications(includeSystemApps: false, includeAppIcons: true);
    } else if (category == _BrowserCategory.downloads || category == _BrowserCategory.documents) {
      _systemFilesFuture = _loadSystemFiles(category);
    }
  }

  Future<List<android_channel.FileInfo>> _loadSystemFiles(_BrowserCategory category) async {
    try {
      if (defaultTargetPlatform != TargetPlatform.android) return [];
      if ((ref.read(deviceInfoProvider).androidSdkInt ?? 0) <= 32) {
        if (!await Permission.storage.request().then((permission) => permission.isGranted)) return [];
      } else if (category == _BrowserCategory.images || category == _BrowserCategory.videos || category == _BrowserCategory.audio) {
        final type = switch (category) {
          _BrowserCategory.images => RequestType.image,
          _BrowserCategory.videos => RequestType.video,
          _BrowserCategory.audio => RequestType.audio,
          _ => RequestType.common,
        };
        final permission = await PhotoManager.requestPermissionExtend(
          requestOption: PermissionRequestOption(androidPermission: AndroidPermission(type: type, mediaLocation: false)),
        );
        if (!permission.isAuth) return [];
      }
      return await android_channel.queryMediaFilesAndroid(category: category.name);
    } catch (_) {
      return [];
    }
  }

  Future<void> _initializeStorageTree() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    String? uri;
    try {
      _saveLocation = await android_channel.getSaveLocationAndroid();
      uri = await android_channel.getStorageTreeAndroid(storage: _saveLocation) ??
          await android_channel.pickStorageTreeAndroid(storage: _saveLocation);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      if (uri != null) {
        _treeRootUri = uri;
        _currentFolderUri = uri;
        _treeEntriesFuture = android_channel.listFolderTreeAndroid(uri: uri);
      }
      _systemFilesFuture = _loadSystemFiles(_category);
    });
  }

  Future<List<AssetEntity>> _loadAssets(_BrowserCategory category) async {
    final type = switch (category) {
      _BrowserCategory.images => RequestType.image,
      _BrowserCategory.videos => RequestType.video,
      _BrowserCategory.audio => RequestType.audio,
      _ => RequestType.common,
    };
    final permission = await PhotoManager.requestPermissionExtend(
      requestOption: PermissionRequestOption(
        androidPermission: AndroidPermission(type: type, mediaLocation: false),
      ),
    );
    if (!permission.isAuth) return [];
    final albums = await PhotoManager.getAssetPathList(type: type);
    if (albums.isEmpty) return [];
    final assets = <AssetEntity>[];
    for (var page = 0; ; page++) {
      final batch = await albums.first.getAssetListPaged(page: page, size: 500);
      if (batch.isEmpty) break;
      assets.addAll(batch);
      if (batch.length < 500) break;
    }
    return assets;
  }

  Future<void> _stageAssets(Iterable<AssetEntity> assets) async {
    await ref
        .redux(selectedSendingFilesProvider)
        .dispatchAsync(
          AddFilesAction<AssetEntity>(
            files: assets,
            converter: CrossFileConverters.convertAssetEntity,
          ),
        );
  }

  Future<void> _toggleApp(Application app) async {
    await _toggleFile(await CrossFileConverters.convertApplication(app));
  }

  Future<void> _toggleAsset(AssetEntity asset) async {
    await _toggleFile(await CrossFileConverters.convertAssetEntity(asset));
  }

  Future<void> _toggleSystemFile(android_channel.FileInfo file) async {
    await _toggleFile(await CrossFileConverters.convertFileInfo(file));
  }

  Future<void> _toggleFile(CrossFile file) async {
    final selection = ref.read(selectedSendingFilesProvider);
    final selectedIndex = selection.indexWhere((selected) => selected.isSameFile(otherFile: file));
    if (selectedIndex >= 0) {
      ref.redux(selectedSendingFilesProvider).dispatch(RemoveSelectedFileAction(selectedIndex));
    } else {
      await ref
          .redux(selectedSendingFilesProvider)
          .dispatchAsync(
            AddFilesAction<CrossFile>(
              files: [file],
              converter: (file) async => file,
            ),
          );
    }
  }

  bool _isAssetSelected(AssetEntity asset) =>
      ref.read(selectedSendingFilesProvider).any((file) => file.asset?.id == asset.id);

  bool _isPathSelected(String path) => ref.read(selectedSendingFilesProvider).any((file) => file.path == path);

  bool _isSystemFileSelected(android_channel.FileInfo file) => _isPathSelected(file.uri);

  Color _selectedColor(BuildContext context) => Theme.of(context).colorScheme.primary.withValues(alpha: 0.16);

  @override
  Widget build(BuildContext context) {
    context.watch(selectedSendingFilesProvider);
    final categories = _BrowserCategory.values;
    return Column(
      children: [
        SizedBox(
          height: 54,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            itemCount: categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final category = categories[index];
              return ChoiceChip(
                avatar: Icon(category.icon, size: 17),
                label: Text(category.label),
                selected: _category == category,
                onSelected: (_) => _openCategory(category),
              );
            },
          ),
        ),
        Expanded(
          child: GlassCard(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            padding: EdgeInsets.zero,
            child: _buildCategoryBody(),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryBody() => switch (_category) {
    _BrowserCategory.images || _BrowserCategory.videos || _BrowserCategory.audio =>
      defaultTargetPlatform == TargetPlatform.android ? _buildAndroidMediaBrowser() : _buildMediaBrowser(),
    _BrowserCategory.apps => _buildAppsBrowser(),
    _BrowserCategory.text => _buildTextComposer(),
    _BrowserCategory.files => _buildFilesBrowser(),
    _BrowserCategory.downloads || _BrowserCategory.documents => _buildSystemFileBrowser(),
  };

  Widget _buildMediaBrowser() {
    final future = _assetsFuture;
    if (future == null) return const Center(child: Text('Open this category to browse media.'));
    return FutureBuilder<List<AssetEntity>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        final assets = snapshot.data ?? [];
        if (assets.isEmpty) {
          return _emptyState(
            icon: _category.icon,
            message: 'No ${_category.label.toLowerCase()} found or access was not granted.',
            action: TextButton.icon(
              onPressed: () => setState(() => _assetsFuture = _loadAssets(_category)),
              icon: const Icon(Icons.refresh),
              label: const Text('Check access'),
            ),
          );
        }
        return Column(
          children: [
            Align(
              alignment: Alignment.center,
              child: TextButton.icon(
                onPressed: () async => _stageAssets(assets),
                icon: const Icon(Icons.select_all),
                label: const Text('Select all'),
              ),
            ),
            Expanded(
              child: _category == _BrowserCategory.audio || _category == _BrowserCategory.videos
                  ? ListView.builder(
                      itemCount: assets.length,
                      itemBuilder: (context, index) {
                        final asset = assets[index];
                        final selected = _isAssetSelected(asset) || _selectedAssets.contains(asset.id);
                        return ListTile(
                          selected: selected,
                          selectedTileColor: _selectedColor(context),
                          leading: _category == _BrowserCategory.audio
                              ? const Icon(Icons.audio_file_outlined)
                              : SizedBox(
                                  width: 64,
                                  height: 48,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(glassRadiusSmall),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        AssetEntityImage(
                                          asset,
                                          isOriginal: false,
                                          thumbnailSize: const ThumbnailSize.square(240),
                                          fit: BoxFit.cover,
                                        ),
                                        const Center(child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 26)),
                                      ],
                                    ),
                                  ),
                                ),
                          title: FutureBuilder<String>(
                            future: asset.titleAsync,
                            builder: (context, title) => Text(
                              title.data ?? (_category == _BrowserCategory.videos ? 'Video file' : 'Audio file'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          trailing: Icon(selected ? Icons.check_circle : Icons.add_circle_outline, color: selected ? glassCyanBright : null),
                          onLongPress: () => setState(() {
                            _assetSelectionMode = true;
                            _selectedAssets.add(asset.id);
                          }),
                          onTap: () async {
                            final pendingSelection = _selectedAssets.contains(asset.id);
                            final staged = _isAssetSelected(asset);
                            if (_assetSelectionMode && staged) {
                              setState(() => _selectedAssets.remove(asset.id));
                              await _toggleAsset(asset);
                            } else if (_assetSelectionMode) {
                              setState(() {
                                if (pendingSelection) {
                                  _selectedAssets.remove(asset.id);
                                } else {
                                  _selectedAssets.add(asset.id);
                                }
                              });
                            } else {
                              await _toggleAsset(asset);
                            }
                          },
                        );
                      },
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(6),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 150,
                        crossAxisSpacing: 4,
                        mainAxisSpacing: 4,
                      ),
                      itemCount: assets.length,
                      itemBuilder: (context, index) {
                        final asset = assets[index];
                        final pendingSelection = _selectedAssets.contains(asset.id);
                        final staged = _isAssetSelected(asset);
                        final selected = staged || pendingSelection;
                        return GestureDetector(
                          onLongPress: () => setState(() {
                            _assetSelectionMode = true;
                            _selectedAssets.add(asset.id);
                          }),
                          onTap: () async {
                            if (_assetSelectionMode && staged) {
                              setState(() => _selectedAssets.remove(asset.id));
                              await _toggleAsset(asset);
                            } else if (_assetSelectionMode) {
                              setState(() {
                                if (pendingSelection) {
                                  _selectedAssets.remove(asset.id);
                                } else {
                                  _selectedAssets.add(asset.id);
                                }
                              });
                            } else {
                              await _toggleAsset(asset);
                            }
                          },
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(glassRadiusSmall),
                                child: AssetEntityImage(
                                  asset,
                                  isOriginal: false,
                                  thumbnailSize: const ThumbnailSize.square(240),
                                  fit: BoxFit.cover,
                                ),
                              ),
                              if (selected)
                                Positioned.fill(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.20),
                                      border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
                                      borderRadius: BorderRadius.circular(glassRadiusSmall),
                                    ),
                                  ),
                                ),
                              if (selected)
                                const Align(
                                  alignment: Alignment.topRight,
                                  child: Padding(
                                    padding: EdgeInsets.all(5),
                                    child: Icon(Icons.check_circle, color: glassCyanBright),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            if (_assetSelectionMode && _selectedAssets.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8),
                child: FilledButton.icon(
                  onPressed: () async {
                    await _stageAssets(assets.where((asset) => _selectedAssets.contains(asset.id)));
                    setState(() {
                      _selectedAssets.clear();
                      _assetSelectionMode = false;
                    });
                  },
                  icon: const Icon(Icons.add),
                  label: Text('Add ${_selectedAssets.length}'),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildAppsBrowser() {
    final future = _appsFuture;
    if (future == null) return const Center(child: Text('Open this category to browse installed apps.'));
    return FutureBuilder<List<Application>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        final apps = snapshot.data ?? [];
        if (apps.isEmpty) return _emptyState(icon: Icons.apps_outlined, message: 'No user apps are available.');
        return GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 128,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 0.76,
          ),
          itemCount: apps.length,
          itemBuilder: (context, index) {
            final app = apps[index];
            final selected = _isPathSelected(app.apkFilePath);
            return Material(
              color: selected ? _selectedColor(context) : Colors.transparent,
              borderRadius: BorderRadius.circular(glassRadiusSmall),
              child: InkWell(
                borderRadius: BorderRadius.circular(glassRadiusSmall),
                onTap: () => _toggleApp(app),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox.square(
                            dimension: 52,
                            child: app is ApplicationWithIcon
                                ? Image.memory(app.icon, fit: BoxFit.contain)
                                : const Icon(Icons.android, size: 44),
                          ),
                          const SizedBox(height: 7),
                          Text(app.appName, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                    if (selected)
                      const Positioned(top: 3, right: 3, child: Icon(Icons.check_circle, size: 19)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTextComposer() => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _textController,
          minLines: 5,
          maxLines: 12,
          decoration: const InputDecoration(labelText: 'Text to send', alignLabelWithHint: true),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.center,
          child: FilledButton.icon(
            onPressed: () {
              final text = _textController.text;
              if (text.isNotEmpty) {
                ref.redux(selectedSendingFilesProvider).dispatch(AddMessageAction(message: text));
                _textController.clear();
              }
            },
            icon: const Icon(Icons.add),
            label: const Text('Add text'),
          ),
        ),
      ],
    ),
  );

  Widget _buildFilesBrowser() {
    final folderUri = _currentFolderUri;
    if (folderUri == null) {
      return _emptyState(
        icon: Icons.folder_open_outlined,
        message: 'Choose a folder once to grant persistent access to its contents.',
        action: FilledButton.icon(
          onPressed: () async {
            final uri = await android_channel.pickStorageTreeAndroid(storage: _saveLocation);
            if (!mounted || uri == null) return;
            setState(() {
              _treeRootUri = uri;
              _currentFolderUri = uri;
              _treeBreadcrumbs.clear();
              _treeEntriesFuture = android_channel.listFolderTreeAndroid(uri: uri);
            });
          },
          icon: const Icon(Icons.folder_open),
          label: const Text('Grant access'),
        ),
      );
    }

    final future = _treeEntriesFuture ??= android_channel.listFolderTreeAndroid(uri: folderUri);
    return FutureBuilder<List<android_channel.AndroidBrowseEntry>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        final entries = [...?snapshot.data]..sort((a, b) {
          if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        if (snapshot.hasError) {
          return _emptyState(
            icon: Icons.folder_off_outlined,
            message: "Couldn't read this folder.\n${snapshot.error}",
            action: TextButton.icon(
              onPressed: () => setState(() => _treeEntriesFuture = android_channel.listFolderTreeAndroid(uri: folderUri)),
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          );
        }
        return Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Back to parent folder',
                  onPressed: _treeBreadcrumbs.isEmpty
                      ? null
                      : () {
                          setState(() {
                            _treeBreadcrumbs.removeLast();
                            _currentFolderUri = _treeBreadcrumbs.isEmpty ? _treeRootUri : _treeBreadcrumbs.last.$2;
                            _treeEntriesFuture = android_channel.listFolderTreeAndroid(uri: _currentFolderUri!);
                          });
                        },
                  icon: const Icon(Icons.arrow_back),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _treeBreadcrumbs.clear();
                              _currentFolderUri = _treeRootUri;
                              _treeEntriesFuture = android_channel.listFolderTreeAndroid(uri: _treeRootUri!);
                            });
                          },
                          child: const Text('Folder'),
                        ),
                        for (var index = 0; index < _treeBreadcrumbs.length; index++)
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _currentFolderUri = _treeBreadcrumbs[index].$2;
                                _treeBreadcrumbs.removeRange(index + 1, _treeBreadcrumbs.length);
                                _treeEntriesFuture = android_channel.listFolderTreeAndroid(uri: _currentFolderUri!);
                              });
                            },
                            child: Text(_treeBreadcrumbs[index].$1),
                          ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Select all files in this folder',
                  onPressed: () async {
                    final files = await android_channel.listFolderTreeFilesAndroid(uri: folderUri);
                    await _stageSystemFiles(files);
                  },
                  icon: const Icon(Icons.select_all),
                ),
              ],
            ),
            Expanded(
              child: entries.isEmpty
                  ? _emptyState(icon: Icons.folder_open_outlined, message: 'This folder is empty.')
                  : ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        final pendingSelection = entry.isDirectory
                            ? _selectedTreeFolders.contains(entry.uri)
                            : _selectedTreeFiles.contains(entry.uri);
                        final staged = !entry.isDirectory && _isPathSelected(entry.uri);
                        final selected = pendingSelection || staged;
                        return ListTile(
                          selected: selected,
                          selectedTileColor: _selectedColor(context),
                          leading: Icon(entry.isDirectory ? Icons.folder_outlined : _fileTypeIcon(entry.name)),
                          title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: entry.isDirectory ? null : Text(entry.size.asReadableFileSize),
                          trailing: Checkbox(
                            value: pendingSelection,
                            onChanged: (value) => setState(() {
                              final selection = entry.isDirectory ? _selectedTreeFolders : _selectedTreeFiles;
                              if (value == true) {
                                selection.add(entry.uri);
                                if (!entry.isDirectory) {
                                  _treeFileEntries[entry.uri] = android_channel.FileInfo(
                                    name: entry.name,
                                    size: entry.size,
                                    uri: entry.uri,
                                    lastModified: entry.lastModified,
                                  );
                                }
                              } else {
                                selection.remove(entry.uri);
                                _treeFileEntries.remove(entry.uri);
                              }
                            }),
                          ),
                          onLongPress: () => setState(() {
                            if (!entry.isDirectory) {
                              _selectedTreeFiles.add(entry.uri);
                              _treeFileEntries[entry.uri] = android_channel.FileInfo(
                                name: entry.name,
                                size: entry.size,
                                uri: entry.uri,
                                lastModified: entry.lastModified,
                              );
                            }
                          }),
                          onTap: entry.isDirectory
                              ? () {
                                  setState(() {
                                    _treeBreadcrumbs.add((entry.name, entry.uri));
                                    _currentFolderUri = entry.uri;
                                    _treeEntriesFuture = android_channel.listFolderTreeAndroid(uri: entry.uri);
                                  });
                                }
                              : () => _toggleSystemFile(
                                  android_channel.FileInfo(
                                    name: entry.name,
                                    size: entry.size,
                                    uri: entry.uri,
                                    lastModified: entry.lastModified,
                                  ),
                                ),
                        );
                      },
                    ),
            ),
            if (_selectedTreeFiles.isNotEmpty || _selectedTreeFolders.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8),
                child: FilledButton.icon(
                  onPressed: _stageTreeSelection,
                  icon: const Icon(Icons.add),
                  label: Text('Add ${_selectedTreeFiles.length + _selectedTreeFolders.length} selected'),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _grantFolderAccessButton() => FilledButton.icon(
    onPressed: () async {
      final uri = await android_channel.pickStorageTreeAndroid(storage: _saveLocation);
      if (!mounted || uri == null) return;
      setState(() {
        _treeRootUri = uri;
        _currentFolderUri = uri;
        _treeEntriesFuture = android_channel.listFolderTreeAndroid(uri: uri);
      });
    },
    icon: const Icon(Icons.folder_open),
    label: const Text('Grant access'),
  );

  Future<void> _stageTreeSelection() async {
    final files = _selectedTreeFiles.map((uri) => _treeFileEntries[uri]).whereType<android_channel.FileInfo>().toList();
    for (final folderUri in _selectedTreeFolders) {
      files.addAll(await android_channel.listFolderTreeFilesAndroid(uri: folderUri));
    }
    await _stageSystemFiles(files);
    if (mounted) {
      setState(() {
        _selectedTreeFiles.clear();
        _selectedTreeFolders.clear();
      });
    }
  }

  Future<void> _stageSystemFiles(List<android_channel.FileInfo> files) async {
    await ref
        .redux(selectedSendingFilesProvider)
        .dispatchAsync(
          AddFilesAction<android_channel.FileInfo>(
            files: files,
            converter: CrossFileConverters.convertFileInfo,
          ),
        );
  }

  Widget _buildSystemFileBrowser() {
    final future = _systemFilesFuture;
    if (future == null) return const Center(child: Text('Open this category to browse device files.'));
    return FutureBuilder<List<android_channel.FileInfo>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        final files = snapshot.data ?? [];
        if (files.isEmpty) {
          return _emptyState(
            icon: _category.icon,
            message: 'No ${_category.label.toLowerCase()} files are available.',
            action: TextButton.icon(
              onPressed: () => setState(() => _systemFilesFuture = _loadSystemFiles(_category)),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          );
        }
        return ListView.builder(
          itemCount: files.length,
          itemBuilder: (context, index) {
            final file = files[index];
            final selected = _isSystemFileSelected(file);
            return ListTile(
              selected: selected,
              selectedTileColor: _selectedColor(context),
              leading: Icon(_fileTypeIcon(file.name)),
              title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${file.size.asReadableFileSize}${file.lastModified == null ? '' : ' · ${file.lastModified}'}'),
              trailing: Icon(selected ? Icons.check_circle : Icons.add_circle_outline),
              onTap: () => _toggleSystemFile(file),
            );
          },
        );
      },
    );
  }

  Widget _buildAndroidMediaBrowser() {
    final future = _systemFilesFuture;
    if (future == null) return const Center(child: Text('Open this category to browse media.'));
    return FutureBuilder<List<android_channel.FileInfo>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        final files = snapshot.data ?? [];
        if (files.isEmpty) {
          return _emptyState(
            icon: _category.icon,
            message: 'No ${_category.label.toLowerCase()} found or access was not granted.',
            action: TextButton.icon(
              onPressed: () => setState(() => _systemFilesFuture = _loadSystemFiles(_category)),
              icon: const Icon(Icons.refresh),
              label: const Text('Check access'),
            ),
          );
        }
        if (_category == _BrowserCategory.audio || _category == _BrowserCategory.videos) {
          return ListView.builder(
            itemCount: files.length,
            itemBuilder: (context, index) {
              final file = files[index];
              final selected = _isSystemFileSelected(file);
              return ListTile(
                selected: selected,
                selectedTileColor: _selectedColor(context),
                leading: SizedBox.square(
                  dimension: 56,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(glassRadiusSmall),
                    child: _category == _BrowserCategory.audio
                        ? _buildMediaThumbnail(file, 'audio', BoxFit.cover, fallback: Icons.music_note)
                        : Stack(
                            fit: StackFit.expand,
                            children: [
                              _buildMediaThumbnail(file, 'videos', BoxFit.cover, fallback: Icons.movie_outlined),
                              const Center(child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 26)),
                            ],
                          ),
                  ),
                ),
                title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(file.size.asReadableFileSize),
                trailing: Icon(selected ? Icons.check_circle : Icons.add_circle_outline, color: selected ? glassCyanBright : null),
                onTap: () => _toggleSystemFile(file),
              );
            },
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(6),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 150,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
          ),
          itemCount: files.length,
          itemBuilder: (context, index) {
            final file = files[index];
            final selected = _isSystemFileSelected(file);
            return GestureDetector(
              onTap: () => _toggleSystemFile(file),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(glassRadiusSmall),
                    child: _buildMediaThumbnail(file, _category.name, BoxFit.cover, fallback: _category.icon),
                  ),
                  if (_category == _BrowserCategory.videos)
                    const Center(child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 30)),
                  if (selected)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.20),
                          border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
                          borderRadius: BorderRadius.circular(glassRadiusSmall),
                        ),
                        child: const Align(
                          alignment: Alignment.topRight,
                          child: Padding(padding: EdgeInsets.all(5), child: Icon(Icons.check_circle)),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMediaThumbnail(android_channel.FileInfo file, String category, BoxFit fit, {required IconData fallback}) {
    final key = '$category:${file.uri}';
    if (!_thumbnailFutures.containsKey(key)) {
      if (_thumbnailFutures.length >= 64) _thumbnailFutures.clear();
      _thumbnailFutures[key] = android_channel.loadMediaThumbnailAndroid(uri: file.uri, category: category);
    }
    return FutureBuilder<Uint8List?>(
      future: _thumbnailFutures[key],
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null) return Image.memory(bytes, fit: fit, gaplessPlayback: true);
        return ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Center(child: Icon(fallback)),
        );
      },
    );
  }

  IconData _fileTypeIcon(String name) {
    final extension = name.split('.').last.toLowerCase();
    return switch (extension) {
      'pdf' => Icons.picture_as_pdf_outlined,
      'doc' || 'docx' || 'odt' => Icons.article_outlined,
      'xls' || 'xlsx' || 'ods' || 'csv' => Icons.table_chart_outlined,
      'zip' || 'rar' || '7z' || 'tar' || 'gz' => Icons.archive_outlined,
      'apk' => Icons.android,
      'txt' || 'md' => Icons.text_snippet_outlined,
      'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' => Icons.image_outlined,
      'mp4' || 'mov' || 'mkv' => Icons.movie_outlined,
      'mp3' || 'm4a' || 'wav' || 'flac' => Icons.audio_file_outlined,
      _ => Icons.description_outlined,
    };
  }

  Widget _emptyState({required IconData icon, required String message, Widget? action}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 12), action],
        ],
      ),
    ),
  );
}