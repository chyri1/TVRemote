import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../core/adb_service.dart';
import '../core/app_settings.dart';
import '../core/keycodes.dart';
import '../core/tv_controller.dart';
import '../l10n/gen/app_localizations.dart';
import 'remote_view.dart';
import 'theme.dart';
import 'widgets/adb_port_dialog.dart';

/// Tracks active detached mirror windows to enforce a max limit of 2 windows.
void logMirror(String msg) {
  try {
    final logFile = File('${Directory.systemTemp.path}\\tv_remote_mirror.log');
    final stamp = DateTime.now().toIso8601String();
    logFile.writeAsStringSync('[$stamp] $msg\n', mode: FileMode.append, flush: true);
  } catch (_) {}
}

/// Checks the operating system process list to ensure closed windows are pruned
/// and do not incorrectly prevent opening a new window.
class MirrorTracker {
  static File get _file =>
      File('${Directory.systemTemp.path}\\tv_remote_mirrors.txt');

  static final List<int> _activePids = [];
  static final List<Socket> _parentClients = [];
  static ServerSocket? _parentServer;
  static Socket? _childSocket;
  static TvController? _activeController;
  static String? _lastSyncedTvId;
  static final List<String> _pendingChildMessages = [];

  static int? get parentPort => _parentServer?.port;

  /// Registra o controller ativo para manter a seleção de TV em sincronia entre processos
  static void registerActiveController(TvController c) {
    _activeController = c;
    _lastSyncedTvId = c.selected?.id;
    AppSettings.onSettingsSaved = notifySettingsChanged;
    AdbService.onAppInfoBroadcast = notifyAppInfoChanged;
    c.addListener(() {
      final currentId = c.selected?.id;
      if (currentId != null && currentId != _lastSyncedTvId) {
        _lastSyncedTvId = currentId;
        notifyTvSelected(currentId);
      }
    });
  }

  static void _handleIncomingMessage(String text) {
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('SELECT_TV:')) {
        final id = trimmed.substring(10).trim();
        if (_activeController != null && _activeController!.selected?.id != id) {
          _lastSyncedTvId = id;
          _activeController!.selectTv(id);
        }
      } else if (trimmed == 'SETTINGS_CHANGED') {
        AppSettings.instance.load();
      } else if (trimmed.startsWith('APP_INFO:')) {
        final rest = trimmed.substring(9);
        final parts = rest.split(':::');
        if (parts.length >= 3) {
          final pkg = parts[0].isEmpty ? null : parts[0];
          final name = parts[1].isEmpty ? null : parts[1];
          final screenOn = parts[2] == 'true';
          AdbService.instance.updateForegroundApp(
            package: pkg,
            appName: name,
            isScreenOn: screenOn,
            broadcast: false,
          );
        }
      } else if (trimmed.startsWith('SEND_KEY:')) {
        final parts = trimmed.split(':');
        if (parts.length >= 2) {
          final keyCode = int.tryParse(parts[1]);
          final dirIndex = parts.length >= 3 ? int.tryParse(parts[2]) : null;
          final direction = dirIndex != null && dirIndex >= 0 && dirIndex < KeyDirection.values.length
              ? KeyDirection.values[dirIndex]
              : KeyDirection.short;
          if (keyCode != null && _activeController != null) {
            _activeController!.sendKey(keyCode, direction);
          }
        }
      } else if (trimmed.startsWith('SEND_TEXT:')) {
        final encoded = trimmed.substring(10).trim();
        try {
          final decoded = utf8.decode(base64Decode(encoded));
          _activeController?.sendText(decoded);
        } catch (_) {}
      } else if (trimmed.startsWith('LAUNCH_APP:')) {
        final encoded = trimmed.substring(11).trim();
        try {
          final decoded = utf8.decode(base64Decode(encoded));
          _activeController?.launchApp(decoded);
        } catch (_) {}
      } else if (trimmed.startsWith('SEEK_MEDIA:')) {
        final secs = double.tryParse(trimmed.substring(11).trim());
        if (secs != null) {
          _activeController?.seekMedia(secs);
        }
      }
    }
  }

  static void _sendToParent(String msg) {
    if (_childSocket != null) {
      try {
        _childSocket!.write(msg);
      } catch (_) {}
    } else {
      _pendingChildMessages.add(msg);
    }
  }

  static void relaySendKey(int keyCode, [int direction = 3]) {
    _sendToParent('SEND_KEY:$keyCode:$direction\n');
  }

  static void relaySendText(String text) {
    final encoded = base64Encode(utf8.encode(text));
    _sendToParent('SEND_TEXT:$encoded\n');
  }

  static void relayLaunchApp(String link) {
    final encoded = base64Encode(utf8.encode(link));
    _sendToParent('LAUNCH_APP:$encoded\n');
  }

  static void relaySeekMedia(double seconds) {
    _sendToParent('SEEK_MEDIA:$seconds\n');
  }

  static void notifyTvSelected(String tvId) {
    final msg = 'SELECT_TV:$tvId\n';
    for (final client in _parentClients) {
      try {
        client.write(msg);
      } catch (_) {}
    }
    if (_childSocket != null) {
      try {
        _childSocket!.write(msg);
      } catch (_) {}
    }
  }

  static void notifySettingsChanged() {
    const msg = 'SETTINGS_CHANGED\n';
    for (final client in _parentClients) {
      try {
        client.write(msg);
      } catch (_) {}
    }
    if (_childSocket != null) {
      try {
        _childSocket!.write(msg);
      } catch (_) {}
    }
  }

  static void notifyAppInfoChanged(String? pkg, String? appName, bool isScreenOn) {
    final msg = 'APP_INFO:${pkg ?? ""}:::${appName ?? ""}:::$isScreenOn\n';
    for (final client in _parentClients) {
      try {
        client.write(msg);
      } catch (_) {}
    }
    if (_childSocket != null) {
      try {
        _childSocket!.write(msg);
      } catch (_) {}
    }
  }

  /// Inicia um servidor TCP na porta local para funcionar como batimento cardíaco da tray.
  /// Quando a tray fecha (ou é morta com 'q'), o kernel encerra o socket e as janelas fecham instantaneamente.
  static Future<int?> initParentServer() async {
    if (_parentServer != null) return _parentServer!.port;
    try {
      _parentServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      logMirror('Parent heartbeat server started on port ${_parentServer!.port}');
      _parentServer!.listen((client) {
        _parentClients.add(client);
        logMirror('Parent server accepted client on port ${client.remotePort}');
        client.listen(
          (data) {
            try {
              _handleIncomingMessage(utf8.decode(data));
            } catch (_) {}
          },
          onDone: () {
            logMirror('Parent server: client disconnected from port ${client.remotePort}');
            _parentClients.remove(client);
          },
          onError: (e) {
            logMirror('Parent server: client error: $e');
            _parentClients.remove(client);
          },
          cancelOnError: false,
        );
      });
      return _parentServer!.port;
    } catch (e) {
      logMirror('MirrorTracker parent server error: $e');
      return null;
    }
  }

  /// Verifica se um PID ainda está em execução na tabela de processos do Windows
  static Future<bool> isPidAlive(int? targetPid) async {
    if (targetPid == null || targetPid <= 0) return true;
    try {
      final res = await Process.run('tasklist', ['/FI', 'PID eq $targetPid', '/NH']);
      if (res.exitCode == 0) {
        final out = res.stdout.toString();
        return out.contains(targetPid.toString());
      }
    } catch (_) {}
    return true;
  }

  /// Inicia monitoramento na janela destacada com logs e dupla verificação (TCP + PID)
  static void startHeartbeatMonitoring({int? parentPort, int? parentPid}) {
    logMirror('Child mirror window started. PID: $pid, Parent PID: $parentPid, Parent Port: $parentPort');

    // Registra os handlers de relay para que qualquer comando acionado pelo teclado ou painel da janela
    // seja transmitido via IPC instantaneamente para o processo pai (que mantém a conexão TLS com a TV).
    TvController.relayKeyHandler = (keyCode, direction) {
      relaySendKey(keyCode, direction.index);
    };
    TvController.relayTextHandler = (text) {
      relaySendText(text);
    };
    TvController.relayLaunchAppHandler = (link) {
      relayLaunchApp(link);
    };
    TvController.relaySeekMediaHandler = (seconds) {
      relaySeekMedia(seconds);
    };

    // 1. Conexão TCP Heartbeat
    if (parentPort != null && parentPort > 0) {
      Socket.connect(
        InternetAddress.loopbackIPv4,
        parentPort,
        timeout: const Duration(seconds: 5),
      ).then((socket) {
        _childSocket = socket;
        logMirror('Child connected to parent TCP heartbeat');
        for (final m in _pendingChildMessages) {
          try {
            _childSocket!.write(m);
          } catch (_) {}
        }
        _pendingChildMessages.clear();
        socket.listen(
          (data) {
            try {
              _handleIncomingMessage(utf8.decode(data));
            } catch (_) {}
          },
          onDone: () async {
            logMirror('Parent TCP socket onDone');
            final alive = await isPidAlive(parentPid);
            logMirror('Parent PID $parentPid alive check: $alive');
            if (!alive) {
              logMirror('Parent is dead. Exiting child window.');
              exit(0);
            }
          },
          onError: (e) async {
            logMirror('Parent TCP socket onError: $e');
            final alive = await isPidAlive(parentPid);
            logMirror('Parent PID $parentPid alive check: $alive');
            if (!alive) {
              logMirror('Parent is dead. Exiting child window.');
              exit(0);
            }
          },
          cancelOnError: false,
        );
      }).catchError((e) {
        logMirror('Could not connect to parent TCP heartbeat: $e');
      });
    }

    // 2. Verificação periódica do PID do pai a cada 3 segundos
    if (parentPid != null && parentPid > 0) {
      Timer.periodic(const Duration(seconds: 3), (timer) async {
        final alive = await isPidAlive(parentPid);
        if (!alive) {
          logMirror('Parent PID $parentPid dead in periodic check. Exiting child window.');
          timer.cancel();
          exit(0);
        }
      });
    }
  }

  /// Conecta a janela filha destacada ao servidor do processo pai.
  static void connectToParentHeartbeat(int port) {
    startHeartbeatMonitoring(parentPort: port);
  }

  /// Mata todas as janelas de espelhamento filhas conhecidas
  static void killAllMirrors() {
    try {
      _parentServer?.close();
      _parentServer = null;
      final pids = getActivePidsFromFile();
      for (final p in pids) {
        if (p != pid) {
          try {
            Process.killPid(p);
          } catch (_) {}
        }
      }
      _activePids.clear();
      if (_file.existsSync()) {
        _file.deleteSync();
      }
    } catch (_) {}
  }

  static List<int> getActivePidsFromFile() {
    try {
      if (!_file.existsSync()) return [];
      final lines = _file.readAsLinesSync();
      final pids = <int>[];
      for (final line in lines) {
        final p = int.tryParse(line.trim());
        if (p != null) pids.add(p);
      }
      return pids;
    } catch (_) {
      return [];
    }
  }

  static void saveActivePidsToFile(List<int> pids) {
    try {
      _file.writeAsStringSync(pids.toSet().join('\n'));
    } catch (_) {}
  }

  static Future<Set<int>> _getRunningExePids() async {
    try {
      final exeName =
          Platform.resolvedExecutable.split(Platform.pathSeparator).last;
      final res =
          await Process.run('tasklist', ['/FI', 'IMAGENAME eq $exeName', '/NH']);
      if (res.exitCode != 0) return {};
      final output = res.stdout.toString();
      final pids = <int>{};
      final regex = RegExp(RegExp.escape(exeName) + r'\s+(\d+)', caseSensitive: false);
      for (final match in regex.allMatches(output)) {
        final p = int.tryParse(match.group(1) ?? '');
        if (p != null) pids.add(p);
      }
      return pids;
    } catch (_) {
      return {};
    }
  }

  /// Prunes any dead/closed PIDs and returns the list of actually running mirror windows.
  static Future<List<int>> getAliveMirrorPids() async {
    final running = await _getRunningExePids();
    running.remove(pid); // Remove the current process itself

    // Re-sync with file-recorded PIDs
    final fromFile = getActivePidsFromFile();
    for (final p in fromFile) {
      if (!_activePids.contains(p)) _activePids.add(p);
    }

    if (running.isNotEmpty) {
      // Remove any PIDs that are no longer running in Windows
      _activePids.retainWhere((p) => running.contains(p));
      // Ensure any running detached mirror process is tracked
      for (final p in running) {
        if (!_activePids.contains(p)) _activePids.add(p);
      }
    } else {
      _activePids.clear();
    }

    saveActivePidsToFile(_activePids);
    return List<int>.from(_activePids);
  }

  static Future<bool> canOpenNew() async {
    // Fast path: Se não temos 2 janelas registradas, permite abrir instantaneamente sem executar tasklist!
    if (_activePids.length < 2) {
      final filePids = getActivePidsFromFile();
      if (filePids.length < 2) return true;
    }
    final alive = await getAliveMirrorPids();
    return alive.length < 2;
  }

  static void trackPid(int p) {
    if (!_activePids.contains(p)) {
      _activePids.add(p);
      saveActivePidsToFile(_activePids);
    }
  }

  static void removePid(int p) {
    _activePids.remove(p);
    saveActivePidsToFile(_activePids);
  }

  static void registerCurrentPid() {
    try {
      final pids = getActivePidsFromFile();
      final myPid = pid;
      if (!pids.contains(myPid)) {
        pids.add(myPid);
        saveActivePidsToFile(pids);
      }
    } catch (_) {}
  }

  static void unregisterCurrentPid() {
    try {
      final pids = getActivePidsFromFile();
      pids.remove(pid);
      saveActivePidsToFile(pids);
    } catch (_) {}
  }
}

