import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:system_theme/system_theme.dart';
import 'package:window_manager/window_manager.dart';

import 'core/adb_service.dart';
import 'core/app_settings.dart';
import 'core/tv_controller.dart';
import 'l10n/gen/app_localizations.dart';
import 'ui/flyout_shell.dart';
import 'ui/mirror_window.dart';
import 'ui/theme.dart';

void main(List<String> args) {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows && args.isNotEmpty && args[0] == '--mirror') {
    final host = args.length > 1 ? args[1] : '';
    final name = args.length > 2 ? args[2] : 'TV';
    final modeArg = args.length > 3 ? args[3] : 'cast';
    final portArg = args.length > 4 ? int.tryParse(args[4]) : null;
    final parentPort = args.length > 5 ? int.tryParse(args[5]) : null;
    final parentPid = args.length > 6 ? int.tryParse(args[6]) : null;

    // Carrega configurações (nomes reais de pacotes, etc.)
    await AppSettings.instance.load();

    if (portArg != null && portArg > 0) {
      AdbService.instance.setAdbPort(portArg);
    }
    MirrorTracker.startHeartbeatMonitoring(
      parentPort: parentPort,
      parentPid: parentPid,
    );
    final initialMode =
        modeArg == 'adb' ? MirrorMode.adbScreen : MirrorMode.castMedia;

    final tvController = TvController();
    MirrorTracker.registerActiveController(tvController);

    // Render the UI IMMEDIATELY without waiting for anything
    runApp(MirrorWindowApp(
      controller: tvController,
      tvName: name,
      tvHost: host,
      initialMode: initialMode,
    ));

    // Connect ADB in background for continuous app and screen detection
    AdbService.instance.setMode(initialMode);
    AdbService.instance.connectToTv(host, port: portArg ?? AdbService.instance.adbPort);

    // Secondary setup asynchronously in background
    SystemTheme.accentColor.load();
    windowManager.ensureInitialized().then((_) async {
      await windowManager.focus();
    });

    // Connect TV controller asynchronously in background
    tvController.init().then((_) {
      final matching =
          tvController.tvs.where((t) => t.host == host).firstOrNull;
      if (matching != null) {
        tvController.selectTv(matching.id);
      }
    });
    return;
  }

  // Limpa processos órfãos de sessões anteriores e inicializa o servidor de batimento cardíaco
  if (Platform.isWindows) {
    MirrorTracker.killAllMirrors();
    await MirrorTracker.initParentServer();
    try {
      ProcessSignal.sigint.watch().listen((_) {
        MirrorTracker.killAllMirrors();
        exit(0);
      });
    } catch (_) {}
  }

  // Load Windows system accent color
  await SystemTheme.accentColor.load();

  final tvController = TvController();
  MirrorTracker.registerActiveController(tvController);
  await tvController.init();

  final settings = AppSettings.instance;
  await settings.load();

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await Window.initialize();

    // Use transparent background to avoid Windows 10 acrylic buffer warping
    try {
      await Window.setEffect(
        effect: WindowEffect.transparent,
      );
    } catch (_) {}

    // Calculate initial height directly from saved TVs so it opens perfectly sized with 0 blinking
    final int tvCount = tvController.tvs.length;
    double initialHeight = 400.0;
    if (tvCount > 0) {
      initialHeight += 28.0 + (tvCount * 68.0);
    }
    initialHeight = initialHeight.clamp(400.0, 960.0);

    final windowSize = Size(360, initialHeight);
    final windowOptions = WindowOptions(
      size: windowSize,
      backgroundColor: Colors.transparent,
      skipTaskbar: true,
      titleBarStyle: TitleBarStyle.hidden,
      alwaysOnTop: true,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setSize(windowSize);
      await windowManager.setPreventClose(true);

      // Posiciona no canto inferior direito próximo à bandeja
      try {
        final primaryDisplay = await screenRetriever.getPrimaryDisplay();
        final visiblePos = primaryDisplay.visiblePosition ?? Offset.zero;
        final visibleSize = primaryDisplay.visibleSize ?? primaryDisplay.size;
        final x = visiblePos.dx + visibleSize.width - windowSize.width - 12;
        final y = visiblePos.dy + visibleSize.height - windowSize.height - 12;
        await windowManager.setPosition(Offset(x, y));
      } catch (_) {
        await windowManager.setAlignment(Alignment.bottomRight);
      }

      await windowManager.show();
      await windowManager.focus();
    });
  }

    runApp(TvRemoteApp(controller: tvController, settings: settings));
  }, (error, stack) {
    debugPrint('Zoned error caught: $error');
  });
}

class TvRemoteApp extends StatelessWidget {
  final TvController controller;
  final AppSettings settings;

  const TvRemoteApp({
    super.key,
    required this.controller,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final currentLang = settings.locale?.languageCode ?? 'system';
        final effective = settings.effectiveLocale;
        return MaterialApp(
          key: ValueKey('tv_app_${currentLang}_${effective.languageCode}_${settings.themeMode}'),
          title: 'TV Remote by Chyri',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: settings.themeMode,
          locale: settings.locale ?? effective,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          localeResolutionCallback: (locale, supportedLocales) {
            final target = settings.locale ?? locale ?? effective;
            for (final supported in supportedLocales) {
              if (supported.languageCode == target.languageCode) {
                return supported;
              }
            }
            return const Locale('en');
          },
          home: FlyoutShell(controller: controller),
        );
      },
    );
  }
}
