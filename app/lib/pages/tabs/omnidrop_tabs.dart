import 'package:flutter/material.dart';
import 'package:localsend_app/pages/web_share_page.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/provider/receive_history_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/native/file_picker.dart';
import 'package:localsend_app/widget/dialogs/add_file_dialog.dart';
import 'package:localsend_isolates/util/file_size_helper.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

class WebDropTab extends StatelessWidget {
  const WebDropTab({super.key});

  @override
  Widget build(BuildContext context) {
    final files = context.watch(selectedSendingFilesProvider);
    final ref = context.ref;
    final colors = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 76),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('WebDrop', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text('Share files with a browser or receive files from one.', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 20),
                Card(
                  color: colors.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Staged files', style: Theme.of(context).textTheme.titleMedium),
                        if (files.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text('No files selected', style: Theme.of(context).textTheme.bodyMedium),
                          )
                        else ...[
                          const SizedBox(height: 8),
                          ...files.map(
                            (file) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.insert_drive_file_outlined),
                              title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(file.size.asReadableFileSize),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () async {
                                final options = FilePickerOption.getOptionsForPlatform();
                                if (options.length == 1) {
                                  await ref.global.dispatchAsync(PickFileAction(option: options.first, context: context));
                                } else {
                                  await AddFileDialog.open(context: context, options: options);
                                }
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('Add/select files'),
                            ),
                            TextButton.icon(
                              onPressed: files.isEmpty ? null : () => ref.redux(selectedSendingFilesProvider).dispatch(ClearSelectionAction()),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Clear staged files'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          bottom: 10,
          left: 0,
          right: 0,
          child: Center(
            child: FilledButton.icon(
              onPressed: () async => await context.push(() => files.isEmpty ? const WebSharePage() : WebSharePage(files: files)),
              icon: const Icon(Icons.language),
              label: const Text('Start WebDrop'),
            ),
          ),
        ),
      ],
    );
  }
}

enum _Platform {
  android('Android', Icons.android),
  ios('iOS', Icons.phone_iphone),
  macos('macOS', Icons.laptop_mac),
  windows('Windows', Icons.desktop_windows),
  linux('Linux', Icons.computer);

  const _Platform(this.label, this.icon);

  final String label;
  final IconData icon;
}

class OsPairsTab extends StatelessWidget {
  const OsPairsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final pairs = [
      for (var left = 0; left < _Platform.values.length; left++)
        for (var right = left + 1; right < _Platform.values.length; right++)
          (_Platform.values[left], _Platform.values[right]),
    ];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('OS Pairs', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth > 760 ? 3 : constraints.maxWidth > 480 ? 2 : 1;
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: pairs.map((pair) {
                return SizedBox(
                  width: width,
                  child: Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(5),
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text('${pair.$1.label} to ${pair.$2.label}'),
                          content: const Text(
                            'Open OmniDrop on both devices. On the sender, choose files in Transfer and select the receiving device. '
                            'For browser-based transfers, start WebDrop on one device and open its link on the other.',
                          ),
                          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(pair.$1.icon),
                            const SizedBox(width: 10),
                            const Icon(Icons.sync_alt),
                            const SizedBox(width: 10),
                            Expanded(child: Text('${pair.$1.label} to ${pair.$2.label}')),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

class CloudTab extends StatelessWidget {
  const CloudTab({super.key});

  @override
  Widget build(BuildContext context) => const Center(child: Text('Cloud transfer - coming soon'));
}

const _profileAvatars = [Icons.person, Icons.face, Icons.account_circle, Icons.pets, Icons.rocket_launch, Icons.bolt];

class MeTab extends StatefulWidget {
  const MeTab({super.key});

  @override
  State<MeTab> createState() => _MeTabState();
}

class _MeTabState extends State<MeTab> with Refena {
  late int _avatarIndex = ref.read(persistenceProvider).getProfileAvatar() % _profileAvatars.length;

  Future<void> _editAvatar() async {
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose avatar'),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              children: [
                for (var i = 0; i < _profileAvatars.length; i++)
                  IconButton(onPressed: () => Navigator.pop(context, i), icon: Icon(_profileAvatars[i], size: 32)),
              ],
            ),
          ),
        ],
      ),
    );
    if (selected == null) return;
    await ref.read(persistenceProvider).setProfileAvatar(selected);
    if (mounted) setState(() => _avatarIndex = selected);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch(settingsProvider);
    final history = context.watch(receiveHistoryProvider);
    final totalReceived = history.fold<int>(0, (total, entry) => total + entry.fileSize);
    final uniqueSenders = history.map((entry) => entry.senderAlias).toSet().length;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(child: Text('Me', style: Theme.of(context).textTheme.headlineSmall)),
        const SizedBox(height: 20),
        Center(
          child: InkWell(
            onTap: _editAvatar,
            borderRadius: BorderRadius.circular(60),
            child: CircleAvatar(radius: 44, child: Icon(_profileAvatars[_avatarIndex], size: 42)),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: settings.alias,
          textAlign: TextAlign.center,
          decoration: const InputDecoration(labelText: 'Device name'),
          onChanged: (value) async => await ref.notifier(settingsProvider).setAlias(value),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 126,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _ProfileMetric(label: 'Total sent', value: 'Not tracked'),
              _ProfileMetric(label: 'Total received', value: totalReceived.asReadableFileSize),
              _ProfileMetric(label: 'Unique senders (by name)', value: '$uniqueSenders recorded'),
              _ProfileMetric(label: 'Total data transferred', value: '${totalReceived.asReadableFileSize} received'),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileMetric extends StatelessWidget {
  final String label;
  final String value;

  const _ProfileMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(right: 10),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    child: SizedBox(
      width: 175,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text(value, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleSmall),
          ],
        ),
      ),
    ),
  );
}