/// Standalone Window Application for TV Screen Mirror.
/// Runs in a dedicated native Windows window.
class MirrorWindowApp extends StatefulWidget {
  final TvController controller;
  final String tvName;
  final String tvHost;
  final MirrorMode? initialMode;

  const MirrorWindowApp({
    super.key,
    required this.controller,
    required this.tvName,
    required this.tvHost,
    this.initialMode,
  });

  @override
  State<MirrorWindowApp> createState() => _MirrorWindowAppState();
}

class _MirrorWindowAppState extends State<MirrorWindowApp> with WindowListener {
  Timer? _mediaTicker;
  double? _mediaBaseTime;
  DateTime _lastMediaUpdate = DateTime.now();
  String? _lastMediaTitle;

  @override
  void onWindowMaximize() {
    setState(() {});
  }

  @override
  void onWindowUnmaximize() {
    setState(() {});
  }

  @override
  void onWindowResize() {
    setState(() {});
  }

  @override
  void onWindowEnterFullScreen() {
    if (mounted) setState(() => _isFullScreen = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) setState(() => _isFullScreen = false);
  }

  void _syncFromController() {
    final info = widget.controller.nowPlaying;
    if (info == null) {
      _mediaBaseTime = null;
      _stopTicker();
      return;
    }

    if (info.title != _lastMediaTitle) {
      _lastMediaTitle = info.title;
      _mediaBaseTime = info.currentTime;
      _lastMediaUpdate = DateTime.now();
    } else if (info.currentTime != null) {
      final currentEst = _interpolatedMediaTime();
      if (currentEst == null ||
          (info.currentTime! - currentEst).abs() > 1.2 ||
          !info.isPlaying) {
        _mediaBaseTime = info.currentTime;
        _lastMediaUpdate = DateTime.now();
      }
    }

    _startTickerIfNeeded();
  }

  void _onControllerChanged() {
    _syncFromController();
    if (mounted) setState(() {});
  }

  void _startTickerIfNeeded() {
    final info = widget.controller.nowPlaying;
    if (info != null &&
        info.isPlaying &&
        info.duration != null &&
        info.duration! > 0) {
      if (_mediaTicker == null || !_mediaTicker!.isActive) {
        _mediaTicker = Timer.periodic(const Duration(milliseconds: 500), (_) {
          if (mounted) setState(() {});
        });
      }
    } else {
      _stopTicker();
    }
  }

  void _stopTicker() {
    _mediaTicker?.cancel();
    _mediaTicker = null;
  }

  double? _interpolatedMediaTime() {
    final info = widget.controller.nowPlaying;
    if (info == null || _mediaBaseTime == null) return null;
    if (!info.isPlaying) return _mediaBaseTime;
    final elapsedSecs =
        DateTime.now().difference(_lastMediaUpdate).inMilliseconds / 1000.0;
    final total = _mediaBaseTime! + elapsedSecs;
    if (info.duration != null && info.duration! > 0) {
      return total.clamp(0.0, info.duration!);
    }
    return total;
  }

  void _onSeek(double targetSecs) {
    _mediaBaseTime = targetSecs;
    _lastMediaUpdate = DateTime.now();
    widget.controller.seekMedia(targetSecs);
    setState(() {});
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

  Widget _buildBarIconButton({
    required Widget icon,
    required String tooltip,
    required VoidCallback onPressed,
    double size = 36,
    double iconSize = 20,
  }) {
    return IconButton(
      icon: icon,
      tooltip: tooltip,
      iconSize: iconSize,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: size, minHeight: size),
      onPressed: onPressed,
    );
  }

