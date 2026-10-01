import 'package:device_apps/device_apps.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/config/theme.dart';
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
  final Set<String> _selectedAssets = {};
  final Set<String> _selectedTreeFiles = {};
  final Set<String> _selectedTreeFolders = {};
  final Map<String, android_channel.FileInfo> _treeFileEntries = {};
  final List<(String, String)> _treeBreadcrumbs = [];
  String? _treeRootUri;
  String? _currentFolderUri;
  Future<List<android_channel.AndroidBrowseEntry>>? _treeEntriesFuture;
  bool _assetSelectionMode = false;

  @override
  void initState() {
    super.initState();
    _systemFilesFuture = _loadSystemFiles(_category);
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
      _assetsFuture = _loadAssets(category);
    } else if (category == _BrowserCategory.apps) {
      _appsFuture = DeviceApps.getInstalledApplications(includeSystemApps: false, includeAppIcons: true);
    } else if (category == _BrowserCategory.downloads || category == _BrowserCategory.documents) {
      _systemFilesFuture = _loadSystemFiles(category);
    }
  }

  Future<List<android_channel.FileInfo>> _loadSystemFiles(_BrowserCategory category) async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android && (ref.read(deviceInfoProvider).androidSdkInt ?? 0) <= 32) {
        final permission = await Permission.storage.request();
        if (!permission.isGranted) return [];
      }
      return await android_channel.queryMediaFilesAndroid(category: category.name);
    } catch (_) {
      return [];
    }
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

  Future<void> _stageApp(Application app) async {
    await ref
        .redux(selectedSendingFilesProvider)
        .dispatchAsync(
          AddFilesAction<Application>(
            files: [app],
            converter: CrossFileConverters.convertApplication,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final selectedFiles = context.watch(selectedSendingFilesProvider);
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
        if (selectedFiles.isNotEmpty)
          ElevatedGlass(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            radius: glassRadiusCard,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${selectedFiles.length} selected · ${selectedFiles.fold<int>(0, (total, file) => total + file.size).asReadableFileSize}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () => ref.redux(selectedSendingFilesProvider).dispatch(ClearSelectionAction()),
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCategoryBody() => switch (_category) {
    _BrowserCategory.images || _BrowserCategory.videos || _BrowserCategory.audio => _buildMediaBrowser(),
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
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async => _stageAssets(assets),
                icon: const Icon(Icons.select_all),
                label: const Text('Select all'),
              ),
            ),
            Expanded(
              child: _category == _BrowserCategory.audio
                  ? ListView.builder(
                      itemCount: assets.length,
                      itemBuilder: (context, index) {
                        final asset = assets[index];
                        final selected = _selectedAssets.contains(asset.id);
                        return ListTile(
                          leading: const Icon(Icons.audio_file_outlined),
                          title: FutureBuilder<String>(
                            future: asset.titleAsync,
                            builder: (context, title) => Text(title.data ?? 'Audio file', maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                          trailing: Icon(selected ? Icons.check_circle : Icons.add_circle_outline, color: selected ? glassCyanBright : null),
                          onLongPress: () => setState(() {
                            _assetSelectionMode = true;
                            _selectedAssets.add(asset.id);
                          }),
                          onTap: () async {
                            if (_assetSelectionMode) {
                              setState(() => selected ? _selectedAssets.remove(asset.id) : _selectedAssets.add(asset.id));
                            } else {
                              await _stageAssets([asset]);
                            }
                          },
                        );
                      },
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(8),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 6,
                        mainAxisSpacing: 6,
                      ),
                      itemCount: assets.length,
                      itemBuilder: (context, index) {
                        final asset = assets[index];
                        final selected = _selectedAssets.contains(asset.id);
                        return GestureDetector(
                          onLongPress: () => setState(() {
                            _assetSelectionMode = true;
                            _selectedAssets.add(asset.id);
                          }),
                          onTap: () async {
                            if (_assetSelectionMode) {
                              setState(() => selected ? _selectedAssets.remove(asset.id) : _selectedAssets.add(asset.id));
                            } else {
                              await _stageAssets([asset]);
                            }
                          },
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(glassRadiusSmall),
                                child: AssetEntityImage(asset, isOriginal: false, thumbnailSize: const ThumbnailSize.square(240), fit: BoxFit.cover),
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
        return ListView.builder(
          itemCount: apps.length,
          itemBuilder: (context, index) {
            final app = apps[index];
            return ListTile(
              leading: app is ApplicationWithIcon ? Image.memory(app.icon, width: 40, height: 40) : const Icon(Icons.android),
              title: Text(app.appName, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(app.packageName, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.add),
              onTap: () => _stageApp(app),
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
        FilledButton.icon(
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
            final uri = await android_channel.pickFolderTreeAndroid();
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
          return _emptyState(icon: Icons.folder_off_outlined, message: 'Folder access is unavailable.', action: _grantFolderAccessButton());
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
                        final selected = entry.isDirectory ? _selectedTreeFolders.contains(entry.uri) : _selectedTreeFiles.contains(entry.uri);
                        return ListTile(
                          leading: Icon(entry.isDirectory ? Icons.folder_outlined : Icons.insert_drive_file_outlined),
                          title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: entry.isDirectory ? null : Text(entry.size.asReadableFileSize),
                          trailing: Checkbox(
                            value: selected,
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
                              : () => setState(() {
                                  if (selected) {
                                    _selectedTreeFiles.remove(entry.uri);
                                    _treeFileEntries.remove(entry.uri);
                                  } else {
                                    _selectedTreeFiles.add(entry.uri);
                                    _treeFileEntries[entry.uri] = android_channel.FileInfo(
                                      name: entry.name,
                                      size: entry.size,
                                      uri: entry.uri,
                                      lastModified: entry.lastModified,
                                    );
                                  }
                                }),
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
      final uri = await android_channel.pickFolderTreeAndroid();
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
            return ListTile(
              leading: Icon(_category == _BrowserCategory.documents ? Icons.description_outlined : Icons.download_outlined),
              title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${file.size.asReadableFileSize}${file.lastModified == null ? '' : ' · ${file.lastModified}'}'),
              onTap: () async => ref
                  .redux(selectedSendingFilesProvider)
                  .dispatchAsync(
                    AddFilesAction<android_channel.FileInfo>(
                      files: [file],
                      converter: CrossFileConverters.convertFileInfo,
                    ),
                  ),
            );
          },
        );
      },
    );
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