import 'package:flutter/material.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/model/persistence/color_mode.dart';
import 'package:localsend_app/pages/about/about_page.dart';
import 'package:localsend_app/pages/language_page.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/widget/dialogs/custom_color_dialog.dart';
import 'package:localsend_app/widget/glass/glass_card.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';
import 'package:url_launcher/url_launcher.dart';

class OmniDropDrawer extends StatefulWidget {
  const OmniDropDrawer({super.key});

  @override
  State<OmniDropDrawer> createState() => _OmniDropDrawerState();
}

class _OmniDropDrawerState extends State<OmniDropDrawer> with Refena {
  late bool _enable5G = ref.read(persistenceProvider).isEnable5GPreference();

  Future<void> _selectTheme() async {
    final current = ref.read(settingsProvider).theme;
    final selected = await showDialog<ThemeMode>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Theme'),
        children: ThemeMode.values
            .map(
              (mode) => RadioListTile<ThemeMode>(
                value: mode,
                groupValue: current,
                title: Text(mode.name),
                onChanged: (value) => Navigator.of(context).pop(value),
              ),
            )
            .toList(),
      ),
    );
    if (selected != null) await ref.notifier(settingsProvider).setTheme(selected);
  }

  Future<void> _selectColor() async {
    final settings = ref.read(settingsProvider);
    final selected = await showDialog<ColorMode>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Color'),
        children: ColorMode.values
            .map(
              (mode) => RadioListTile<ColorMode>(
                value: mode,
                groupValue: settings.colorMode,
                title: Text(mode.name),
                onChanged: (value) => Navigator.of(context).pop(value),
              ),
            )
            .toList(),
      ),
    );
    if (selected == null) return;
    if (selected == ColorMode.custom) {
      final color = await showDialog<Color>(
        context: context,
        builder: (_) => CustomColorDialog(initialColor: settings.customColor),
      );
      if (color == null) return;
      await ref.notifier(settingsProvider).setCustomColor(color);
    }
    await ref.notifier(settingsProvider).setColorMode(selected);
    if (selected == ColorMode.oled) {
      await ref.notifier(settingsProvider).setTheme(ThemeMode.dark);
      await updateSystemOverlayStyleWithBrightness(Brightness.dark);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch(settingsProvider);
    return Drawer(
      backgroundColor: Colors.transparent,
      child: GlassCard(
        margin: EdgeInsets.zero,
        padding: EdgeInsets.zero,
        radius: 0,
        blur: true,
        child: SafeArea(
          child: ListView(
          children: [
            const DrawerHeader(
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text('OmniDrop', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.brightness_6),
              title: const Text('Theme'),
              subtitle: Text(settings.theme.name),
              onTap: _selectTheme,
            ),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Color'),
              subtitle: Text(settings.colorMode.name),
              onTap: _selectColor,
            ),
            ListTile(
              leading: const Icon(Icons.language),
              title: const Text('Language'),
              subtitle: Text(settings.locale?.languageTag ?? 'System'),
              onTap: () async => await context.push(() => const LanguagePage()),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.animation),
              title: const Text('Animations'),
              value: settings.enableAnimations,
              onChanged: (value) async => await ref.notifier(settingsProvider).setEnableAnimations(value),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.signal_cellular_alt),
              title: const Text('Enable 5G'),
              value: _enable5G,
              onChanged: (value) async {
                // This stores a UI preference only; apps cannot force cellular generation or control the radio.
                await ref.read(persistenceProvider).setEnable5GPreference(value);
                if (mounted) setState(() => _enable5G = value);
              },
            ),
            ListTile(
              leading: const Icon(Icons.star_outline),
              title: const Text('Rating'),
              onTap: () async {
                final uri = Uri.parse('https://play.google.com/store/apps/details?id=com.omnidrop.app');
                if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About'),
              onTap: () async => await context.push(() => const AboutPage()),
            ),
          ],
          ),
        ),
      ),
    );
  }
}