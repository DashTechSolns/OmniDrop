import 'dart:async';
import 'dart:io';

import 'package:dart_mappable/dart_mappable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:localsend_app/config/refena.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/pages/home_page.dart';
import 'package:localsend_app/pages/home_page_controller.dart';
import 'package:localsend_app/pages/whats_new_page.dart';
import 'package:localsend_app/provider/animation_provider.dart';
import 'package:localsend_app/provider/app_arguments_provider.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/network/webrtc/signaling_provider.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
// [FOSS_REMOVE_START]
import 'package:localsend_app/provider/purchase_provider.dart';
// [FOSS_REMOVE_END]
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/provider/tv_provider.dart';
import 'package:localsend_app/provider/version_provider.dart';
import 'package:localsend_app/provider/window_dimensions_provider.dart';
import 'package:localsend_app/util/i18n.dart';
import 'package:localsend_app/util/native/autostart_helper.dart';
import 'package:localsend_app/util/native/cache_helper.dart';
import 'package:localsend_app/util/native/channel/android_channel.dart';
import 'package:localsend_app/util/native/context_menu_helper.dart';
import 'package:localsend_app/util/native/cross_file_converters.dart';
import 'package:localsend_app/util/native/device_info_helper.dart';
import 'package:localsend_app/util/native/macos_channel.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/native/tray_helper.dart';
import 'package:localsend_app/util/notification_strings.dart';
import 'package:localsend_app/util/ui/dynamic_colors.dart';
import 'package:localsend_app/util/ui/snackbar.dart';
import 'package:localsend_app/widget/dialogs/local_network_dialog.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:localsend_isolates/model/dto/file_dto.dart';
import 'package:localsend_isolates/model/dto/multicast_dto.dart';
import 'package:localsend_isolates/rust/api/logging.dart' as rust_logging;
import 'package:localsend_isolates/rust/frb_generated.dart';
import 'package:localsend_isolates/util/logger.dart';
import 'package:localsend_isolates/util/show_instance.dart';
import 'package:localsend_isolates/util/transfer_notification.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';
import 'package:share_handler/share_handler.dart';
import 'package:window_manager/window_manager.dart';

final _logger = Logger('Init');
const _initStepTimeout = Duration(seconds: 30);

Future<T> _awaitInit<T>(Future<T> future, String step, {Duration timeout = _initStepTimeout}) {
  return future.timeout(
    timeout,
    onTimeout: () => throw TimeoutException('Timed out while $step', timeout),
  );
}