  Widget? _buildAppBrandIcon(String? pkg, String name) {
    final str = '${pkg ?? ''} $name'.toLowerCase();
    if (str.contains('backdrop') ||
        str.contains('protetor de tela') ||
        str.contains('screen saver') ||
        str.contains('salvapantallas')) {
      return Container(
        width: 22,
        height: 22,
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
            size: 14,
          ),
        ),
      );
    } else if (str.contains('mediatek.wwtv') ||
        str.contains('wwtv') ||
        str.contains('tv / hdmi / av')) {
      return Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: const Color(0xFF1E3A8A),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: const Color(0xFF60A5FA), width: 1.0),
        ),
        child: const Center(
          child: Icon(
            Icons.settings_input_hdmi_rounded,
            color: Color(0xFF60A5FA),
            size: 14,
          ),
        ),
      );
    } else if (str.contains('youtube') ||
        str.contains('smarttube') ||
        str.contains('tizentube')) {
      return Container(
        width: 26,
        height: 18,
        decoration: BoxDecoration(
          color: const Color(0xFFFF0000),
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF0000).withValues(alpha: 0.4),
              blurRadius: 4,
            ),
          ],
        ),
        child: const Center(
          child: Icon(
            Icons.play_arrow_rounded,
            color: Colors.white,
            size: 16,
          ),
        ),
      );
    } else if (str.contains('projengmenu') || str.contains('projectivy')) {
      return Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: const Color(0xFF38BDF8), width: 1.2),
        ),
        child: const Center(
          child: Icon(
            Icons.grid_view_rounded,
            color: Color(0xFF38BDF8),
            size: 14,
          ),
        ),
      );
    } else if (str.contains('sendfilestotv') || str.contains('send files to tv')) {
      return Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0072FF), Color(0xFF00C6FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(5),
        ),
        child: const Center(
          child: Icon(
            Icons.send_to_mobile_rounded,
            color: Colors.white,
            size: 13,
          ),
        ),
      );
    } else if (str.contains('bitchord')) {
      return Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF8B5CF6), Color(0xFF06B6D4)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(5),
        ),
        child: const Center(
          child: Icon(
            Icons.graphic_eq_rounded,
            color: Colors.white,
            size: 13,
          ),
        ),
      );
    } else if (str.contains('youcine')) {
      return Container(
        width: 22,
        height: 22,
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
            size: 14,
          ),
        ),
      );
    } else if (str.contains('isic') || str.contains('intelbras')) {
      return Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: const Color(0xFF00A34D),
          borderRadius: BorderRadius.circular(5),
        ),
        child: const Center(
          child: Icon(
            Icons.videocam_rounded,
            color: Colors.white,
            size: 14,
          ),
        ),
      );
    } else if (str.contains('netflix')) {
      return Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFFE50914), width: 1.5),
        ),
        child: const Center(
          child: Text(
            'N',
            style: TextStyle(
              color: Color(0xFFE50914),
              fontSize: 14,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
        ),
      );
    } else if (str.contains('spotify') || str.contains('music')) {
      return Container(
        width: 22,
        height: 22,
        decoration: const BoxDecoration(
          color: Color(0xFF1ED760),
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: Icon(
            Icons.music_note_rounded,
            color: Colors.black,
            size: 15,
          ),
        ),
      );
    } else if (str.contains('prime') || str.contains('amazon')) {
      return Container(
        width: 24,
        height: 20,
        decoration: BoxDecoration(
          color: const Color(0xFF00A8E1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Center(
          child: Icon(
            Icons.play_arrow_rounded,
            color: Colors.white,
            size: 16,
          ),
        ),
      );
    } else if (str.contains('disney')) {
      return Container(
        width: 24,
        height: 20,
        decoration: BoxDecoration(
          color: const Color(0xFF113CCF),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Center(
          child: Icon(
            Icons.star_rounded,
            color: Colors.white,
            size: 16,
          ),
        ),
      );
    } else if (str.contains('globo')) {
      return Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: const Color(0xFFFF4D00),
          borderRadius: BorderRadius.circular(5),
        ),
        child: const Center(
          child: Icon(
            Icons.play_circle_filled_rounded,
            color: Colors.white,
            size: 16,
          ),
        ),
      );
    } else if (str.contains('max') || str.contains('hbo')) {
      return Container(
        width: 24,
        height: 20,
        decoration: BoxDecoration(
          color: const Color(0xFF002BE7),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Center(
          child: Text(
            'MAX',
            style: TextStyle(
              color: Colors.white,
              fontSize: 8.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ),
      );
    } else if (str.contains('twitch')) {
      return Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: const Color(0xFF9146FF),
          borderRadius: BorderRadius.circular(5),
        ),
        child: const Center(
          child: Icon(
            Icons.videogame_asset_rounded,
            color: Colors.white,
            size: 15,
          ),
        ),
      );
    } else if (str.contains('kodi')) {
      return Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: const Color(0xFF17B2E7),
          borderRadius: BorderRadius.circular(5),
        ),
        child: const Center(
          child: Icon(
            Icons.grid_view_rounded,
            color: Colors.white,
            size: 15,
          ),
        ),
      );
    } else if (str.contains('vending') || str.contains('play store') || str.contains('playstore')) {
      return Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: const Color(0xFF01875F),
          borderRadius: BorderRadius.circular(5),
        ),
        child: const Center(
          child: Icon(
            Icons.shopping_bag_rounded,
            color: Colors.white,
            size: 15,
          ),
        ),
      );
    } else if (str.contains('setting') || str.contains('configuraç')) {
      return Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: const Color(0xFF5F6368),
          borderRadius: BorderRadius.circular(5),
        ),
        child: const Center(
          child: Icon(
            Icons.settings_rounded,
            color: Colors.white,
            size: 15,
          ),
        ),
      );
    } else if (str.contains('adb') || str.contains('depuração')) {
      return Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: const Color(0xFF107C41),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Center(
          child: Icon(
            Icons.android_rounded,
            color: Colors.white,
            size: 15,
          ),
        ),
      );
    } else if (str.contains('tela inicial') ||
        str.contains('launcher') ||
        str.contains('home')) {
      return Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: const Color(0xFF64748B), width: 1.0),
        ),
        child: const Center(
          child: Icon(
            Icons.home_rounded,
            color: Colors.white,
            size: 14,
          ),
        ),
      );
    }
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: const Color(0xFF20222A),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: Colors.white24, width: 0.8),
      ),
      child: const Center(
        child: Icon(
          Icons.android_rounded,
          color: Color(0xFF60CDFF),
          size: 14,
        ),
      ),
    );
  }

  Widget _buildModeTogglePill({
    required bool isAdbMode,
    required Function(MirrorMode) onSelectMode,
    required AdbService adb,
    required String tvHost,
  }) {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3.5),
      decoration: BoxDecoration(
        color: const Color(0xFF141519),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2A2C34), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Media / Cast Option (TV screen with stand and play arrow inside, matching mockup)
          Tooltip(
            message: 'Modo Mídia / Transmissão',
            child: InkWell(
              onTap: () => onSelectMode(MirrorMode.castMedia),
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 52,
                height: 33,
                decoration: BoxDecoration(
                  color: !isAdbMode ? const Color(0xFF38404E) : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        Icons.tv_rounded,
                        size: 23,
                        color: !isAdbMode ? Colors.white : Colors.white60,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3.5),
                        child: Icon(
                          Icons.play_arrow_rounded,
                          size: 11,
                          color: !isAdbMode ? Colors.white : Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 3),
          // ADB Option (Android robot head, matching mockup)
          Tooltip(
            message: appTr(
              pt: 'Modo Depuração ADB',
              en: 'ADB Debugging Mode',
              es: 'Modo Depuración ADB',
            ),
            child: InkWell(
              onTap: () {
                onSelectMode(MirrorMode.adbScreen);
                if (adb.state == AdbState.idle) {
                  adb.connectToTv(tvHost);
                }
              },
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 52,
                height: 33,
                decoration: BoxDecoration(
                  color: isAdbMode ? const Color(0xFF38404E) : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Icon(
                    Icons.android_rounded,
                    size: 23,
                    color: isAdbMode ? Colors.white : Colors.white60,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _alwaysOnTop = true;
  bool _isFullScreen = false;
  bool _wasMaximizedBeforeFullScreen = false;
  final FocusNode _focusNode = FocusNode();
  LogicalKeyboardKey? _heldKey;
  Timer? _keyInitialDelayTimer;
  Timer? _keyRepeatTimer;

  @override
  void onWindowFocus() {
    _focusNode.requestFocus();
  }

  @override
  void onWindowBlur() {
    _cancelKeyRepeat();
  }

  void _cancelKeyRepeat() {
    _heldKey = null;
    _keyInitialDelayTimer?.cancel();
    _keyInitialDelayTimer = null;
    _keyRepeatTimer?.cancel();
    _keyRepeatTimer = null;
  }

  bool _handleGlobalKeyEvent(KeyEvent event) {
    // Se o usuário está interagindo com qualquer campo de texto na janela (ex: comando manual no RemoteView),
    // não intercepta para permitir navegação e digitação local.
    final primaryFocus = FocusManager.instance.primaryFocus;
    final isEditingText = primaryFocus != null &&
        (primaryFocus.context?.widget is EditableText ||
            primaryFocus.context?.findAncestorWidgetOfExactType<EditableText>() != null ||
            primaryFocus.debugLabel?.contains('EditableText') == true);
    if (isEditingText) {
      _cancelKeyRepeat();
      return false;
    }

    final key = event.logicalKey;
    final c = widget.controller;

    // Se a tecla foi liberada, cancela imediatamente a repetição contínua
    if (event is KeyUpEvent) {
      if (_heldKey == key) {
        _cancelKeyRepeat();
      }
      return false;
    }

    // Teclas direcionais e de repetição contínua
    int? repeatableKeyCode;
    if (key == LogicalKeyboardKey.arrowUp) {
      repeatableKeyCode = KeyCode.dpadUp;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      repeatableKeyCode = KeyCode.dpadDown;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      repeatableKeyCode = KeyCode.dpadLeft;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      repeatableKeyCode = KeyCode.dpadRight;
    } else if (key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.numpadAdd) {
      repeatableKeyCode = KeyCode.volumeUp;
    } else if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      repeatableKeyCode = KeyCode.volumeDown;
    } else if (key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.delete) {
      repeatableKeyCode = KeyCode.del;
    }

    if (repeatableKeyCode != null) {
      if (event is KeyDownEvent) {
        if (_heldKey == key) {
          return true;
        }

        _cancelKeyRepeat();
        _heldKey = key;
        final code = repeatableKeyCode;

        void sendKeyAction(int code) {
          final step = (code == KeyCode.volumeUp || code == KeyCode.volumeDown)
              ? AppSettings.instance.volumeStep
              : 1;
          for (int i = 0; i < step; i++) {
            c.sendKey(code);
          }
        }

        // 1. Envia imediatamente no primeiro toque
        sendKeyAction(code);
        if (code == KeyCode.del) {
          c.reportExternalBackspace();
        }

        // 2. Se continuar segurando a seta, dispara comandos contínuos a cada 110ms
        _keyInitialDelayTimer = Timer(const Duration(milliseconds: 300), () {
          _keyRepeatTimer =
              Timer.periodic(const Duration(milliseconds: 110), (_) {
            if (_heldKey == key && mounted) {
              sendKeyAction(code);
              if (code == KeyCode.del) {
                c.reportExternalBackspace();
              }
            }
          });
        });

        return true;
      } else if (event is KeyRepeatEvent) {
        return true;
      }
    }

    // Comandos de clique único (Enter, Voltar, Home, etc.)
    if (event is KeyDownEvent) {
      if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter ||
          key == LogicalKeyboardKey.select) {
        c.sendKey(KeyCode.dpadCenter);
        return true;
      } else if (key == LogicalKeyboardKey.f11) {
        _toggleFullScreen();
        return true;
      } else if (key == LogicalKeyboardKey.escape) {
        if (_isFullScreen) {
          _toggleFullScreen();
          return true;
        }
        c.sendKey(KeyCode.back);
        return true;
      } else if (key == LogicalKeyboardKey.home) {
        c.sendKey(KeyCode.home);
        return true;
      } else if (key == LogicalKeyboardKey.pageUp) {
        c.sendKey(KeyCode.channelUp);
        return true;
      } else if (key == LogicalKeyboardKey.pageDown) {
        c.sendKey(KeyCode.channelDown);
        return true;
      } else if (key == LogicalKeyboardKey.audioVolumeMute) {
        c.sendKey(KeyCode.volumeMute);
        return true;
      } else if (key == LogicalKeyboardKey.mediaPlayPause) {
        c.sendKey(KeyCode.mediaPlayPause);
        return true;
      } else if (key == LogicalKeyboardKey.mediaStop) {
        c.sendKey(KeyCode.mediaStop);
        return true;
      } else if (key == LogicalKeyboardKey.mediaTrackNext) {
        c.sendKey(KeyCode.mediaNext);
        return true;
      } else if (key == LogicalKeyboardKey.mediaTrackPrevious) {
        c.sendKey(KeyCode.mediaPrevious);
        return true;
      } else if (event.character != null &&
          event.character!.isNotEmpty &&
          !HardwareKeyboard.instance.isControlPressed &&
          !HardwareKeyboard.instance.isAltPressed &&
          !HardwareKeyboard.instance.isMetaPressed) {
        // Digitação em tempo real do teclado do PC direto na TV
        c.sendText(event.character!);
        c.reportExternalCharacter(event.character!);
        return true;
      }
    }

    return false;
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialMode != null) {
      AdbService.instance.setMode(widget.initialMode!);
      if (widget.initialMode == MirrorMode.adbScreen &&
          AdbService.instance.state == AdbState.idle) {
        AdbService.instance.connectToTv(widget.tvHost);
      }
    }
    windowManager.addListener(this);
    MirrorTracker.registerCurrentPid();
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
    widget.controller.addListener(_onControllerChanged);
    _syncFromController();
  }

  @override
  void onWindowClose() {
    MirrorTracker.unregisterCurrentPid();
    windowManager.destroy();
    exit(0);
  }

  Future<void> _toggleAlwaysOnTop() async {
    final next = !_alwaysOnTop;
    await windowManager.setAlwaysOnTop(next);
    setState(() => _alwaysOnTop = next);
  }

  Future<void> _toggleFullScreen() async {
    final currentlyFull = await windowManager.isFullScreen();
    final willBeFullScreen = !currentlyFull;

    if (willBeFullScreen) {
      final isMax = await windowManager.isMaximized();
      _wasMaximizedBeforeFullScreen = isMax;
      if (isMax) {
        await windowManager.unmaximize();
        // Breve intervalo para o Win32 liberar os estilos WS_MAXIMIZE
        await Future.delayed(const Duration(milliseconds: 80));
      }
      await windowManager.setFullScreen(true);
      if (mounted) setState(() => _isFullScreen = true);
    } else {
      await windowManager.setFullScreen(false);
      await Future.delayed(const Duration(milliseconds: 80));
      if (_wasMaximizedBeforeFullScreen) {
        await windowManager.maximize();
        _wasMaximizedBeforeFullScreen = false;
      }
      if (mounted) setState(() => _isFullScreen = false);
    }
  }

  @override
  void dispose() {
    MirrorTracker.unregisterCurrentPid();
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    _cancelKeyRepeat();
    _focusNode.dispose();
    _adbCmdController.dispose();
    _terminalScrollController.dispose();
    windowManager.removeListener(this);
    widget.controller.removeListener(_onControllerChanged);
    _stopTicker();
    super.dispose();
  }

  bool _showRemotePanel = false;
  bool _showAdbTerminal = false;
  final TextEditingController _adbCmdController = TextEditingController();
  final ScrollController _terminalScrollController = ScrollController();
  bool _isExecutingAdbCmd = false;

  Future<void> _executeAdbCommand(AdbService adb, String rawCmd) async {
    final cmd = rawCmd.trim();
    if (cmd.isEmpty || _isExecutingAdbCmd) return;
    _adbCmdController.clear();
    setState(() => _isExecutingAdbCmd = true);
    try {
      await adb.runCommand(cmd);
      await Future.delayed(const Duration(milliseconds: 100));
      if (_terminalScrollController.hasClients) {
        _terminalScrollController.animateTo(
          _terminalScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExecutingAdbCmd = false);
      }
    }
  }

  Future<void> _toggleRemotePanel() async {
    final next = !_showRemotePanel;
    setState(() => _showRemotePanel = next);

    try {
      final isMax = await windowManager.isMaximized();
      final isFull = await windowManager.isFullScreen();
      if (!isMax && !isFull) {
        final currentSize = await windowManager.getSize();
        final delta = next ? 350.0 : -350.0;
        final newWidth = (currentSize.width + delta).clamp(640.0, 3840.0);
        await windowManager.setSize(Size(newWidth, currentSize.height));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        final settings = AppSettings.instance;
        final currentLang = settings.locale?.languageCode ?? 'system';
        final effective = settings.effectiveLocale;
        return MaterialApp(
          key: ValueKey('mirror_app_${currentLang}_${effective.languageCode}_${settings.themeMode}'),
          debugShowCheckedModeBanner: false,
          title: 'TV Remote - Tela da TV (${widget.tvName})',
          theme: buildTheme(Brightness.dark),
          locale: settings.locale ?? effective,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            backgroundColor: const Color(0xFF0F0F12),
            body: Focus(
              focusNode: _focusNode,
              autofocus: true,
              child: Builder(
              builder: (ctx) {
                final p = Palette.of(ctx);
                return ListenableBuilder(
                  listenable: Listenable.merge([widget.controller, AdbService.instance]),
                  builder: (context, _) {
            final info = widget.controller.nowPlaying;
            final isPlaying = info?.isPlaying ?? false;
            final hasImage = info?.imageUrl != null && info!.imageUrl!.isNotEmpty;
            final adb = AdbService.instance;
            final isAdbMode = adb.mode == MirrorMode.adbScreen;
            final activeAppPkg = adb.currentAppPackage ?? info?.appPackage;
            final friendlyFromPkg = NowPlayingInfo.friendlyPackageName(activeAppPkg);
            final isCastPlaying = (info?.isPlaying == true || info?.hasMedia == true);
            final rawAppName = (!isCastPlaying && adb.currentAppName != null && adb.currentAppName != 'Tela Inicial')
                ? adb.currentAppName
                : (friendlyFromPkg ?? adb.currentAppName ?? info?.appName);
            final isScreenOff = widget.controller.isScreenOff;
            final adbLabel = appTr(pt: 'Depuração ADB', en: 'ADB Debugging', es: 'Depuración ADB');
            final screenOffLabel = appTr(pt: 'Tela desligada', en: 'Screen off', es: 'Pantalla apagada');
            final homeScreenLabel = appTr(pt: 'Tela Inicial', en: 'Home Screen', es: 'Pantalla de inicio');
            final String effectiveAppName;
            if (isScreenOff) {
              effectiveAppName = screenOffLabel;
            } else if (AppSettings.instance.showRawPackageName) {
              effectiveAppName = (activeAppPkg != null && activeAppPkg.isNotEmpty)
                  ? activeAppPkg
                  : (rawAppName != null && rawAppName.isNotEmpty ? rawAppName : 'Android TV');
            } else {
              final friendly = friendlyFromPkg;
              if (friendly != null && friendly.isNotEmpty && friendly != 'Tela Inicial') {
                effectiveAppName = friendly;
              } else if (rawAppName != null &&
                  rawAppName.isNotEmpty &&
                  rawAppName != 'Default Media Receiver' &&
                  rawAppName != 'Tela Inicial' &&
                  rawAppName != homeScreenLabel) {
                final rLow = rawAppName.toLowerCase();
                if (rLow.contains('backdrop') || rLow == 'screen saver' || rLow == 'ambient mode') {
                  effectiveAppName = getScreenSaverTitle();
                } else if (rLow.contains('projengmenu') || rLow.contains('projectivy')) {
                  effectiveAppName = 'Projectivy Launcher';
                } else if (rLow.contains('sendfilestotv') || rLow.contains('send files to tv')) {
                  effectiveAppName = 'Send Files to TV';
                } else if (rLow.contains('bitchord')) {
                  effectiveAppName = 'BitChord';
                } else if (rLow.contains('youcine')) {
                  effectiveAppName = 'YouCine';
                } else if (rLow.contains('isiclite') || rLow.contains('intelbras')) {
                  effectiveAppName = 'ISIC Lite';
                } else if (rLow.contains('mediatek.wwtv') || rLow.contains('wwtv')) {
                  effectiveAppName = 'TV / HDMI / AV';
                } else {
                  effectiveAppName = rawAppName;
                }
              } else {
                if (info?.hasMedia == true || (info?.title != null && info!.title!.isNotEmpty)) {
                  effectiveAppName = 'YouTube';
                } else if (activeAppPkg != null &&
                    activeAppPkg.isNotEmpty &&
                    activeAppPkg != 'Tela Inicial') {
                  effectiveAppName = activeAppPkg;
                } else if (rawAppName != null &&
                    rawAppName.isNotEmpty &&
                    rawAppName != 'Tela Inicial') {
                  effectiveAppName = rawAppName;
                } else {
                  effectiveAppName = isAdbMode ? adbLabel : homeScreenLabel;
                }
              }
            }

            final hasApp = !isScreenOff &&
                effectiveAppName != adbLabel &&
                effectiveAppName != screenOffLabel;
            final mediaTitle = isScreenOff
                ? screenOffLabel
                : ((info?.title != null && info!.title!.isNotEmpty)
                    ? info.title!
                    : (hasApp
                        ? effectiveAppName
                        : (isAdbMode
                            ? appTr(pt: 'Depuração de Tela ADB', en: 'ADB Screen Debugging', es: 'Depuración de pantalla ADB')
                            : (widget.tvName.isNotEmpty ? widget.tvName : 'Android TV'))));
            final mediaChannel = isScreenOff
                ? null
                : ((info?.artist != null && info!.artist!.isNotEmpty)
                    ? info.artist!
                    : (info?.displaySubtitle != null &&
                            info!.displaySubtitle!.isNotEmpty &&
                            info.displaySubtitle != info.displayTitle &&
                            info.displaySubtitle != info.appName
                        ? info.displaySubtitle
                        : null));

            return Row(
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                // Video / Mirror Feed (Cast Media vs ADB Screencap)
                Center(
                  child: isScreenOff
                      ? _buildFallback(
                          tvName: widget.tvName,
                          appName: 'Tela desligada',
                          appPackage: null,
                        )
                      : (!isAdbMode
                          ? (hasImage
                              ? AspectRatio(
                                  aspectRatio: 16 / 9,
                                  child: Image.network(
                                    info.imageUrl!,
                                    fit: BoxFit.contain,
                                    errorBuilder: (ctx, err, stack) =>
                                        _buildFallback(
                                      tvName: widget.tvName,
                                      appName: effectiveAppName,
                                      appPackage: activeAppPkg,
                                    ),
                                  ),
                                )
                              : _buildFallback(
                                  tvName: widget.tvName,
                                  appName: effectiveAppName,
                                  appPackage: activeAppPkg,
                                ))
                          : (adb.state == AdbState.connected &&
                                  adb.currentFrame != null
                              ? AspectRatio(
                                  aspectRatio: 16 / 9,
                                  child: Image.memory(
                                    adb.currentFrame!,
                                    fit: BoxFit.contain,
                                    gaplessPlayback: true,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            const SizedBox.shrink(),
                                  ),
                                )
                              : _buildAdbWindowContent(adb))),
                ),

                // Top Bar Overlay
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.88),
                          Colors.black.withValues(alpha: 0.45),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.65, 1.0],
                      ),
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final availableWidth = constraints.maxWidth;
                        final isCompact = availableWidth < 680;
                        final appBrandIcon = isScreenOff
                            ? const Icon(Icons.tv_off_rounded, size: 16, color: Colors.white38)
                            : _buildAppBrandIcon(activeAppPkg, effectiveAppName);

                        // Mode toggle pill (Media vs ADB)
                        final modeTogglePill = _buildModeTogglePill(
                          isAdbMode: isAdbMode,
                          onSelectMode: (mode) => adb.setMode(mode),
                          adb: adb,
                          tvHost: widget.tvHost,
                        );

                        // ADB Port & Variant Badge (Shows :5555 and PADRÃO or MINIMAL)
                        final isMinimal = adb.isMinimalAdb;
                        final variantColor = isMinimal ? Colors.amberAccent : const Color(0xFF60CDFF);
                        final variantBg = (isMinimal ? Colors.amber : const Color(0xFF60CDFF)).withValues(alpha: 0.16);
                        final variantBorder = (isMinimal ? Colors.amber : const Color(0xFF60CDFF)).withValues(alpha: 0.5);

                        final portAndVariantBadge = Tooltip(
                          message: '${adb.adbVariantFullName}\nPorta ADB: ${adb.adbPort}\nCaminho: ${adb.adbPath ?? "detectando..."}\nClique para configurar porta',
                          child: InkWell(
                            onTap: () => showAdbPortDialog(context, widget.tvHost),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              height: 24,
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF141519),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFF2A2C34), width: 1.0),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const Icon(Icons.settings_ethernet_rounded,
                                      size: 13, color: Color(0xFF60CDFF)),
                                  const SizedBox(width: 3),
                                  Text(
                                    ':${adb.adbPort}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      height: 1.1,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1.0),
                                    decoration: BoxDecoration(
                                      color: variantBg,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: variantBorder, width: 0.7),
                                    ),
                                    child: Text(
                                      isMinimal ? 'MINIMAL' : 'PADRÃO',
                                      style: TextStyle(
                                        color: variantColor,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.4,
                                        height: 1.1,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );

                        // Terminal toggle button
                        final terminalButton = _buildBarIconButton(
                          size: 24,
                          iconSize: 15,
                          icon: Icon(
                            Icons.terminal_rounded,
                            size: 15,
                            color: _showAdbTerminal
                                ? const Color(0xFF60CDFF)
                                : Colors.white70,
                          ),
                          tooltip: _showAdbTerminal
                              ? 'Ocultar terminal ADB'
                              : 'Mostrar terminal ADB',
                          onPressed: () => setState(
                              () => _showAdbTerminal = !_showAdbTerminal),
                        );

                        // Refresh frame button (when connected)
                        final refreshButton = _buildBarIconButton(
                          size: 24,
                          iconSize: 15,
                          icon: const Icon(Icons.refresh_rounded,
                              size: 15, color: Colors.white70),
                          tooltip: 'Atualizar imagem',
                          onPressed: () => adb.refreshFrame(),
                        );

                        // AO VIVO / CARREGANDO badge
                        final isAdbLoading = !isScreenOff && isAdbMode && (adb.state != AdbState.connected || adb.isAdbStale);
                        final isLiveActive = (!isScreenOff &&
                            ((isAdbMode && adb.state == AdbState.connected && !adb.isAdbStale) ||
                                (!isAdbMode && info != null && info.isPlaying)));
                        final badgeColor = isScreenOff
                            ? Colors.redAccent
                            : (isAdbLoading
                                ? Colors.amber
                                : (isLiveActive ? const Color(0xFF107C41) : Colors.redAccent));
                        final hasFrame = adb.currentFrame != null;
                        final String badgeText;
                        if (isScreenOff) {
                          badgeText = 'DESLIGADA';
                        } else if (isAdbLoading) {
                          if (hasFrame) {
                            final secs = adb.secondsSinceLastFrame;
                            badgeText = 'CARREGANDO (${secs}s)';
                          } else {
                            badgeText = 'CARREGANDO';
                          }
                        } else {
                          badgeText = 'AO VIVO';
                        }

                        final aoVivoBadge = Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4.5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: badgeColor.withValues(alpha: 0.8),
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
                                  color: badgeColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                badgeText,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        );

                        // Window action buttons (Remote, Pin, Fullscreen)
                        final windowControlIcons = <Widget>[
                          _buildBarIconButton(
                            icon: Icon(
                              Icons.settings_remote_rounded,
                              size: 20,
                              color: _showRemotePanel
                                  ? const Color(0xFF60CDFF)
                                  : Colors.white70,
                            ),
                            tooltip: _showRemotePanel
                                ? 'Fechar controle remoto'
                                : 'Abrir controle remoto',
                            onPressed: _toggleRemotePanel,
                          ),
                          const SizedBox(width: 3),
                          _buildBarIconButton(
                            icon: Icon(
                              _alwaysOnTop
                                  ? Icons.push_pin_rounded
                                  : Icons.push_pin_outlined,
                              size: 20,
                              color: _alwaysOnTop
                                  ? const Color(0xFF60CDFF)
                                  : Colors.white70,
                            ),
                            tooltip: _alwaysOnTop
                                ? 'Desafixar do topo'
                                : 'Fixar sempre no topo',
                            onPressed: _toggleAlwaysOnTop,
                          ),
                          const SizedBox(width: 3),
                          _buildBarIconButton(
                            icon: Icon(
                              _isFullScreen
                                  ? Icons.fullscreen_exit_rounded
                                  : Icons.fullscreen_rounded,
                              size: 20,
                              color: Colors.white70,
                            ),
                            tooltip: _isFullScreen
                                ? 'Sair da tela cheia'
                                : 'Tela cheia',
                            onPressed: _toggleFullScreen,
                          ),
                        ];

                        final sideWidth = (availableWidth - 124) / 2;

                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            // 1. Left Zone: Title & App chip + ADB Tools (if in ADB mode)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                    maxWidth: sideWidth.clamp(80.0, double.infinity)),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(
                                            text: mediaTitle,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: isCompact ? 13.5 : 16.0,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.2,
                                              height: 1.25,
                                            ),
                                          ),
                                          if (mediaChannel != null) ...[
                                            TextSpan(
                                              text: ' - $mediaChannel',
                                              style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: isCompact ? 11.5 : 13.5,
                                                fontWeight: FontWeight.normal,
                                                height: 1.25,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      softWrap: false,
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                    const SizedBox(height: 4),
                                    SizedBox(
                                      height: 24,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            // App branding chip
                                            Container(
                                              height: 24,
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 7, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withValues(alpha: 0.65),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(
                                                    color: Colors.white24, width: 0.8),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment: CrossAxisAlignment.center,
                                                children: [
                                                  if (appBrandIcon != null) ...[
                                                    appBrandIcon,
                                                    const SizedBox(width: 6),
                                                  ],
                                                  ConstrainedBox(
                                                    constraints: BoxConstraints(
                                                        maxWidth: (sideWidth - 50).clamp(40.0, 160.0)),
                                                    child: Text(
                                                      effectiveAppName,
                                                      softWrap: false,
                                                      overflow: TextOverflow.ellipsis,
                                                      maxLines: 1,
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: isCompact ? 11.5 : 12.5,
                                                        fontWeight: FontWeight.w600,
                                                        height: 1.1,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),

                                            // ADB Tools on the Left (adjacent to connection info)
                                            if (isAdbMode) ...[
                                              const SizedBox(width: 6),
                                              portAndVariantBadge,
                                              const SizedBox(width: 5),
                                              terminalButton,
                                              if (adb.state == AdbState.connected) ...[
                                                const SizedBox(width: 5),
                                                refreshButton,
                                              ],
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // 2. Center: Mode toggle pill - ALWAYS in the exact horizontal center!
                            Align(
                              alignment: Alignment.center,
                              child: modeTogglePill,
                            ),

                            // 3. Right Zone: AO VIVO badge + Window control icons (Remote, Pin, Fullscreen)
                            Align(
                              alignment: Alignment.centerRight,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                    maxWidth: sideWidth.clamp(80.0, double.infinity)),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      aoVivoBadge,
                                      const SizedBox(width: 8),
                                      ...windowControlIcons,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),

                // Bottom Bar Overlay
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.9),
                          Colors.black.withValues(alpha: 0.5),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.7, 1.0],
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Video Scrub / Progress Bar (Above action buttons in media mode)
                        if (!isAdbMode && info != null && info.hasMedia) ...[
                          Builder(
                            builder: (context) {
                              final duration = info.duration ?? 0.0;
                              final current = _interpolatedMediaTime() ??
                                  info.currentTime ??
                                  0.0;
                              final frac = (duration > 0)
                                  ? (current / duration).clamp(0.0, 1.0)
                                  : 0.0;
                              final hasDuration = duration > 0;

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Time row above the scrub bar: Left = Current time, Right = Duration
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          _formatDuration(current),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          hasDuration
                                              ? _formatDuration(duration)
                                              : '--:--',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    // Interactive scrub bar with circle thumb
                                    LayoutBuilder(
                                      builder: (context, constraints) {
                                        final barWidth = constraints.maxWidth;
                                        final thumbX = (barWidth * frac - 6)
                                            .clamp(0.0, barWidth - 12);

                                        return GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTapDown: hasDuration
                                              ? (details) {
                                                  final tappedFrac =
                                                      (details.localPosition.dx /
                                                              barWidth)
                                                          .clamp(0.0, 1.0);
                                                  final targetSecs =
                                                      tappedFrac * duration;
                                                  _onSeek(targetSecs);
                                                }
                                              : null,
                                          onHorizontalDragUpdate: hasDuration
                                              ? (details) {
                                                  final tappedFrac =
                                                      (details.localPosition.dx /
                                                              barWidth)
                                                          .clamp(0.0, 1.0);
                                                  final targetSecs =
                                                      tappedFrac * duration;
                                                  _onSeek(targetSecs);
                                                }
                                              : null,
                                          child: SizedBox(
                                            height: 20,
                                            child: Stack(
                                              clipBehavior: Clip.none,
                                              alignment: Alignment.centerLeft,
                                              children: [
                                                // Background track
                                                Center(
                                                  child: Container(
                                                    height: 4,
                                                    width: double.infinity,
                                                    decoration: BoxDecoration(
                                                      color: Colors.white24,
                                                      borderRadius:
                                                          BorderRadius.circular(2),
                                                    ),
                                                  ),
                                                ),
                                                // Progress track
                                                Align(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: FractionallySizedBox(
                                                    widthFactor: frac,
                                                    child: Container(
                                                      height: 4,
                                                      decoration: BoxDecoration(
                                                        color: const Color(
                                                            0xFF60CDFF),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(2),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                // Circle Thumb (strictly centered vertically with track)
                                                Positioned(
                                                  left: thumbX,
                                                  top: 0,
                                                  bottom: 0,
                                                  child: Center(
                                                    child: Container(
                                                      width: 12,
                                                      height: 12,
                                                      decoration: BoxDecoration(
                                                        color: Colors.white,
                                                        shape: BoxShape.circle,
                                                        boxShadow: [
                                                          BoxShadow(
                                                            color: Colors.black
                                                                .withValues(
                                                                    alpha: 0.5),
                                                            blurRadius: 4,
                                                            offset:
                                                                const Offset(
                                                                    0, 1),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],

                        // Action Buttons Row (perfeitamente alinhada e com mesma altura em ambos os modos)
                        LayoutBuilder(
                          builder: (context, bConstraints) {
                            final bw = bConstraints.maxWidth;
                            final isNarrow = bw < 620;
                            final isVeryNarrow = bw < 460;
                            final btnSize = isVeryNarrow ? 28.0 : (isNarrow ? 31.0 : 36.0);
                            final iconSize = isVeryNarrow ? 16.0 : (isNarrow ? 18.0 : 20.0);
                            final dpadIconSize = isVeryNarrow ? 18.0 : (isNarrow ? 20.0 : 22.0);
                            final spacing = isVeryNarrow ? 1.0 : 2.0;

                            final tvChip = Container(
                              height: 32,
                              padding: EdgeInsets.symmetric(
                                  horizontal: isNarrow ? 7 : 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: Colors.white24, width: 0.8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.tv_rounded,
                                      size: 14, color: Color(0xFF60CDFF)),
                                  if (!isVeryNarrow) ...[
                                    const SizedBox(width: 6),
                                    ConstrainedBox(
                                      constraints: BoxConstraints(
                                          maxWidth: isNarrow ? 90 : 160),
                                      child: Text(
                                        widget.tvName,
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );

                            if (!isAdbMode) {
                              return SizedBox(
                                height: 38,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    _buildBarIconButton(
                                      size: 36,
                                      icon: Icon(
                                        isPlaying
                                            ? Icons.pause_circle_filled_rounded
                                            : Icons.play_circle_fill_rounded,
                                        size: 28,
                                        color: const Color(0xFF60CDFF),
                                      ),
                                      tooltip: isPlaying ? 'Pausar' : 'Reproduzir',
                                      onPressed: () => widget.controller
                                          .sendKey(KeyCode.mediaPlayPause),
                                    ),
                                    const SizedBox(width: 8),
                                    tvChip,
                                    const Spacer(),
                                    _buildBarIconButton(
                                      size: 36,
                                      icon: const Icon(
                                        Icons.volume_down_rounded,
                                        size: 20,
                                        color: Colors.white70,
                                      ),
                                      tooltip: 'Volume -',
                                      onPressed: () => widget.controller
                                          .sendKey(KeyCode.volumeDown),
                                    ),
                                    const SizedBox(width: 4),
                                    _buildBarIconButton(
                                      size: 36,
                                      icon: const Icon(
                                        Icons.volume_up_rounded,
                                        size: 20,
                                        color: Colors.white70,
                                      ),
                                      tooltip: 'Volume +',
                                      onPressed: () => widget.controller
                                          .sendKey(KeyCode.volumeUp),
                                    ),
                                  ],
                                ),
                              );
                            }

                            // ADB Mode: Navigation + D-Pad + Volume controls
                            return SizedBox(
                              height: 38,
                              width: double.infinity,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                    tvChip,
                                    const SizedBox(width: 6),
                                    _buildBarIconButton(
                                      size: btnSize,
                                      iconSize: iconSize,
                                      icon: const Icon(Icons.arrow_back_rounded,
                                          color: Colors.white),
                                      tooltip: 'Voltar',
                                      onPressed: () => widget.controller
                                          .sendKey(KeyCode.back),
                                    ),
                                    SizedBox(width: spacing),
                                    _buildBarIconButton(
                                      size: btnSize,
                                      iconSize: iconSize,
                                      icon: const Icon(Icons.home_rounded,
                                          color: Colors.white),
                                      tooltip: 'Home',
                                      onPressed: () => widget.controller
                                          .sendKey(KeyCode.home),
                                    ),
                                    SizedBox(width: spacing),
                                    _buildBarIconButton(
                                      size: btnSize,
                                      iconSize: iconSize,
                                      icon: const Icon(Icons.menu_rounded,
                                          color: Colors.white),
                                      tooltip: 'Menu',
                                      onPressed: () => widget.controller
                                          .sendKey(KeyCode.menu),
                                    ),
                                    SizedBox(width: spacing * 2),
                                    _buildBarIconButton(
                                      size: btnSize,
                                      iconSize: dpadIconSize,
                                      icon: const Icon(
                                          Icons.keyboard_arrow_left_rounded,
                                          color: Colors.white70),
                                      tooltip: 'Esquerda',
                                      onPressed: () => widget.controller
                                          .sendKey(KeyCode.dpadLeft),
                                    ),
                                    SizedBox(width: spacing),
                                    _buildBarIconButton(
                                      size: btnSize,
                                      iconSize: dpadIconSize,
                                      icon: const Icon(
                                          Icons.keyboard_arrow_up_rounded,
                                          color: Colors.white70),
                                      tooltip: 'Cima',
                                      onPressed: () => widget.controller
                                          .sendKey(KeyCode.dpadUp),
                                    ),
                                    SizedBox(width: spacing),
                                    _buildBarIconButton(
                                      size: btnSize,
                                      iconSize: iconSize,
                                      icon: const Icon(
                                          Icons.check_circle_outline_rounded,
                                          color: Color(0xFF60CDFF)),
                                      tooltip: 'OK / Selecionar',
                                      onPressed: () => widget.controller
                                          .sendKey(KeyCode.dpadCenter),
                                    ),
                                    SizedBox(width: spacing),
                                    _buildBarIconButton(
                                      size: btnSize,
                                      iconSize: dpadIconSize,
                                      icon: const Icon(
                                          Icons.keyboard_arrow_down_rounded,
                                          color: Colors.white70),
                                      tooltip: 'Baixo',
                                      onPressed: () => widget.controller
                                          .sendKey(KeyCode.dpadDown),
                                    ),
                                    SizedBox(width: spacing),
                                    _buildBarIconButton(
                                      size: btnSize,
                                      iconSize: dpadIconSize,
                                      icon: const Icon(
                                          Icons.keyboard_arrow_right_rounded,
                                          color: Colors.white70),
                                      tooltip: 'Direita',
                                      onPressed: () => widget.controller
                                          .sendKey(KeyCode.dpadRight),
                                    ),
                                    SizedBox(width: isNarrow ? 8 : 16),
                                    _buildBarIconButton(
                                      size: btnSize,
                                      iconSize: iconSize,
                                      icon: const Icon(
                                        Icons.volume_down_rounded,
                                        color: Colors.white70,
                                      ),
                                      tooltip: 'Volume -',
                                      onPressed: () => widget.controller
                                          .sendKey(KeyCode.volumeDown),
                                    ),
                                    SizedBox(width: spacing),
                                    _buildBarIconButton(
                                      size: btnSize,
                                      iconSize: iconSize,
                                      icon: const Icon(
                                        Icons.volume_up_rounded,
                                        color: Colors.white70,
                                      ),
                                      tooltip: 'Volume +',
                                      onPressed: () => widget.controller
                                          .sendKey(KeyCode.volumeUp),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                // Terminal ADB Overlay (exibido apenas quando ativado no modo ADB na janela)
                if (isAdbMode && _showAdbTerminal)
                  _buildAdbTerminalOverlay(adb),
              ],
                  ),
                ),
                if (_showRemotePanel)
                  _buildRemoteSidePanel(p),
              ],
            );
          },
        );
              },
            ),
          ),
        ),
      );
    },
  );
}

  Widget _buildRemoteSidePanel(Palette p) {
    return Container(
      width: 350,
      decoration: BoxDecoration(
        color: const Color(0xFF141418),
        border: Border(
          left: BorderSide(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 18,
            offset: const Offset(-4, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header do painel lateral
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 1,
                ),
              ),
              color: Colors.black.withValues(alpha: 0.3),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.settings_remote_rounded,
                  size: 18,
                  color: Color(0xFF60CDFF),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Controle Remoto',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: _toggleRemotePanel,
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Conteúdo do controle remoto idêntico ao da tray
          Expanded(
            child: RemoteView(
              controller: widget.controller,
              showScreenMirrorCard: false,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdbWindowContent(AdbService adb) {
    if (adb.state == AdbState.connected && adb.currentFrame != null) {
      return Image.memory(
        adb.currentFrame!,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
      );
    }

    return Container(
      color: Colors.transparent,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (adb.state == AdbState.missingAdb) ...[
              const Icon(Icons.adb_rounded, size: 48, color: Colors.orangeAccent),
              const SizedBox(height: 12),
              Text(
                appTr(
                  pt: 'Ferramenta ADB não encontrada',
                  en: 'ADB tool not found',
                  es: 'Herramienta ADB no encontrada',
                ),
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                appTr(
                  pt: 'Necessária para streaming de tela em tempo real via depuração de rede.',
                  en: 'Required for real-time screen streaming via network debugging.',
                  es: 'Necesaria para la transmisión de pantalla en tiempo real mediante depuración de red.',
                ),
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () => adb.downloadPlatformTools(),
                child: Text(appTr(
                  pt: 'Baixar ADB Oficial do Google',
                  en: 'Download Official Google ADB',
                  es: 'Descargar ADB Oficial de Google',
                )),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.terminal_rounded, size: 16),
                label: const Text('Ver Terminal / Logs do ADB'),
                onPressed: () => setState(() => _showAdbTerminal = true),
              ),
            ] else if (adb.state == AdbState.downloadingAdb) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 14),
              Text(
                'Baixando Platform-Tools (${(adb.downloadProgress * 100).toInt()}%)...',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ] else if (adb.state == AdbState.connecting || adb.state == AdbState.checking) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 14),
              Text(
                'Conectando via ADB a ${widget.tvHost}:${adb.adbPort}...',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 14),
              FilledButton.tonal(
                onPressed: () => adb.reRequestConnection(widget.tvHost),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.restart_alt_rounded, size: 16),
                    SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Reenviar pedido de conexão para a TV',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.terminal_rounded, size: 16),
                label: const Text('Ver Terminal / Logs do ADB'),
                onPressed: () => setState(() => _showAdbTerminal = true),
              ),
            ] else if (adb.state == AdbState.connected && adb.currentFrame == null) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 14),
              Text(
                appTr(
                  pt: 'Carregando tela da TV via ADB...',
                  en: 'Loading TV screen via ADB...',
                  es: 'Cargando pantalla de la TV mediante ADB...',
                ),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ] else if (adb.state == AdbState.unauthorized) ...[
              const Icon(Icons.touch_app_rounded, size: 48, color: Colors.amberAccent),
              const SizedBox(height: 12),
              const Text(
                'Aguardando autorização na TV!',
                style: TextStyle(color: Colors.amberAccent, fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Olhe para a tela da sua TV e marque "Sempre permitir deste computador", depois clique em OK.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              FilledButton.tonal(
                onPressed: () => adb.reRequestConnection(widget.tvHost),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.restart_alt_rounded, size: 16),
                    SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Reenviar pedido de conexão para a TV',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.terminal_rounded, size: 16),
                label: const Text('Ver Terminal / Logs do ADB'),
                onPressed: () => setState(() => _showAdbTerminal = true),
              ),
            ] else if (adb.state == AdbState.error) ...[
              const Icon(Icons.warning_amber_rounded, size: 44, color: Colors.redAccent),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  adb.errorMessage ?? 'Erro na conexão ADB',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (adb.adbPort != 5555) ...[
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF107C41)),
                      onPressed: () => adb.reRequestConnection(widget.tvHost, 5555),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_outline_rounded, size: 16),
                          SizedBox(width: 6),
                          Text('Usar porta padrão 5555'),
                        ],
                      ),
                    ),
                  ],
                  FilledButton.tonal(
                    onPressed: () => adb.reRequestConnection(widget.tvHost),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.restart_alt_rounded, size: 16),
                        SizedBox(width: 6),
                        Text('Tentar novamente'),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF60CDFF),
                      side: const BorderSide(color: Color(0xFF60CDFF)),
                    ),
                    icon: const Icon(Icons.terminal_rounded, size: 16),
                    label: const Text('Ver Terminal / Logs de Erro'),
                    onPressed: () => setState(() => _showAdbTerminal = true),
                  ),
                ],
              ),
            ] else ...[
              const Icon(Icons.adb_rounded, size: 48, color: Color(0xFF60CDFF)),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () => adb.reRequestConnection(widget.tvHost),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.restart_alt_rounded, size: 16),
                    SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Conectar e solicitar pedido na TV',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.terminal_rounded, size: 16),
                label: const Text('Ver Terminal / Logs do ADB'),
                onPressed: () => setState(() => _showAdbTerminal = true),
              ),
              const SizedBox(height: 14),
              Tooltip(
                message: 'Clique para alternar entre ADB Padrão e Minimal ADB and Fastboot ou alterar porta',
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => showAdbPortDialog(context, widget.tvHost),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: (adb.isMinimalAdb ? Colors.amber : const Color(0xFF60CDFF)).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: (adb.isMinimalAdb ? Colors.amber : const Color(0xFF60CDFF)).withValues(alpha: 0.4),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          adb.isMinimalAdb ? Icons.flash_on_rounded : Icons.verified_rounded,
                          size: 14,
                          color: adb.isMinimalAdb ? Colors.amberAccent : const Color(0xFF60CDFF),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Usando: ${adb.adbVariantFullName}',
                          style: TextStyle(
                            color: adb.isMinimalAdb ? Colors.amber[100] : const Color(0xFFD4EFFF),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.swap_horiz_rounded,
                          size: 14,
                          color: adb.isMinimalAdb ? Colors.amberAccent : const Color(0xFF60CDFF),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAdbTerminalOverlay(AdbService adb) {
    final (statusColor, statusText) = switch (adb.state) {
      AdbState.connected => (const Color(0xFF107C41), 'Conectado'),
      AdbState.unauthorized => (Colors.amber, 'Aguardando autorização'),
      AdbState.connecting => (const Color(0xFF60CDFF), 'Conectando...'),
      AdbState.downloadingAdb => (const Color(0xFF60CDFF), 'Baixando ADB...'),
      AdbState.missingAdb => (Colors.orangeAccent, 'ADB não encontrado'),
      AdbState.error => (Colors.redAccent, 'Erro na conexão'),
      AdbState.idle || AdbState.checking => (Colors.white54, 'Ocioso'),
    };

    return Positioned(
      top: 60,
      bottom: 60,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xF50F1117),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF282C38), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.65),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: const BoxDecoration(
                    color: Color(0xFF161821),
                    border: Border(
                      bottom: BorderSide(color: Color(0xFF242733), width: 1),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.terminal_rounded, size: 18, color: Color(0xFF60CDFF)),
                      const SizedBox(width: 8),
                      Text(
                        'Terminal ADB - ${widget.tvHost}:${adb.adbPort}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (adb.isMinimalAdb ? Colors.amber : const Color(0xFF60CDFF)).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: (adb.isMinimalAdb ? Colors.amber : const Color(0xFF60CDFF)).withValues(alpha: 0.5),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          adb.adbVariantShortName,
                          style: TextStyle(
                            color: adb.isMinimalAdb ? Colors.amberAccent : const Color(0xFF60CDFF),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Status badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: statusColor.withValues(alpha: 0.4), width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              statusText,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),

                      // Reconnect / Test connection button
                      Tooltip(
                        message: 'Reconectar / Testar conexão ADB',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => adb.reRequestConnection(widget.tvHost),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF222634),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.white12, width: 0.8),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.restart_alt_rounded, size: 14, color: Colors.white70),
                                SizedBox(width: 4),
                                Text(
                                  'Reconectar',
                                  style: TextStyle(color: Colors.white, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Copy logs button
                      Tooltip(
                        message: 'Copiar todo o histórico do terminal',
                        child: IconButton(
                          iconSize: 17,
                          padding: const EdgeInsets.all(6),
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.copy_rounded, color: Colors.white70),
                          onPressed: () {
                            if (adb.logs.isEmpty) return;
                            final text = adb.logs.map((l) {
                              final status = l.isError ? '[FALHA exitCode: ${l.exitCode}]' : '[SUCESSO]';
                              return '[${l.timeFormatted}] $status > ${l.command}\n${l.output}';
                            }).join('\n\n');
                            Clipboard.setData(ClipboardData(text: text));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Logs copiados para a área de transferência!'),
                                duration: Duration(seconds: 2),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 4),

                      // Clear logs button
                      Tooltip(
                        message: 'Limpar tela do terminal',
                        child: IconButton(
                          iconSize: 17,
                          padding: const EdgeInsets.all(6),
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.white70),
                          onPressed: () => adb.clearLogs(),
                        ),
                      ),
                      const SizedBox(width: 4),

                      // Close terminal button
                      Tooltip(
                        message: 'Fechar terminal',
                        child: IconButton(
                          iconSize: 18,
                          padding: const EdgeInsets.all(6),
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.close_rounded, color: Colors.white),
                          onPressed: () => setState(() => _showAdbTerminal = false),
                        ),
                      ),
                    ],
                  ),
                ),

                // Terminal Log Display Body
                Expanded(
                  child: Container(
                    color: const Color(0xFF090A0E),
                    padding: const EdgeInsets.all(12),
                    child: adb.logs.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.terminal_rounded, size: 36, color: Colors.white24),
                                const SizedBox(height: 10),
                                const Text(
                                  'Terminal ADB pronto.',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                    fontFamily: 'Consolas',
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Os acertos, erros e saídas dos comandos ADB executados aparecerão aqui em tempo real.',
                                  style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 11,
                                    fontFamily: 'Consolas',
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            controller: _terminalScrollController,
                            itemCount: adb.logs.length,
                            separatorBuilder: (_, index) => const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final log = adb.logs[i];
                              final isSuccess = !log.isError;
                              return Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: log.isError
                                      ? Colors.red.withValues(alpha: 0.08)
                                      : Colors.white.withValues(alpha: 0.03),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: log.isError
                                        ? Colors.redAccent.withValues(alpha: 0.3)
                                        : Colors.white.withValues(alpha: 0.06),
                                    width: 0.8,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Command header line
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Text(
                                          '[${log.timeFormatted}] ',
                                          style: const TextStyle(
                                            color: Colors.white38,
                                            fontSize: 11,
                                            fontFamily: 'Consolas',
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: (isSuccess ? const Color(0xFF107C41) : Colors.redAccent)
                                                .withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            isSuccess ? 'SUCESSO' : 'ERRO (${log.exitCode})',
                                            style: TextStyle(
                                              color: isSuccess ? const Color(0xFF68E08F) : Colors.redAccent,
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.bold,
                                              fontFamily: 'Consolas',
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: SelectableText(
                                            '> ${log.command}',
                                            style: const TextStyle(
                                              color: Color(0xFF60CDFF),
                                              fontSize: 12,
                                              fontFamily: 'Consolas',
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 5),
                                    // Command output line
                                    SelectableText(
                                      log.output,
                                      style: TextStyle(
                                        color: log.isError ? const Color(0xFFFF9494) : const Color(0xFFD4D7E2),
                                        fontSize: 11.5,
                                        fontFamily: 'Consolas',
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ),

                // Quick Command Action Chips
                Container(
                  color: const Color(0xFF12141C),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        const Text(
                          'Comandos rápidos: ',
                          style: TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'Consolas'),
                        ),
                        _buildQuickCommandChip(adb, 'devices', 'adb devices'),
                        _buildQuickCommandChip(adb, 'disconnect', 'adb disconnect'),
                        _buildQuickCommandChip(adb, 'shell dumpsys power', 'adb shell dumpsys power'),
                        _buildQuickCommandChip(adb, 'shell pm list packages -3', 'adb shell apps de terceiros'),
                        _buildQuickCommandChip(adb, 'shell getprop ro.build.version.release', 'adb versão Android'),
                      ],
                    ),
                  ),
                ),

                // Bottom Command Input Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: const BoxDecoration(
                    color: Color(0xFF161821),
                    border: Border(
                      top: BorderSide(color: Color(0xFF242733), width: 1),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        'adb > ',
                        style: TextStyle(
                          color: Color(0xFF60CDFF),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          fontFamily: 'Consolas',
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: TextField(
                          controller: _adbCmdController,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontFamily: 'Consolas',
                          ),
                          cursorColor: const Color(0xFF60CDFF),
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'Digite um comando ADB (ex: shell input keyevent 66, devices, shell ...)',
                            hintStyle: TextStyle(
                              color: Colors.white30,
                              fontSize: 11.5,
                              fontFamily: 'Consolas',
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 4),
                          ),
                          onSubmitted: (val) => _executeAdbCommand(adb, val),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_isExecutingAdbCmd)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF60CDFF)),
                        )
                      else
                        IconButton(
                          iconSize: 18,
                          padding: const EdgeInsets.all(6),
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.send_rounded, color: Color(0xFF60CDFF)),
                          tooltip: 'Executar comando (Enter)',
                          onPressed: () => _executeAdbCommand(adb, _adbCmdController.text),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickCommandChip(AdbService adb, String command, String tooltip) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => _executeAdbCommand(adb, command),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1F2B),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white12, width: 0.8),
            ),
            child: Text(
              command,
              style: const TextStyle(
                color: Color(0xFF60CDFF),
                fontSize: 10.5,
                fontFamily: 'Consolas',
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFallback({
    required String tvName,
    String? appName,
    String? appPackage,
  }) {
    final isScreenOff = widget.controller.isScreenOff;
    final hasAppInfo = !isScreenOff &&
        appName != null &&
        appName.isNotEmpty &&
        appName != 'Default Media Receiver' &&
        appName != 'Tela desligada';

    final displayName = isScreenOff
        ? 'Tela desligada'
        : (hasAppInfo ? appName : tvName);

    return Container(
      color: Colors.transparent,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isScreenOff)
              const Icon(Icons.tv_off_rounded, size: 54, color: Colors.white38)
            else if (hasAppInfo)
              _buildLargeAppBrandIcon(appPackage, displayName)
            else
              const Icon(Icons.tv_rounded, size: 54, color: Color(0xFF60CDFF)),
            const SizedBox(height: 14),
            Text(
              displayName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16.5,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              isScreenOff
                  ? tvName
                  : 'Transmissão da tela ativa',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLargeAppBrandIcon(String? pkg, String name) {
    final str = '${pkg ?? ''} $name'.toLowerCase();
    if (str.contains('backdrop') ||
        str.contains('protetor de tela') ||
        str.contains('screen saver') ||
        str.contains('salvapantallas')) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4285F4), Color(0xFF34A853)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Center(
          child: Icon(
            Icons.wallpaper_rounded,
            color: Colors.white,
            size: 28,
          ),
        ),
      );
    } else if (str.contains('mediatek.wwtv') ||
        str.contains('wwtv') ||
        str.contains('tv / hdmi / av')) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF1E3A8A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF60A5FA), width: 1.8),
        ),
        child: const Center(
          child: Icon(
            Icons.settings_input_hdmi_rounded,
            color: Color(0xFF60A5FA),
            size: 28,
          ),
        ),
      );
    } else if (str.contains('youtube') ||
        str.contains('smarttube') ||
        str.contains('tizentube')) {
      return Container(
        width: 60,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFFFF0000),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF0000).withValues(alpha: 0.45),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Center(
          child: Icon(
            Icons.play_arrow_rounded,
            color: Colors.white,
            size: 30,
          ),
        ),
      );
    } else if (str.contains('projengmenu') || str.contains('projectivy')) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF38BDF8), width: 2),
        ),
        child: const Center(
          child: Icon(
            Icons.grid_view_rounded,
            color: Color(0xFF38BDF8),
            size: 28,
          ),
        ),
      );
    } else if (str.contains('youcine')) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF7C3AED), Color(0xFFC026D3)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Center(
          child: Icon(
            Icons.movie_filter_rounded,
            color: Colors.white,
            size: 28,
          ),
        ),
      );
    } else if (str.contains('isic') || str.contains('intelbras')) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF00A34D),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Center(
          child: Icon(
            Icons.videocam_rounded,
            color: Colors.white,
            size: 28,
          ),
        ),
      );
    } else if (str.contains('netflix')) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE50914), width: 2.5),
        ),
        child: const Center(
          child: Text(
            'N',
            style: TextStyle(
              color: Color(0xFFE50914),
              fontSize: 30,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
        ),
      );
    } else if (str.contains('spotify') || str.contains('music')) {
      return Container(
        width: 48,
        height: 48,
        decoration: const BoxDecoration(
          color: Color(0xFF1ED760),
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: Icon(
            Icons.music_note_rounded,
            color: Colors.black,
            size: 30,
          ),
        ),
      );
    } else if (str.contains('prime') || str.contains('amazon')) {
      return Container(
        width: 56,
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFF00A8E1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Center(
          child: Icon(
            Icons.play_arrow_rounded,
            color: Colors.white,
            size: 30,
          ),
        ),
      );
    } else if (str.contains('disney')) {
      return Container(
        width: 56,
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFF113CCF),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Center(
          child: Icon(
            Icons.star_rounded,
            color: Colors.white,
            size: 30,
          ),
        ),
      );
    } else if (str.contains('globo')) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFFFF4D00),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Center(
          child: Icon(
            Icons.play_circle_filled_rounded,
            color: Colors.white,
            size: 30,
          ),
        ),
      );
    } else if (str.contains('max') || str.contains('hbo')) {
      return Container(
        width: 56,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFF002BE7),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Center(
          child: Text(
            'MAX',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
        ),
      );
    } else if (str.contains('twitch')) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF9146FF),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Center(
          child: Icon(
            Icons.videogame_asset_rounded,
            color: Colors.white,
            size: 28,
          ),
        ),
      );
    } else if (str.contains('kodi')) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF17B2E7),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Center(
          child: Icon(
            Icons.grid_view_rounded,
            color: Colors.white,
            size: 28,
          ),
        ),
      );
    } else if (str.contains('adb') || str.contains('depuração')) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF107C41),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Center(
          child: Icon(
            Icons.android_rounded,
            color: Colors.white,
            size: 28,
          ),
        ),
      );
    } else if (str.contains('tela inicial') ||
        str.contains('launcher') ||
        str.contains('home')) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF64748B), width: 1.5),
        ),
        child: const Center(
          child: Icon(
            Icons.home_rounded,
            color: Colors.white,
            size: 28,
          ),
        ),
      );
    }
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFF20222A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24, width: 1.2),
      ),
      child: Center(
        child: (name.isNotEmpty && name.length <= 4)
            ? Text(
                name.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              )
            : const Icon(
                Icons.android_rounded,
                color: Color(0xFF60CDFF),
                size: 28,
              ),
      ),
    );
  }
}

