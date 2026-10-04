import 'dart:io';

import 'package:device_apps/device_apps.dart';
import 'package:localsend_app/provider/param/apk_provider_param.dart';
import 'package:localsend_app/provider/param/cached_apk_provider_param.dart';
import 'package:refena_flutter/refena_flutter.dart';

final apkSearchParamProvider = StateProvider<ApkProviderParam>(
  (ref) => ApkProviderParam(
    query: '',
    includeSystemApps: false,
    onlyAppsWithLaunchIntent: true,
    selectMultipleApps: false,
  ),
);

final apkProvider = ViewProvider<AsyncValue<List<Application>>>((ref) {
  final param = ref.watch(apkSearchParamProvider);

  return ref
      .watch(
        installedApplicationsProvider(
          CachedApkProviderParam(
            includeSystemApps: param.includeSystemApps,
            onlyAppsWithLaunchIntent: param.onlyAppsWithLaunchIntent,
            selectMultipleApps: param.selectMultipleApps,
          ),
        ),
      )
      .maybeWhen(
        data: (apps) {
          final query = param.query.trim().toLowerCase();
          var result = apps;
          if (query.isNotEmpty) {
            result = apps.where((a) => a.appName.toLowerCase().contains(query) || a.packageName.contains(query)).toList();
          }

          result = [...result]..sort((a, b) => a.appName.compareTo(b.appName));
          return AsyncValue<List<Application>>.data(result);
        },
        orElse: () => const AsyncValue<List<Application>>.loading(),
      );
});

final apkSizeProvider = FutureFamilyProvider<int, String>((_, path) {
  return File(path).length();
});

/// Provides the installed applications and their icon bytes from a cached async query.
final installedApplicationsProvider = FutureFamilyProvider<List<Application>, CachedApkProviderParam>((_, param) {
  return DeviceApps.getInstalledApplications(
    includeSystemApps: param.includeSystemApps,
    onlyAppsWithLaunchIntent: param.onlyAppsWithLaunchIntent,
    includeAppIcons: true,
  );
});