/// Will be called before the MaterialApp started
Future<RefenaContainer> preInit(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  initLogger(args.contains('-v') || args.contains('--verbose') ? Level.ALL : Level.INFO);
  MapperContainer.globals.use(const FileDtoMapper());

  await _awaitInit(RustLib.init(), 'initializing Rust');

  if (kDebugMode) {
    try {
      await _awaitInit(rust_logging.enableDebugLogging(), 'enabling Rust debug logging');
    } catch (e) {
      _logger.warning('Enabling debug logging failed', e);
    }
  }

  final dynamicColors = await _awaitInit(getDynamicColors(), 'reading dynamic colors');

  final persistenceService = await _awaitInit(
    PersistenceService.initialize(supportsDynamicColors: dynamicColors != null),
    'loading persistent settings',
  );

  if (persistenceService.isFirstAppStart && !persistenceService.isPortableMode()) {
    await _awaitInit(enableContextMenu(), 'enabling the context menu');
  }

  await _awaitInit(initI18n(), 'initializing translations');

  TransferNotification.init(notificationStrings);

  bool startHidden = false;
  if (checkPlatformIsDesktop()) {
    // Check if this app is already open and let it "show up".
    // If this is the case, then exit the current instance.

    final handedOver = await _awaitInit(
      notifyRunningInstance(
        securityContext: persistenceService.getSecurityContext(),
        port: persistenceService.getPort(),
        https: persistenceService.isHttps(),
        showToken: persistenceService.getShowToken(),
        args: args,
      ),
      'checking for an existing instance',
    );
    if (handedOver) {
      exit(0); // Another instance does exist
    }

    // initialize tray AFTER i18n has been initialized
    try {
      await _awaitInit(initTray(), 'initializing the system tray');
    } catch (e) {
      _logger.warning('Initializing tray failed: $e');
    }

    // initialize size and position
    await _awaitInit(WindowManager.instance.ensureInitialized(), 'initializing the application window');
    await _awaitInit(WindowDimensionsController(persistenceService).initDimensionsConfiguration(), 'loading window dimensions');
    if (args.contains(startHiddenFlag)) {
      // keep this app hidden
      startHidden = true;
    } else if (defaultTargetPlatform == TargetPlatform.macOS) {
      startHidden =
          await _awaitInit(isLaunchedAsLoginItem(), 'checking login-item launch state') &&
          await _awaitInit(getLaunchAtLoginMinimized(), 'checking minimized launch preference');
    }

    if (startHidden) {
      unawaited(hideToTray());
    } else {
      unawaited(showFromTray());
    }

    if (defaultTargetPlatform == TargetPlatform.macOS) {
      await _awaitInit(setupStatusBar(), 'initializing the status bar');
    }
  }

  setDefaultRouteTransition();

  final container = RefenaContainer(
    observers: kDebugMode ? [CustomRefenaObserver()] : [],
    overrides: [
      persistenceProvider.overrideWithValue(persistenceService),
      deviceRawInfoProvider.overrideWithValue(await _awaitInit(getDeviceInfo(), 'reading device information')),
      appArgumentsProvider.overrideWithValue(args),
      tvProvider.overrideWithValue(await _awaitInit(checkIfTv(), 'checking TV device mode')),
      dynamicColorsProvider.overrideWithValue(dynamicColors),
      sleepProvider.overrideWithInitialState((ref) => startHidden),
    ],
    platformHint: RefenaScope.getPlatformHint(), // help Refena know the correct platform
  );

  // compatibility for Routerino. TODO: Remove Routerino
  Routerino.navigatorKey = container.read(navigationProvider).key;

  // initialize multi-threading
  await _awaitInit(
    container.set(
      parentIsolateProvider.overrideWithNotifier((ref) {
        final settings = ref.read(settingsProvider);
        return IsolateController(
          initialState: ParentIsolateState.initial(
            SyncState(
              rootIsolateToken: RootIsolateToken.instance!,
              securityContext: persistenceService.getSecurityContext(),
              deviceInfo: ref.read(deviceInfoProvider),
              alias: settings.alias,
              port: settings.port,
              networkWhitelist: settings.networkWhitelist,
              networkBlacklist: settings.networkBlacklist,
              protocol: settings.https ? ProtocolType.https : ProtocolType.http,
              multicastGroup: settings.multicastGroup,
              discoveryTimeout: settings.discoveryTimeout,
              serverRunning: true,
              download: false,
            ),
          ),
        );
      }),
    ),
    'creating the networking isolate',
  );

  await _awaitInit(container.redux(parentIsolateProvider).dispatchAsync(IsolateSetupAction()), 'starting networking isolates');

  return container;
}

StreamSubscription? _sharedMediaSubscription;