/// Helper to open the mirror in a separate detached window or in-app dialog,
/// strictly enforcing a maximum limit of 2 simultaneously opened mirror windows.
Future<void> openScreenMirrorPopout(
  BuildContext context,
  TvController controller,
) async {
  final tv = controller.selected;
  if (tv == null) return;

  // Verifica se as janelas destacadas foram fechadas antes de impedir a abertura da terceira janela
  final canOpen = await MirrorTracker.canOpenNew();
  if (!canOpen) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFFFA000), size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Limite atingido: já existem 2 telas destacadas abertas.',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1E1E24),
          duration: const Duration(seconds: 3),
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0x40FFFFFF), width: 1),
          ),
        ),
      );
    }
    return;
  }

  try {
    // Inicia como um processo nativo de janela separada do Windows
    final exe = Platform.resolvedExecutable;
    final modeArg =
        AdbService.instance.mode == MirrorMode.adbScreen ? 'adb' : 'cast';
    final portArg = AdbService.instance.adbPort.toString();
    final parentPort = await MirrorTracker.initParentServer();
    final parentPortArg = (parentPort ?? 0).toString();
    final parentPidArg = pid.toString();
    final proc = await Process.start(
      exe,
      ['--mirror', tv.host, tv.name, modeArg, portArg, parentPortArg, parentPidArg],
      mode: ProcessStartMode.detached,
    );
    MirrorTracker.trackPid(proc.pid);
  } catch (e) {
    debugPrint('Erro ao iniciar janela de espelhamento: $e');
  }
}
