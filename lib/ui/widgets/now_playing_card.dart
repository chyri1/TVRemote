import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/adb_service.dart';
import '../../core/keycodes.dart';
import '../../core/tv_controller.dart';
import '../theme.dart';

/// Modern "Now Playing" media banner displaying active app,
/// episode/song title, artist, thumbnail art in 16:9 and clickable progress bar
/// with real-time second-by-second smooth time interpolation between TV status updates.
class NowPlayingCard extends StatefulWidget {
  final TvController controller;

  const NowPlayingCard({super.key, required this.controller});

  @override
  State<NowPlayingCard> createState() => _NowPlayingCardState();
}

class _NowPlayingCardState extends State<NowPlayingCard> {
  Timer? _ticker;
  double? _baseTime;
  DateTime _lastUpdate = DateTime.now();
  String? _lastMediaTitle;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    AdbService.instance.addListener(_onControllerChanged);
    _syncFromController();
    _startTickerIfNeeded();
  }

  @override
  void didUpdateWidget(covariant NowPlayingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
    _syncFromController();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    _syncFromController();
    setState(() {});
  }

  void _syncFromController() {
    final info = widget.controller.nowPlaying;
    if (info == null) {
      _baseTime = null;
      _stopTicker();
      return;
    }

    // Se o título ou a mídia mudou, reinicia a base do tempo
    if (info.title != _lastMediaTitle) {
      _lastMediaTitle = info.title;
      _baseTime = info.currentTime;
      _lastUpdate = DateTime.now();
    } else if (info.currentTime != null) {
      // Se a diferença entre a estimativa atual e o dado recebido for > 1.2s ou estiver pausado,
      // resincroniza suavemente sem pular
      final currentEst = _interpolatedTime();
      if (currentEst == null ||
          (info.currentTime! - currentEst).abs() > 1.2 ||
          !info.isPlaying) {
        _baseTime = info.currentTime;
        _lastUpdate = DateTime.now();
      }
    }

    _startTickerIfNeeded();
  }

  void _startTickerIfNeeded() {
    final info = widget.controller.nowPlaying;
    if (info != null &&
        info.isPlaying &&
        info.duration != null &&
        info.duration! > 0) {
      if (_ticker == null || !_ticker!.isActive) {
        _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
          if (mounted) setState(() {});
        });
      }
    } else {
      _stopTicker();
    }
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    AdbService.instance.removeListener(_onControllerChanged);
    _stopTicker();
    super.dispose();
  }

  double? _interpolatedTime() {
    final info = widget.controller.nowPlaying;
    if (info == null || _baseTime == null) return null;
    if (!info.isPlaying) return _baseTime;
    final elapsedSecs =
        DateTime.now().difference(_lastUpdate).inMilliseconds / 1000.0;
    final total = _baseTime! + elapsedSecs;
    if (info.duration != null && info.duration! > 0) {
      return total.clamp(0.0, info.duration!);
    }
    return total;
  }

  String _formatDuration(double? seconds) {
    if (seconds == null || seconds.isNaN || seconds < 0) return '0:00';
    final totalSecs = seconds.toInt();
    final h = totalSecs ~/ 3600;
    final m = (totalSecs % 3600) ~/ 60;
    final s = totalSecs % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  void _onSeek(TapDownDetails details, double duration, double barWidth) {
    if (duration <= 0 || barWidth <= 0) return;
    final frac = (details.localPosition.dx / barWidth).clamp(0.0, 1.0);
    final targetSecs = frac * duration;
    _baseTime = targetSecs;
    _lastUpdate = DateTime.now();
    widget.controller.seekMedia(targetSecs);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);

    // Quando a tela está desligada (standby), mantém o card visível informando "Tela desligada"
    if (widget.controller.isScreenOff) {
      final tvName = widget.controller.selected?.name ?? 'Android TV';
      final lang = Localizations.localeOf(context).languageCode;
      final screenOffTitle = lang == 'en'
          ? 'Screen off'
          : (lang == 'es' ? 'Pantalla apagada' : 'Tela desligada');

      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          decoration: BoxDecoration(
            color: p.fill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.stroke, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 40,
                    height: 40,
                    color: p.fillHover,
                    child: Center(
                      child: Icon(
                        Icons.tv_off_rounded,
                        size: 22,
                        color: p.textDim,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        screenOffTitle,
                        softWrap: true,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        tvName,
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 11,
                          color: p.textDim,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final info = widget.controller.nowPlaying;
    // Caso não haja informação nem de vídeo nem de app, não mostre esse painel
    if (info == null || !info.isVisible) {
      return const SizedBox.shrink();
    }
    final hasImage = info.imageUrl != null && info.imageUrl!.isNotEmpty;
    final duration = info.duration;
    final current = _interpolatedTime() ?? info.currentTime;
    final hasTiming = duration != null && duration > 0 && current != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: p.fill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.stroke, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Caso consiga a imagem, coloque ela em 16:9 acima do nome do vídeo
            if (hasImage) ...[
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      info.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, err, stack) =>
                          _buildFallbackBanner(p, info),
                    ),
                    // Sutil gradiente na base da imagem
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 40,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.7),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (info.appName != null && info.appName!.isNotEmpty)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (info.isPlaying) ...[
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: p.accent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                              ],
                              Text(
                                info.appName!,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Informações abaixo da imagem 16:9
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            info.displayTitle,
                            softWrap: true,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              height: 1.25,
                            ),
                          ),
                          if (info.displaySubtitle != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              info.displaySubtitle!,
                              softWrap: true,
                              style: TextStyle(
                                fontSize: 11,
                                color: p.textDim,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      iconSize: 26,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 34,
                        minHeight: 34,
                      ),
                      color: p.accent,
                      icon: Icon(
                        info.isPlaying
                            ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_fill_rounded,
                      ),
                      onPressed: () =>
                          widget.controller.sendKey(KeyCode.mediaPlayPause),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Caso não tenha imagem: Ícone do app à esquerda mesmo
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: _buildFallbackIcon(p, info),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (info.isPlaying) ...[
                                Container(
                                  width: 6,
                                  height: 6,
                                  margin: const EdgeInsets.only(top: 4, right: 6),
                                  decoration: BoxDecoration(
                                    color: p.accent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                              Expanded(
                                child: Text(
                                  info.displayTitle,
                                  softWrap: true,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    height: 1.25,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (info.displaySubtitle != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              info.displaySubtitle!,
                              softWrap: true,
                              style: TextStyle(
                                fontSize: 11,
                                color: p.textDim,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      iconSize: 24,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      color: p.accent,
                      icon: Icon(
                        info.isPlaying
                            ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_fill_rounded,
                      ),
                      onPressed: () =>
                          widget.controller.sendKey(KeyCode.mediaPlayPause),
                    ),
                  ],
                ),
              ),
            ],

            // Barra de minutagem clicável com segundos em tempo real
            if (hasTiming) ...[
              LayoutBuilder(
                builder: (context, constraints) {
                  final barWidth = constraints.maxWidth;
                  final frac = (current / duration).clamp(0.0, 1.0);
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) =>
                        _onSeek(details, duration, barWidth),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            height: 10,
                            width: barWidth,
                            color: Colors.transparent,
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Stack(
                              alignment: Alignment.centerLeft,
                              children: [
                                Container(
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: p.stroke,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                FractionallySizedBox(
                                  widthFactor: frac,
                                  child: Container(
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: p.accent,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 2),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _formatDuration(current),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: p.textDim,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                                Text(
                                  _formatDuration(duration),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: p.textDim,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackBanner(Palette p, NowPlayingInfo info) {
    return Container(
      color: p.fillHover,
      child: Center(
        child: Icon(Icons.movie_outlined, size: 36, color: p.accent),
      ),
    );
  }

  Widget _buildFallbackIcon(Palette p, NowPlayingInfo info) {
    final str = '${info.appPackage ?? ''} ${info.appName ?? ''}'.toLowerCase();

    Widget? brand;
    if (str.contains('backdrop') ||
        str.contains('protetor de tela') ||
        str.contains('screen saver') ||
        str.contains('salvapantallas')) {
      brand = Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4285F4), Color(0xFF34A853)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(5),
        ),
        child: const Center(
          child: Icon(
            Icons.wallpaper_rounded,
            color: Colors.white,
            size: 16,
          ),
        ),
      );
    } else if (str.contains('mediatek.wwtv') ||
        str.contains('wwtv') ||
        str.contains('tv / hdmi / av')) {
      brand = Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: const Color(0xFF1E3A8A),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: const Color(0xFF60A5FA), width: 1.2),
        ),
        child: const Center(
          child: Icon(
            Icons.settings_input_hdmi_rounded,
            color: Color(0xFF60A5FA),
            size: 16,
          ),
        ),
      );
    } else if (str.contains('youtube') ||
        str.contains('smarttube') ||
        str.contains('tizentube')) {
      brand = Container(
        width: 30,
        height: 22,
        decoration: BoxDecoration(
          color: const Color(0xFFFF0000),
          borderRadius: BorderRadius.circular(5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF0000).withValues(alpha: 0.5),
              blurRadius: 6,
            ),
          ],
        ),
        child: const Center(
          child: Icon(
            Icons.play_arrow_rounded,
            color: Colors.white,
            size: 17,
          ),
        ),
      );
    } else if (str.contains('netflix')) {
      brand = Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: const Color(0xFFE50914), width: 1.8),
        ),
        child: const Center(
          child: Text(
            'N',
            style: TextStyle(
              color: Color(0xFFE50914),
              fontSize: 16,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
        ),
      );
    } else if (str.contains('spotify') || str.contains('music')) {
      brand = Container(
        width: 26,
        height: 26,
        decoration: const BoxDecoration(
          color: Color(0xFF1ED760),
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: Icon(
            Icons.music_note_rounded,
            color: Colors.black,
            size: 16,
          ),
        ),
      );
    } else if (str.contains('prime') || str.contains('amazon')) {
      brand = Container(
        width: 28,
        height: 24,
        decoration: BoxDecoration(
          color: const Color(0xFF00A8E1),
          borderRadius: BorderRadius.circular(5),
        ),
        child: const Center(
          child: Icon(
            Icons.play_arrow_rounded,
            color: Colors.white,
            size: 17,
          ),
        ),
      );
    } else if (str.contains('disney')) {
      brand = Container(
        width: 28,
        height: 24,
        decoration: BoxDecoration(
          color: const Color(0xFF113CCF),
          borderRadius: BorderRadius.circular(5),
        ),
        child: const Center(
          child: Icon(
            Icons.star_rounded,
            color: Colors.white,
            size: 17,
          ),
        ),
      );
    } else if (str.contains('globo')) {
      brand = Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: const Color(0xFFFF4D00),
          borderRadius: BorderRadius.circular(5),
        ),
        child: const Center(
          child: Icon(
            Icons.play_circle_filled_rounded,
            color: Colors.white,
            size: 17,
          ),
        ),
      );
    } else if (str.contains('max') || str.contains('hbo')) {
      brand = Container(
        width: 28,
        height: 24,
        decoration: BoxDecoration(
          color: const Color(0xFF002BE7),
          borderRadius: BorderRadius.circular(5),
        ),
        child: const Center(
          child: Text(
            'MAX',
            style: TextStyle(
              color: Colors.white,
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ),
      );
    } else if (str.contains('youcine')) {
      brand = Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF7C3AED), Color(0xFFC026D3)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(5),
        ),
        child: const Center(
          child: Icon(
            Icons.movie_filter_rounded,
            color: Colors.white,
            size: 16,
          ),
        ),
      );
    } else if (str.contains('isic') || str.contains('intelbras')) {
      brand = Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: const Color(0xFF00A34D),
          borderRadius: BorderRadius.circular(5),
        ),
        child: const Center(
          child: Icon(
            Icons.videocam_rounded,
            color: Colors.white,
            size: 16,
          ),
        ),
      );
    } else if (str.contains('projengmenu') || str.contains('projectivy')) {
      brand = Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: const Color(0xFF38BDF8), width: 1.3),
        ),
        child: const Center(
          child: Icon(
            Icons.grid_view_rounded,
            color: Color(0xFF38BDF8),
            size: 16,
          ),
        ),
      );
    } else if (str.contains('vending') || str.contains('play store') || str.contains('playstore')) {
      brand = Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: const Color(0xFF01875F),
          borderRadius: BorderRadius.circular(5),
        ),
        child: const Center(
          child: Icon(
            Icons.shopping_bag_rounded,
            color: Colors.white,
            size: 16,
          ),
        ),
      );
    } else if (str.contains('twitch')) {
      brand = Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: const Color(0xFF9146FF),
          borderRadius: BorderRadius.circular(5),
        ),
        child: const Center(
          child: Icon(
            Icons.videogame_asset_rounded,
            color: Colors.white,
            size: 16,
          ),
        ),
      );
    } else if (str.contains('kodi')) {
      brand = Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: const Color(0xFF17B2E7),
          borderRadius: BorderRadius.circular(5),
        ),
        child: const Center(
          child: Icon(
            Icons.grid_view_rounded,
            color: Colors.white,
            size: 16,
          ),
        ),
      );
    }

    brand ??= Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: p.fill,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: p.stroke),
      ),
      child: Center(
        child: Icon(Icons.android_rounded, size: 16, color: p.accent),
      ),
    );

    return Container(
      color: p.fillHover,
      child: Center(
        child: brand,
      ),
    );
  }
}