/// Will be called when home page has been initialized
Future<void> postInit(BuildContext context, Ref ref, bool appStart) async {
  await _awaitInit(updateSystemOverlayStyle(context), 'updating system overlay style');

  if (checkPlatform([TargetPlatform.android])) {
    try {
      await _awaitInit(FlutterDisplayMode.setHighRefreshRate(), 'setting display refresh rate');
    } catch (e) {
      _logger.warning('Setting high refresh rate failed', e);
    }

    // Android 17+ blocks multicast discovery and LAN connections until this permission is granted,
    // so ask before the server and discovery start.
    final localNetworkGranted = await _awaitInit(requestLocalNetworkPermissionAndroid(), 'requesting local network permission');
    if (!localNetworkGranted) {
      _logger.warning('Local network permission denied. Discovery and transfers may not work.');
      if (context.mounted) {
        try {
          await _awaitInit(
            context.pushBottomSheet(() => const LocalNetworkDialog()),
            'waiting for local network permission settings',
            timeout: const Duration(minutes: 5),
          );
        } on TimeoutException catch (error, stackTrace) {
          _logger.warning('Local network permission dialog remained open', error, stackTrace);
        }
      }
    }
  }

  try {
    await _awaitInit(ref.notifier(serverProvider).startServerFromSettings(), 'starting the receive server');
  } catch (e) {
    if (context.mounted) {
      context.showSnackBar(e.toString());
    }
  }

  try {
    ref.redux(nearbyDevicesProvider).dispatchAsync(StartDiscoveryListener()); // ignore: unawaited_futures
  } catch (e) {
    _logger.warning('Starting discovery listener failed', e);
  }

  // ignore: dead_code
  if (webRTCEnabled) {
    ref.redux(signalingProvider).dispatch(SetupSignalingConnection());
  }

  if (appStart) {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      // handle dropped files
      pendingFilesStream.listen((files) async {
        await _awaitInit(
          ref.global.dispatchAsync(_HandleAppStartArgumentsAction(args: files)),
          'handling dropped launch files',
        );
      });

      // handle dropped strings
      pendingStringsStream.listen((pendingStrings) {
        for (final string in pendingStrings) {
          ref.redux(selectedSendingFilesProvider).dispatch(AddMessageAction(message: string));
        }
        ref.redux(homePageControllerProvider).dispatch(ChangeTabAction(HomeTab.send));
      });

      await _awaitInit(setupMethodCallHandler(), 'setting up macOS method calls');
    } else {
      final args = ref.read(appArgumentsProvider);
      await _awaitInit(
        ref.global.dispatchAsync(_HandleAppStartArgumentsAction(args: args)),
        'handling application launch arguments',
      );
    }
  }

  bool hasInitialShare = false;

  if (checkPlatformCanReceiveShareIntent()) {
    final shareHandler = ShareHandlerPlatform.instance;

    if (appStart) {
      final initialSharedPayload = await _awaitInit(shareHandler.getInitialSharedMedia(), 'reading initial shared media');
      if (initialSharedPayload != null) {
        hasInitialShare = true;
        // ignore: unawaited_futures
        ref.global.dispatchAsync(
          _HandleShareIntentAction(
            payload: initialSharedPayload,
          ),
        );
      }
    }

    _sharedMediaSubscription?.cancel(); // ignore: unawaited_futures
    _sharedMediaSubscription = shareHandler.sharedMediaStream.listen((SharedMedia payload) async {
      await _awaitInit(
        ref.global.dispatchAsync(_HandleShareIntentAction(payload: payload)),
        'handling shared media',
      );
    });

    if (checkPlatform([TargetPlatform.android])) {
      // Both messages above travel through the same messenger in order, so the stream is
      // guaranteed to be attached natively before MainActivity replays held-back intents.
      await _awaitInit(flushPendingShareIntentsAndroid(), 'reading pending Android share intents');
    }
  }

  if (appStart && !hasInitialShare && (checkPlatformWithGallery() || checkPlatformCanReceiveShareIntent())) {
    // Clear cache on every app start.
    // If we received a share intent, then don't clear it, otherwise the shared file will be lost.
    ref.global.dispatchAsync(ClearCacheAction()); // ignore: unawaited_futures
  }

  if (!ref.read(persistenceProvider).isFirstAppStart) {
    WhatsNewPage? whatsNew = WhatsNewPage.fromLastVersion(lastVersion: ref.read(persistenceProvider).getWhatsNew());
    if (whatsNew != null) {
      // ignore: unawaited_futures
      ref.global.dispatchAsync(NavigateAction.push(whatsNew));
    }
  }

  await _awaitInit(
    ref.future(versionProvider).then((version) async {
      await _awaitInit(ref.read(persistenceProvider).setWhatsNew(version.version), 'saving the current app version');
    }),
    'checking the current app version',
  );

  // [FOSS_REMOVE_START]
  if (checkPlatformSupportPayment()) {
    // ignore: unawaited_futures
    ref.redux(purchaseProvider).dispatchAsync(InitPurchaseStream());
  }
  // [FOSS_REMOVE_END]
}

class _HandleShareIntentAction extends AsyncGlobalAction {
  final SharedMedia payload;

  _HandleShareIntentAction({
    required this.payload,
  });

  @override
  Future<void> reduce() async {
    final message = payload.content;
    if (message != null && message.trim().isNotEmpty) {
      ref.redux(selectedSendingFilesProvider).dispatch(AddMessageAction(message: message));
    }
    await ref
        .redux(selectedSendingFilesProvider)
        .dispatchAsync(
          AddFilesAction(
            files: payload.attachments?.where((a) => a != null).cast<SharedAttachment>() ?? <SharedAttachment>[],
            converter: CrossFileConverters.convertSharedAttachment,
          ),
        );

    ref.redux(homePageControllerProvider).dispatch(ChangeTabAction(HomeTab.send));
  }
}

class _HandleAppStartArgumentsAction extends AsyncGlobalAction {
  final List<String> args;

  _HandleAppStartArgumentsAction({
    required this.args,
  });

  @override
  Future<void> reduce() async {
    final filesAdded = await ref.redux(selectedSendingFilesProvider).dispatchAsyncTakeResult(LoadSelectionFromArgsAction(args));
    if (filesAdded) {
      ref.redux(homePageControllerProvider).dispatch(ChangeTabAction(HomeTab.send));
    }
  }
}
