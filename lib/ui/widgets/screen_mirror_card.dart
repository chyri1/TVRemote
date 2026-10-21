import 'package:flutter/material.dart';

import '../../core/adb_service.dart';
import '../../core/app_settings.dart';
import '../../core/tv_controller.dart';
import '../theme.dart';
import 'adb_port_dialog.dart';

/// Screen Mirror live preview card displayed in the remote above the media player.
/// Supports both Google Cast / Media metadata view and real-time ADB screen capture.
/// Clicking it opens the mirror feed in a dedicated separate Windows window.
class ScreenMirrorCard extends StatefulWidget {
  final TvController controller;
  final VoidCallback onOpenPopout;

  const ScreenMirrorCard({
    super.key,
    required this.controller,
    required this.onOpenPopout,
  });

  @override
  State<ScreenMirrorCard> createState() => _ScreenMirrorCardState();
}

class _ScreenMirrorCardState extends State<ScreenMirrorCard> {
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    final tv = widget.controller.selected;
    if (tv != null) {
      AdbService.instance.ensureConnected(tv.host);
    } else {
      AdbService.instance.findAdb();
    }
  }

  @override
  void didUpdateWidget(covariant ScreenMirrorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final tv = widget.controller.selected;
    if (tv != null && tv.host != oldWidget.controller.selected?.host) {
      AdbService.instance.ensureConnected(tv.host);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final tv = widget.controller.selected;
    final info = widget.controller.nowPlaying;
    final hasImage = info?.imageUrl != null && info!.imageUrl!.isNotEmpty;
    final adb = AdbService.instance;

    return ListenableBuilder(
      listenable: Listenable.merge([widget.controller, adb]),
      builder: (context, _) {
        final isAdbMode = adb.mode == MirrorMode.adbScreen;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Mode Selector Tabs (Cast / Mídia vs Depuração ADB)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildModeTab(
                            label: appTr(pt: 'Mídia / Cast', en: 'Media / Cast', es: 'Medios / Cast'),
                            icon: Icons.movie_filter_rounded,
                            selected: !isAdbMode,
                            p: p,
                            onTap: () => adb.setMode(MirrorMode.castMedia),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildModeTab(
                            label: appTr(pt: 'Depuração ADB', en: 'ADB Debugging', es: 'Depuración ADB'),
                            icon: Icons.adb_rounded,
                            selected: isAdbMode,
                            p: p,
                            onTap: () {
                              adb.setMode(MirrorMode.adbScreen);
                              if (tv != null && adb.state == AdbState.idle) {
                                adb.connectToTv(tv.host);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    if (isAdbMode) ...[
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => showAdbPortDialog(
                                context, tv?.host ?? '192.168.1.100'),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: p.fill,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: p.stroke, width: 0.8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.settings_ethernet_rounded,
                                      size: 13, color: Color(0xFF60CDFF)),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${appTr(pt: 'Porta ADB', en: 'ADB Port', es: 'Puerto ADB')}: ${adb.adbPort}',
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.edit_rounded,
                                      size: 11, color: Colors.white60),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Preview Screen Container
              MouseRegion(
                onEnter: (_) => setState(() => _hovered = true),
                onExit: (_) => setState(() => _hovered = false),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _hovered ? p.accent : p.stroke,
                      width: _hovered ? 1.5 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Display Feed (Cast Media vs ADB Screencap)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: widget.onOpenPopout,
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: widget.controller.isScreenOff
                                ? _buildVirtualDisplay(p, tv, null)
                                : (!isAdbMode
                                    ? (hasImage
                                        ? Image.network(
                                            info.imageUrl!,
                                            fit: BoxFit.cover,
                                            errorBuilder: (ctx, err, stack) =>
                                                _buildVirtualDisplay(p, tv, info),
                                          )
                                        : _buildVirtualDisplay(p, tv, info))
                                    : _buildAdbContent(p, tv, adb)),
                          ),
                        ),

                          // Top gradient shadow
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            height: 44,
                            child: IgnorePointer(
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.black.withValues(alpha: 0.75),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // Bottom gradient shadow
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            height: 50,
                            child: IgnorePointer(
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [
                                      Colors.black.withValues(alpha: 0.85),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // Top Bar: Live indicator + Pop-out button
                          Positioned(
                            top: 8,
                            left: 8,
                            right: 8,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Live badge
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.75),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: (!widget.controller.isScreenOff &&
                                              ((isAdbMode && adb.state == AdbState.connected) ||
                                                  (!isAdbMode && info != null && info.isPlaying)))
                                          ? const Color(0xFF107C41)
                                          : Colors.redAccent.withValues(alpha: 0.6),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 7,
                                        height: 7,
                                        decoration: BoxDecoration(
                                          color: (!widget.controller.isScreenOff &&
                                                  ((isAdbMode && adb.state == AdbState.connected) ||
                                                      (!isAdbMode && info != null && info.isPlaying)))
                                              ? const Color(0xFF107C41)
                                              : Colors.redAccent,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        widget.controller.isScreenOff
                                            ? appTr(pt: 'DESLIGADA', en: 'OFF', es: 'APAGADA')
                                            : appTr(pt: 'AO VIVO', en: 'LIVE', es: 'EN VIVO'),
                                        style: const TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Pop-out button
                                Tooltip(
                                  message: appTr(pt: 'Abrir em tela destacada', en: 'Open in separate window', es: 'Abrir en ventana separada'),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: widget.onOpenPopout,
                                      borderRadius: BorderRadius.circular(6),
                                      child: Container(
                                        padding: const EdgeInsets.all(5),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.7),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Icon(
                                          Icons.open_in_new_rounded,
                                          size: 14,
                                          color: _hovered ? p.accent : Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Bottom Bar: Active Title / App info (apenas quando a tela estiver ligada)
                          if (!widget.controller.isScreenOff &&
                              (_hovered ||
                                  hasImage ||
                                  (isAdbMode && adb.currentFrame != null) ||
                                  (info != null && info.hasMedia)))
                            Positioned(
                              bottom: 8,
                              left: 10,
                              right: 10,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        widget.controller.isScreenOff
                                            ? appTr(pt: 'Tela desligada', en: 'Screen off', es: 'Pantalla apagada')
                                            : (isAdbMode
                                                ? (adb.state == AdbState.connected
                                                    ? appTr(pt: 'Tela em Tempo Real (ADB)', en: 'Real-Time Screen (ADB)', es: 'Pantalla en tiempo real (ADB)')
                                                    : (adb.getErrorMessageTr() ?? appTr(pt: 'Depuração USB / Rede', en: 'USB / Network Debugging', es: 'Depuración USB / Red')))
                                                : (info?.displayTitle ?? tv?.name ?? 'Android TV')),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      if (!widget.controller.isScreenOff && !isAdbMode && info?.displaySubtitle != null)
                                        Text(
                                          info!.displaySubtitle!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.white.withValues(alpha: 0.75),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (_hovered)
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: widget.onOpenPopout,
                                      borderRadius: BorderRadius.circular(5),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: p.accent,
                                          borderRadius: BorderRadius.circular(5),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              'Destacar',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: p.onAccent,
                                              ),
                                            ),
                                            const SizedBox(width: 3),
                                            Icon(
                                              Icons.arrow_forward_rounded,
                                              size: 11,
                                              color: p.onAccent,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModeTab({
    required String label,
    required IconData icon,
    required bool selected,
    required Palette p,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? p.accent.withValues(alpha: 0.15)
              : p.fill,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? p.accent : p.stroke.withValues(alpha: 0.5),
            width: selected ? 1.2 : 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 13,
              color: selected ? p.accent : p.textDim,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? p.accent : p.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdbContent(Palette p, dynamic tv, AdbService adb) {
    if (adb.state == AdbState.connected && adb.currentFrame != null) {
      return Image.memory(
        adb.currentFrame!,
        fit: BoxFit.contain,
        gaplessPlayback: true,
      );
    }

    return Container(
      color: const Color(0xFF101016),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (adb.state == AdbState.missingAdb) ...[
              const Icon(Icons.adb_rounded, size: 28, color: Colors.orangeAccent),
              const SizedBox(height: 6),
              const Text(
                'Ferramenta ADB não encontrada',
                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 26,
                child: FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  ),
                  onPressed: () => adb.downloadPlatformTools(),
                  child: const Text('Baixar ADB Oficial (Google)', style: TextStyle(fontSize: 10)),
                ),
              ),
            ] else if (adb.state == AdbState.downloadingAdb) ...[
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(height: 8),
              Text(
                '${appTr(pt: 'Baixando ADB', en: 'Downloading ADB', es: 'Descargando ADB')} (${(adb.downloadProgress * 100).toInt()}%)...',
                style: const TextStyle(color: Colors.white70, fontSize: 10.5),
              ),
            ] else if (adb.state == AdbState.connecting || adb.state == AdbState.checking) ...[
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(height: 8),
              Text(
                '${appTr(pt: 'Conectando a', en: 'Connecting to', es: 'Conectando a')} ${tv?.host ?? "TV"}:${adb.adbPort}...',
                style: const TextStyle(color: Colors.white70, fontSize: 10.5),
              ),
            ] else if (adb.state == AdbState.connected && adb.currentFrame == null) ...[
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(height: 8),
              Text(
                '${appTr(pt: 'Carregando tela da TV', en: 'Loading TV screen', es: 'Cargando pantalla de la TV')}...',
                style: const TextStyle(color: Colors.white70, fontSize: 10.5),
              ),
            ] else if (adb.state == AdbState.unauthorized) ...[
              const Icon(Icons.touch_app_rounded, size: 26, color: Colors.amberAccent),
              const SizedBox(height: 4),
              Text(
                appTr(pt: 'Autorize na tela da TV!', en: 'Authorize on TV screen!', es: '¡Autoriza en la pantalla de la TV!'),
                style: const TextStyle(color: Colors.amberAccent, fontSize: 11.5, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                appTr(pt: 'Marque "Sempre permitir" e clique em OK', en: 'Check "Always allow" and click OK', es: 'Marca "Permitir siempre" y haz clic en OK'),
                style: const TextStyle(color: Colors.white70, fontSize: 9.5),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 24,
                child: FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  ),
                  onPressed: () => adb.reRequestConnection(tv?.host),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.restart_alt_rounded, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        appTr(pt: 'Reenviar pedido à TV', en: 'Resend request to TV', es: 'Reenviar solicitud a la TV'),
                        style: const TextStyle(fontSize: 9.5),
                      ),
                    ],
                  ),
                ),
              ),
            ] else if (adb.state == AdbState.error) ...[
              const Icon(Icons.warning_amber_rounded, size: 26, color: Colors.redAccent),
              Text(
                adb.getErrorMessageTr() ?? appTr(pt: 'Erro na conexão ADB', en: 'ADB connection error', es: 'Error en la conexión ADB'),
                style: const TextStyle(color: Colors.white, fontSize: 10),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                alignment: WrapAlignment.center,
                children: [
                  if (adb.adbPort != 5555)
                    SizedBox(
                      height: 24,
                      child: FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                        ),
                        onPressed: () {
                          if (tv != null) adb.reRequestConnection(tv.host, 5555);
                        },
                        child: Text(
                          appTr(pt: 'Usar porta 5555', en: 'Use port 5555', es: 'Usar puerto 5555'),
                          style: const TextStyle(fontSize: 9.5),
                        ),
                      ),
                    ),
                  SizedBox(
                    height: 24,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                      ),
                      onPressed: () {
                        if (tv != null) adb.reRequestConnection(tv.host);
                      },
                      child: Text(
                        appTr(pt: 'Tentar novamente', en: 'Try again', es: 'Reintentar'),
                        style: const TextStyle(fontSize: 9.5),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Icon(Icons.adb_rounded, size: 28, color: p.accent),
              const SizedBox(height: 6),
              SizedBox(
                height: 26,
                child: FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  ),
                  onPressed: () {
                    if (tv != null) adb.connectToTv(tv.host);
                  },
                  child: Text(
                    appTr(pt: 'Conectar depuração ADB', en: 'Connect ADB debugging', es: 'Conectar depuración ADB'),
                    style: const TextStyle(fontSize: 10.5),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVirtualDisplay(Palette p, dynamic tv, [NowPlayingInfo? info]) {
    final adb = AdbService.instance;
    final activeAppPkg = adb.currentAppPackage ?? info?.appPackage;
    final friendlyFromPkg = NowPlayingInfo.friendlyPackageName(activeAppPkg);
    final isCastPlaying = (info?.isPlaying == true || info?.hasMedia == true);
    final rawAppName = (!isCastPlaying && adb.currentAppName != null && adb.currentAppName != 'Tela Inicial')
        ? adb.currentAppName
        : (friendlyFromPkg ?? adb.currentAppName ?? info?.appName);
    final String? appName;
    if (AppSettings.instance.showRawPackageName) {
      appName = (activeAppPkg != null && activeAppPkg.isNotEmpty)
          ? activeAppPkg
          : (rawAppName != null && rawAppName.isNotEmpty ? rawAppName : null);
    } else {
      final friendly = friendlyFromPkg;
      if (friendly != null && friendly.isNotEmpty && friendly != 'Tela Inicial') {
        appName = friendly;
      } else if (rawAppName != null &&
          rawAppName.isNotEmpty &&
          rawAppName != 'Default Media Receiver' &&
          rawAppName != 'Tela Inicial') {
        final rLow = rawAppName.toLowerCase();
        if (rLow.contains('backdrop') || rLow == 'screen saver' || rLow == 'ambient mode') {
          appName = getScreenSaverTitle();
        } else if (rLow.contains('projengmenu') || rLow.contains('projectivy')) {
          appName = 'Projectivy Launcher';
        } else if (rLow.contains('sendfilestotv') || rLow.contains('send files to tv')) {
          appName = 'Send Files to TV';
        } else if (rLow.contains('bitchord')) {
          appName = 'BitChord';
        } else if (rLow.contains('youcine')) {
          appName = 'YouCine';
        } else if (rLow.contains('isiclite') || rLow.contains('intelbras')) {
          appName = 'ISIC Lite';
        } else if (rLow.contains('mediatek.wwtv') || rLow.contains('wwtv')) {
          appName = 'TV / HDMI / AV';
        } else {
          appName = rawAppName;
        }
      } else {
        if (info?.hasMedia == true) {
          appName = 'YouTube';
        } else if (activeAppPkg != null &&
            activeAppPkg.isNotEmpty &&
            activeAppPkg != 'Tela Inicial') {
          appName = activeAppPkg;
        } else if (rawAppName != null &&
            rawAppName.isNotEmpty &&
            rawAppName != 'Tela Inicial') {
          appName = rawAppName;
        } else {
          appName = appTr(pt: 'Tela Inicial', en: 'Home Screen', es: 'Pantalla de inicio');
        }
      }
    }

    final isScreenOff = widget.controller.isScreenOff;
    final hasAppInfo = !isScreenOff && appName != null && appName.isNotEmpty;
    final displayName = isScreenOff
        ? appTr(pt: 'Tela desligada', en: 'Screen off', es: 'Pantalla apagada')
        : (hasAppInfo ? appName : (tv?.name ?? 'Android TV'));

    return Container(
      color: const Color(0xFF141419),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isScreenOff)
              const Icon(Icons.tv_off_rounded, size: 36, color: Colors.white38)
            else if (hasAppInfo)
              _buildAppBrandIcon(activeAppPkg, displayName)
            else
              Icon(Icons.tv_rounded, size: 36, color: p.accent),
            const SizedBox(height: 7),
            Text(
              displayName,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              isScreenOff
                  ? (tv?.name ?? 'Android TV')
                  : appTr(pt: 'Transmissão da tela ativa', en: 'Active screen cast', es: 'Transmisión de pantalla activa'),
              style: TextStyle(
                fontSize: 10,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBrandIcon(String? pkg, String name) {
    final str = '${pkg ?? ''} $name'.toLowerCase();
    if (str.contains('backdrop') ||
        str.contains('protetor de tela') ||
        str.contains('screen saver') ||
        str.contains('salvapantallas')) {
      return Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4285F4), Color(0xFF34A853)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Center(
          child: Icon(
            Icons.wallpaper_rounded,
            color: Colors.white,
            size: 18,
          ),
        ),
      );
    } else if (str.contains('mediatek.wwtv') ||
        str.contains('wwtv') ||
        str.contains('tv / hdmi / av')) {
      return Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: const Color(0xFF1E3A8A),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF60A5FA), width: 1.2),
        ),
        child: const Center(
          child: Icon(
            Icons.settings_input_hdmi_rounded,
            color: Color(0xFF60A5FA),
            size: 18,
          ),
        ),
      );
    } else if (str.contains('youtube') ||
        str.contains('smarttube') ||
        str.contains('tizentube')) {
      return Container(
        width: 38,
        height: 26,
        decoration: BoxDecoration(
          color: const Color(0xFFFF0000),
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF0000).withValues(alpha: 0.4),
              blurRadius: 6,
            ),
          ],
        ),
        child: const Center(
          child: Icon(
            Icons.play_arrow_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
      );
    } else if (str.contains('projengmenu') || str.contains('projectivy')) {
      return Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF38BDF8), width: 1.5),
        ),
        child: const Center(
          child: Icon(
            Icons.grid_view_rounded,
            color: Color(0xFF38BDF8),
            size: 18,
          ),
        ),
      );
    } else if (str.contains('youcine')) {
      return Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF7C3AED), Color(0xFFC026D3)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Center(
          child: Icon(
            Icons.movie_filter_rounded,
            color: Colors.white,
            size: 18,
          ),
        ),
      );
    } else if (str.contains('isic') || str.contains('intelbras')) {
      return Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: const Color(0xFF00A34D),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Center(
          child: Icon(
            Icons.videocam_rounded,
            color: Colors.white,
            size: 18,
          ),
        ),
      );
    } else if (str.contains('netflix')) {
      return Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFE50914), width: 1.8),
        ),
        child: const Center(
          child: Text(
            'N',
            style: TextStyle(
              color: Color(0xFFE50914),
              fontSize: 18,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
        ),
      );
    } else if (str.contains('spotify') || str.contains('music')) {
      return Container(
        width: 30,
        height: 30,
        decoration: const BoxDecoration(
          color: Color(0xFF1ED760),
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: Icon(
            Icons.music_note_rounded,
            color: Colors.black,
            size: 18,
          ),
        ),
      );
    } else if (str.contains('prime') || str.contains('amazon')) {
      return Container(
        width: 34,
        height: 28,
        decoration: BoxDecoration(
          color: const Color(0xFF00A8E1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Center(
          child: Icon(
            Icons.play_arrow_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
      );
    } else if (str.contains('disney')) {
      return Container(
        width: 34,
        height: 28,
        decoration: BoxDecoration(
          color: const Color(0xFF113CCF),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Center(
          child: Icon(
            Icons.star_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
      );
    } else if (str.contains('globo')) {
      return Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: const Color(0xFFFF4D00),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Center(
          child: Icon(
            Icons.play_circle_filled_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
      );
    } else if (str.contains('max') || str.contains('hbo')) {
      return Container(
        width: 34,
        height: 28,
        decoration: BoxDecoration(
          color: const Color(0xFF002BE7),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Center(
          child: Text(
            'MAX',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ),
      );
    } else if (str.contains('twitch')) {
      return Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: const Color(0xFF9146FF),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Center(
          child: Icon(
            Icons.videogame_asset_rounded,
            color: Colors.white,
            size: 18,
          ),
        ),
      );
    } else if (str.contains('kodi')) {
      return Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: const Color(0xFF17B2E7),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Center(
          child: Icon(
            Icons.grid_view_rounded,
            color: Colors.white,
            size: 18,
          ),
        ),
      );
    } else if (str.contains('vending') || str.contains('play store') || str.contains('playstore')) {
      return Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: const Color(0xFF01875F),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Center(
          child: Icon(
            Icons.shopping_bag_rounded,
            color: Colors.white,
            size: 18,
          ),
        ),
      );
    } else if (str.contains('setting') || str.contains('configuraç')) {
      return Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: const Color(0xFF5F6368),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Center(
          child: Icon(
            Icons.settings_rounded,
            color: Colors.white,
            size: 18,
          ),
        ),
      );
    } else if (str.contains('adb') || str.contains('depuração')) {
      return Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: const Color(0xFF107C41),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Center(
          child: Icon(
            Icons.android_rounded,
            color: Colors.white,
            size: 18,
          ),
        ),
      );
    } else if (str.contains('tela inicial') ||
        str.contains('launcher') ||
        str.contains('home')) {
      return Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF64748B), width: 1.2),
        ),
        child: const Center(
          child: Icon(
            Icons.home_rounded,
            color: Colors.white,
            size: 18,
          ),
        ),
      );
    }
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: const Color(0xFF20222A),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white24, width: 1.0),
      ),
      child: const Center(
        child: Icon(
          Icons.android_rounded,
          color: Color(0xFF60CDFF),
          size: 18,
        ),
      ),
    );
  }
}
