import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'adb_service.dart';
import 'app_settings.dart';
import 'cast_client.dart';
import 'client_identity.dart';
import 'discovery.dart';
import 'keycodes.dart';
import 'pairing_client.dart';
import 'remote_client.dart';
import 'tv_store.dart';

enum TvStatus { noTv, connecting, connected, offline, needsPairing }

/// Combined now-playing media and active app information.
class NowPlayingInfo {
  final String? appName;
  final String? appPackage;
  final String? title;
  final String? artist;
  final String? imageUrl;
  final bool isPlaying;
  final double? duration;
  final double? currentTime;

  const NowPlayingInfo({
    this.appName,
    this.appPackage,
    this.title,
    this.artist,
    this.imageUrl,
    this.isPlaying = false,
    this.duration,
    this.currentTime,
  });

  bool get hasMedia =>
      (title != null && title!.isNotEmpty) ||
      (imageUrl != null && imageUrl!.isNotEmpty);

  bool get hasApp =>
      (appName != null &&
          appName!.isNotEmpty &&
          appName != 'Default Media Receiver' &&
          appName != 'Tela Inicial') ||
      (appPackage != null &&
          appPackage!.isNotEmpty &&
          friendlyPackageName(appPackage) != 'Tela Inicial');

  bool get isVisible => hasMedia || hasApp;

  String get displayTitle {
    if (AppSettings.instance.showRawPackageName) {
      if (appPackage != null && appPackage!.isNotEmpty) return appPackage!;
      if (appName != null && appName!.isNotEmpty) return appName!;
      return 'Android TV';
    }
    if (title != null && title!.isNotEmpty) return title!;
    if (appName != null &&
        appName!.isNotEmpty &&
        appName != 'Default Media Receiver' &&
        appName != 'Tela Inicial') {
      final aLow = appName!.toLowerCase();
      if (aLow.contains('backdrop') || aLow == 'screen saver' || aLow == 'ambient mode') {
        return getScreenSaverTitle();
      }
      if (aLow.contains('projengmenu')) return 'Projectivy Launcher';
      if (aLow.contains('sendfilestotv') || aLow.contains('send files to tv')) return 'Send Files to TV';
      if (aLow.contains('bitchord')) return 'BitChord';
      if (aLow.contains('youcine')) return 'YouCine';
      if (aLow.contains('isiclite') || aLow.contains('intelbras')) return 'ISIC Lite';
      if (aLow.contains('mediatek.wwtv') || aLow.contains('wwtv')) return 'TV / HDMI / AV';
      return appName!;
    }
    final friendly = friendlyPackageName(appPackage);
    if (friendly != null && friendly.isNotEmpty) return friendly;
    if (appPackage != null && appPackage!.isNotEmpty) return appPackage!;
    return 'Android TV';
  }

  String? get displaySubtitle {
    if (AppSettings.instance.showRawPackageName) {
      return artist ?? appName;
    }
    if (artist != null && artist!.isNotEmpty) return artist;
    if (hasMedia &&
        appName != null &&
        appName != 'Default Media Receiver') {
      final aLow = appName!.toLowerCase();
      if (aLow.contains('backdrop') || aLow == 'screen saver' || aLow == 'ambient mode') {
        return getScreenSaverTitle();
      }
      if (aLow.contains('projengmenu')) return 'Projectivy Launcher';
      if (aLow.contains('sendfilestotv') || aLow.contains('send files to tv')) return 'Send Files to TV';
      if (aLow.contains('bitchord')) return 'BitChord';
      if (aLow.contains('youcine')) return 'YouCine';
      if (aLow.contains('isiclite') || aLow.contains('intelbras')) return 'ISIC Lite';
      if (aLow.contains('mediatek.wwtv') || aLow.contains('wwtv')) return 'TV / HDMI / AV';
      return appName;
    }
    return null;
  }

  static String? friendlyPackageName(String? pkg) {
    if (pkg == null || pkg.isEmpty) return null;
    if (AppSettings.instance.showRawPackageName) return pkg;
    final p = pkg.toLowerCase();
    if (p.contains('backdrop') || p.contains('screensaver') || p.contains('ambientmode')) {
      return getScreenSaverTitle();
    }
    if (p.contains('projengmenu') || p.contains('projectivy')) return 'Projectivy Launcher';
    if (p.contains('sendfilestotv') || p.contains('sendfiles') || p.contains('send_files_to_tv')) return 'Send Files to TV';
    if (p.contains('bitchord')) return 'BitChord';
    if (p.contains('youcine')) return 'YouCine';
    if (p.contains('isiclite') || p.contains('intelbras')) return 'ISIC Lite';
    if (p.contains('mediatek.wwtv') || p.contains('wwtv')) return 'TV / HDMI / AV';
    if (p.contains('tvlauncher') ||
        p.contains('launcherx') ||
        p.contains('nexuslauncher') ||
        p.contains('katniss')) {
      return 'Tela Inicial';
    }
    if (p.contains('vending')) return 'Google Play Store';
    if (p.contains('wbd') || p.contains('max') || p.contains('hbo')) return 'Max';
    if (p.contains('smarttube') || p.contains('teamsmart') || p.contains('liskovsoft')) return 'SmartTube';
    if (p.contains('tizentube')) return 'TizenTube';
    if (p.contains('youtube')) return 'YouTube';
    if (p.contains('netflix')) return 'Netflix';
    if (p.contains('amazonvideo') || p.contains('primevideo') || p.contains('amazon.avod')) return 'Prime Video';
    if (p.contains('spotify')) return 'Spotify';
    if (p.contains('disney')) return 'Disney+';
    if (p.contains('globo')) return 'Globoplay';
    if (p.contains('kodi')) return 'Kodi';
    if (p.contains('twitch')) return 'Twitch';
    if (p.contains('videolan.vlc') || p == 'org.videolan.vlc') return 'VLC';
    if (p.contains('stremio')) return 'Stremio';
    if (p.contains('pluto')) return 'Pluto TV';
    if (p.contains('crunchyroll')) return 'Crunchyroll';
    if (p.contains('plex')) return 'Plex';
    if (p.contains('apple') && (p.contains('tv') || p.contains('atv'))) return 'Apple TV';
    if (p.contains('deezer')) return 'Deezer';
    if (p.contains('tidal')) return 'Tidal';
    if (p.contains('paramount')) return 'Paramount+';
    if (p.contains('starplus')) return 'Star+';
    if (p.contains('steamlink')) return 'Steam Link';
    if (p.contains('tv.settings') || p.contains('settings')) return 'Configurações';
    if (p.contains('google.android.videos')) return 'Google TV';

    // Quando não tiver nome normatizado pra mostrar, mostre o nome real/formatado em vez de esconder!
    final parts = pkg.split('.');
    if (parts.isNotEmpty) {
      var last = parts.last;
      if ((last == 'stream' || last == 'tv' || last == 'app' || last == 'android') && parts.length > 2) {
        last = parts[parts.length - 2];
      }
      if (last.length > 2) {
        return last[0].toUpperCase() + last.substring(1);
      }
    }
    return pkg;
  }
}

/// App-wide state: TVs, connection lifecycle and commands.
///
/// Platform-agnostic so the same controller drives the Windows tray flyout
/// today and the Android app later.
class TvController extends ChangeNotifier {
  static void Function(int keyCode, KeyDirection direction)? relayKeyHandler;
  static void Function(String text)? relayTextHandler;
  static void Function(String link)? relayLaunchAppHandler;
  static void Function(double seconds)? relaySeekMediaHandler;

  final TvStore _store = TvStore();
  ClientIdentity? _identity;

  TvController() {
    AdbService.instance.addListener(_onAdbChanged);
  }

  void _safeNotifyListeners() {
    if (_disposed) return;
    if (WidgetsBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  void _onAdbChanged() {
    if (!_disposed) {
      _recomputeNowPlaying();
    }
  }

  List<TvDevice> _tvs = [];
  String? _selectedId;
  TvStatus _status = TvStatus.noTv;
  RemoteClient? _remote;
  CastClient? _cast;
  StreamSubscription<Object?>? _closedSub;
  StreamSubscription<bool>? _powerSub;
  StreamSubscription<VolumeInfo>? _volumeSub;
  StreamSubscription<AppInfo>? _appSub;
  StreamSubscription<CastMediaStatus?>? _castMediaSub;
  StreamSubscription<ImeStatus>? _imeSub;
  StreamSubscription<int>? _voiceSessionSub;
  StreamSubscription<int>? _voiceEndSub;
  AudioRecorder? _audioRecorder;
  StreamSubscription<List<int>>? _audioStreamSub;
  int? _activeVoiceSessionId;
  bool _isVoiceRecording = false;
  Timer? _voiceTimeoutTimer;
  Timer? _reconnectTimer;
  int _attempt = 0;
  bool? _powerOn;
  VolumeInfo? _volume;
  AppInfo? _currentApp;
  NowPlayingInfo? _nowPlaying;
  ImeStatus? _imeStatus;
  bool _disposed = false;

  bool get isVoiceRecording => _isVoiceRecording;

  final StreamController<String> _externalKeystrokeCtrl =
      StreamController<String>.broadcast();
  Stream<String> get onExternalKeystroke => _externalKeystrokeCtrl.stream;

  void reportExternalCharacter(String char) {
    if (!_externalKeystrokeCtrl.isClosed) {
      _externalKeystrokeCtrl.add(char);
    }
  }

  final StreamController<void> _externalBackspaceCtrl =
      StreamController<void>.broadcast();
  Stream<void> get onExternalBackspace => _externalBackspaceCtrl.stream;

  void reportExternalBackspace() {
    if (!_externalBackspaceCtrl.isClosed) {
      _externalBackspaceCtrl.add(null);
    }
  }

  PairingClient? _pairing;

  List<TvDevice> _savedPairings = [];
  List<TvDevice> get savedPairings => List.unmodifiable(_savedPairings);

  List<TvDevice> get tvs => List.unmodifiable(_tvs);
  TvDevice? get selected =>
      _tvs.where((t) => t.id == _selectedId).firstOrNull ?? _tvs.firstOrNull;
  TvStatus get status => _status;
  bool? get powerOn => _powerOn;
  VolumeInfo? get volume => _volume;
  NowPlayingInfo? get nowPlaying => _nowPlaying;
  ImeStatus? get imeStatus => _imeStatus;
  bool get hasActiveIme => _imeStatus?.active == true;

  void clearIme() {
    _remote?.clearIme();
    _imeStatus = const ImeStatus(active: false);
    notifyListeners();
  }
  bool get isScreenOff {
    // 1. Se a tela estiver explicitamente acordada pelo ADB
    if (AdbService.instance.isScreenOn == true) return false;

    // 2. Mídia ativa tocando (Cast / player)
    if (_nowPlaying?.hasMedia == true) return false;

    // 3. Standby explícito reportado pelo protocolo da TV
    if (_powerOn == false) return true;

    // 4. Estado de tela reportado pelo ADB (dumpsys power mWakefulness: Asleep/Dozing)
    if (AdbService.instance.isScreenOn == false) return true;

    // 5. Power explicitamente reportado como ligado
    if (_powerOn == true) return false;

    // 6. Nível de volume disponível indica TV com áudio ativo
    if (_volume != null) return false;

    // 7. Se a TV está conectada ao RemoteClient (respondendo a comandos)
    if (_status == TvStatus.connected && _remote?.isConnected == true) {
      return false;
    }

    // 8. Caso não haja conexão ativa nem dados, considera tela desligada
    return true;
  }
  bool get identityReady => _identity != null;

  Future<void> init() async {
    final (list, sel) = await _store.load();
    _tvs = list;
    _selectedId = sel;
    _savedPairings = await _store.loadSavedPairings();
    bool savedChanged = false;
    for (final t in _tvs) {
      if (!_savedPairings.any((p) => p.id == t.id || p.host == t.host)) {
        _savedPairings.add(t);
        savedChanged = true;
      }
    }
    if (savedChanged) {
      await _store.saveSavedPairings(_savedPairings);
    }
    _identity = await ClientIdentity.loadOrCreate();
    _autoEnrichTvNames();
    if (selected != null) {
      unawaited(connect());
    } else {
      _setStatus(TvStatus.noTv);
    }
  }

  void _autoEnrichTvNames() {
    for (final tv in _tvs) {
      TvDiscovery.resolveTvMetadata(tv.host).then((meta) {
        bool changed = false;
        String newName = tv.name;
        String? newManufacturer = tv.manufacturer ?? meta.manufacturer;
        String? newModel = tv.model ?? meta.model;

        if ((tv.name == tv.host || tv.name == 'Android TV') &&
            meta.name.isNotEmpty &&
            meta.name != tv.name) {
          newName = meta.name;
          changed = true;
        }
        if (newManufacturer != tv.manufacturer || newModel != tv.model) {
          changed = true;
        }

        if (changed) {
          updateTv(
            tv.id,
            name: newName,
            manufacturer: newManufacturer,
            model: newModel,
          );
        }
      }).catchError((_) {});
    }
  }

  void _setStatus(TvStatus s) {
    _status = s;
    _safeNotifyListeners();
  }

  // ---------------------------------------------------------------- connect

  Future<void> connect() async {
    final tv = selected;
    final id = _identity;
    if (tv == null || id == null) return;
    _reconnectTimer?.cancel();
    await _teardown();
    _setStatus(TvStatus.connecting);

    final client = RemoteClient(
      host: tv.host,
      context: id.toSecurityContext(),
      deviceModel: Platform.localHostname,
    );
    _remote = client;
    try {
      await client.connect();
      if (_remote != client) return; // superseded
      _attempt = 0;
      _powerSub = client.powerState.listen((on) {
        _powerOn = on;
        _safeNotifyListeners();
      });
      _volumeSub = client.volume.listen((v) {
        _volume = v;
        _safeNotifyListeners();
      });
      _appSub = client.currentApp.listen((app) {
        _currentApp = app;
        _recomputeNowPlaying();
      });
      _imeSub = client.imeStatus.listen((status) {
        _imeStatus = status;
        _safeNotifyListeners();
      });
      _voiceSessionSub = client.voiceSession.listen((sessionId) {
        _onTvVoiceSessionStarted(sessionId);
      });
      _voiceEndSub = client.voiceEnd.listen((sessionId) {
        stopVoiceSearch();
      });
      _closedSub = client.closed.listen((_) {
        if (_remote == client) _scheduleReconnect();
      });

      // Start Google Cast client (port 8009) in parallel for Now Playing metadata
      final cast = CastClient(host: tv.host);
      _cast = cast;
      _castMediaSub = cast.mediaStatus.listen((status) {
        _recomputeNowPlaying(castStatus: status);
      });
      unawaited(cast.connect());

      // Ensure ADB is connected in background for continuous app and screen detection
      unawaited(AdbService.instance.ensureConnected(tv.host));

      _setStatus(TvStatus.connected);
    } on TlsException {
      if (_remote == client) _setStatus(TvStatus.needsPairing);
    } on RemoteRejectedException {
      if (_remote == client) _setStatus(TvStatus.needsPairing);
    } catch (_) {
      if (_remote == client) _scheduleReconnect();
    }
  }

  void _recomputeNowPlaying({CastMediaStatus? castStatus}) {
    // Se a TV estiver com tela desligada, limpa imediatamente _nowPlaying
    if (isScreenOff) {
      if (_nowPlaying != null) {
        _nowPlaying = null;
        _safeNotifyListeners();
      }
      return;
    }

    final cs = castStatus ?? _cast?.currentStatus;
    final app = _currentApp;
    final adbAppName = AdbService.instance.currentAppName;
    final adbAppPkg = AdbService.instance.currentAppPackage;

    final resolvedPackage = adbAppPkg ?? app?.package;
    final friendlyFromPkg = NowPlayingInfo.friendlyPackageName(resolvedPackage);
    final isCastPlaying = (cs?.isPlaying == true || cs?.hasMedia == true) && cs?.appName != null;

    final resolvedAppName = isCastPlaying
        ? cs!.appName
        : (adbAppName != null && adbAppName != 'Tela Inicial'
            ? adbAppName
            : (friendlyFromPkg ?? app?.label ?? cs?.appName));

    if (cs == null && app == null && resolvedAppName == null && resolvedPackage == null) {
      if (_nowPlaying != null) {
        _nowPlaying = null;
        _safeNotifyListeners();
      }
      return;
    }

    final newInfo = NowPlayingInfo(
      appName: resolvedAppName,
      appPackage: resolvedPackage,
      title: cs?.title,
      artist: cs?.artist,
      imageUrl: cs?.imageUrl,
      isPlaying: cs?.isPlaying ?? false,
      duration: cs?.duration,
      currentTime: cs?.currentTime,
    );

    if (newInfo.isVisible) {
      _nowPlaying = newInfo;
      _safeNotifyListeners();
    } else if (_nowPlaying != null) {
      _nowPlaying = null;
      _safeNotifyListeners();
    }
  }

  void _scheduleReconnect() {
    _setStatus(TvStatus.offline);
    _reconnectTimer?.cancel();
    _powerOn = null; // Do NOT set to false: false means explicit power-off reported by TV!
    _volume = null;
    _currentApp = null;
    _nowPlaying = null;
    if (!_disposed) notifyListeners();
    final secs = min(30, 2 << min(_attempt, 4));
    _attempt++;
    _reconnectTimer = Timer(Duration(seconds: secs), connect);
  }

  Future<void> _teardown() async {
    await stopVoiceSearch();
    await _closedSub?.cancel();
    await _powerSub?.cancel();
    await _volumeSub?.cancel();
    await _appSub?.cancel();
    await _castMediaSub?.cancel();
    await _imeSub?.cancel();
    await _voiceSessionSub?.cancel();
    await _voiceEndSub?.cancel();
    _closedSub = _powerSub = _volumeSub = _appSub = _castMediaSub = _imeSub =
        _voiceSessionSub = _voiceEndSub = null;
    _imeStatus = null;
    final c = _cast;
    _cast = null;
    await c?.close();
    final r = _remote;
    _remote = null;
    await r?.close();
    _currentApp = null;
    _nowPlaying = null;
    if (!_disposed) notifyListeners();
  }

  BytesBuilder? _voiceAudioBuffer;

  /// Initiates microphone capture on the local device and streams audio to Android TV Remote v2.
  Future<void> startVoiceSearch() async {
    final r = _remote;
    if (r == null || !r.isConnected) {
      ensureConnected();
      return;
    }

    if (_isVoiceRecording) return;

    // 1. Request microphone permission
    try {
      final micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        return;
      }
    } catch (_) {}

    _audioRecorder ??= AudioRecorder();
    final hasPerm = await _audioRecorder!.hasPermission();
    if (!hasPerm) return;

    _isVoiceRecording = true;
    _activeVoiceSessionId = null;
    _voiceAudioBuffer = BytesBuilder(copy: false);
    _safeNotifyListeners();

    // 2. Send KEYCODE_SEARCH (84) to trigger voice search on TV
    r.sendKey(KeyCode.search);

    // 3. Start audio stream with standard Google TV Remote v2 format (PCM 16-bit, 8000 Hz, mono)
    try {
      final recordStream = await _audioRecorder!.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 8000,
          numChannels: 1,
        ),
      );

      const int minVoiceChunk = 8192;
      const int maxVoiceChunk = 16384;

      _audioStreamSub?.cancel();
      _audioStreamSub = recordStream.listen((chunk) {
        if (!_isVoiceRecording) return;
        final buffer = _voiceAudioBuffer;
        if (buffer == null) return;
        buffer.add(chunk);

        final sessionId = _activeVoiceSessionId;
        if (sessionId != null && buffer.length >= minVoiceChunk) {
          final allBytes = buffer.takeBytes();
          int offset = 0;
          while (allBytes.length - offset >= minVoiceChunk) {
            final end = (offset + maxVoiceChunk <= allBytes.length)
                ? offset + maxVoiceChunk
                : allBytes.length;
            final slice = Uint8List.sublistView(allBytes, offset, end);
            r.sendVoicePayload(sessionId, slice);
            offset = end;
          }
          if (offset < allBytes.length) {
            buffer.add(Uint8List.sublistView(allBytes, offset));
          }
        }
      });
    } catch (e) {
      stopVoiceSearch();
      return;
    }

    // Safety timeout: automatically finalize after 10 seconds
    _voiceTimeoutTimer?.cancel();
    _voiceTimeoutTimer = Timer(const Duration(seconds: 10), () {
      stopVoiceSearch();
    });

    // Fallback: If TV did not send RemoteVoiceBegin within 700ms, start session with id 1
    Future.delayed(const Duration(milliseconds: 700), () {
      if (_isVoiceRecording && _activeVoiceSessionId == null) {
        _activeVoiceSessionId = 1;
        r.sendVoiceBegin(1);
        _safeNotifyListeners();
      }
    });
  }

  void _onTvVoiceSessionStarted(int sessionId) {
    _activeVoiceSessionId = sessionId;
    _safeNotifyListeners();
  }

  Future<void> stopVoiceSearch() async {
    _voiceTimeoutTimer?.cancel();
    _voiceTimeoutTimer = null;

    final sessionId = _activeVoiceSessionId;
    _activeVoiceSessionId = null;
    _isVoiceRecording = false;

    try {
      await _audioStreamSub?.cancel();
      _audioStreamSub = null;
      if (_audioRecorder != null && await _audioRecorder!.isRecording()) {
        await _audioRecorder!.stop();
      }
    } catch (_) {}

    final r = _remote;
    if (r != null && r.isConnected && sessionId != null) {
      final buffer = _voiceAudioBuffer;
      if (buffer != null && buffer.isNotEmpty) {
        final remaining = buffer.takeBytes();
        if (remaining.length >= 8192) {
          r.sendVoicePayload(sessionId, remaining);
        } else {
          // Pad with silence up to 8192 bytes so the last payload meets TV threshold
          final padded = Uint8List(8192);
          padded.setRange(0, remaining.length, remaining);
          r.sendVoicePayload(sessionId, padded);
        }
      }
      r.sendVoiceEnd(sessionId);
    }
    _voiceAudioBuffer = null;

    _safeNotifyListeners();
  }

  /// Called when the flyout opens: reconnect right away if offline.
  void ensureConnected() {
    if (_status == TvStatus.offline) {
      _attempt = 0;
      connect();
    }
  }

  // --------------------------------------------------------------- commands

  void sendKey(int keyCode, [KeyDirection d = KeyDirection.short]) {
    if (keyCode == KeyCode.back || keyCode == KeyCode.home || keyCode == KeyCode.power) {
      clearIme();
    }
    final r = _remote;
    if (r != null && r.isConnected) {
      r.sendKey(keyCode, d);
      if (_powerOn != true) {
        _powerOn = true;
      }
    } else if (relayKeyHandler != null) {
      relayKeyHandler!(keyCode, d);
      if (_powerOn != true) {
        _powerOn = true;
      }
    } else {
      ensureConnected();
    }

    final tvHost = selected?.host;
    if (tvHost != null) {
      unawaited(AdbService.instance.ensureConnected(tvHost));
    }

    // Refresh foreground app after sending keys (debounced)
    Future.delayed(const Duration(milliseconds: 400), () {
      AdbService.instance.checkForegroundApp();
    });
    if (keyCode == KeyCode.power || keyCode == KeyCode.home) {
      Future.delayed(const Duration(milliseconds: 1600), () {
        AdbService.instance.checkForegroundApp();
      });
    }
  }

  /// Sends text to the TV input field (Google Home protocol + ADB universal typing).
  Future<void> sendText(String text, {bool submit = false}) async {
    if (_powerOn != true) _powerOn = true;

    final adb = AdbService.instance;
    final adbConnected = adb.state == AdbState.connected && text.isNotEmpty;

    if (adbConnected) {
      // ADB shell input text é o método mais universal e confiável em qualquer app da TV
      unawaited(adb.sendText(text));
    }

    final r = _remote;
    if (r != null && r.isConnected) {
      if (!adbConnected) {
        // Envia via IME do Android TV Remote (Google Home)
        r.sendText(text);
        // E envia como sequência de keycodes caso o app atual na TV não utilize o IME remoto
        r.sendKeySequence(text);
      }
    } else if (relayTextHandler != null) {
      if (!adbConnected) {
        relayTextHandler!(text);
      }
    } else if (!adbConnected) {
      ensureConnected();
    }

    if (submit) {
      await Future.delayed(const Duration(milliseconds: 100));
      sendKey(KeyCode.enter);
    }
  }

  void seekMedia(double seconds) {
    final c = _cast;
    if (c != null && c.isConnected) {
      c.seek(seconds);
    } else if (relaySeekMediaHandler != null) {
      relaySeekMediaHandler!(seconds);
    }
    if (_nowPlaying != null && _nowPlaying!.duration != null) {
      _nowPlaying = NowPlayingInfo(
        appName: _nowPlaying!.appName,
        appPackage: _nowPlaying!.appPackage,
        title: _nowPlaying!.title,
        artist: _nowPlaying!.artist,
        imageUrl: _nowPlaying!.imageUrl,
        isPlaying: _nowPlaying!.isPlaying,
        duration: _nowPlaying!.duration,
        currentTime: seconds,
      );
      if (!_disposed) notifyListeners();
    }
  }

  void launchApp(String link) {
    if (link == 'settings' || link == 'action:settings' || link == 'android.settings.SETTINGS') {
      sendKey(KeyCode.settings);
      return;
    }
    final r = _remote;
    if (r != null && r.isConnected) {
      r.launchApp(link);
    } else if (relayLaunchAppHandler != null) {
      relayLaunchAppHandler!(link);
    } else {
      ensureConnected();
    }
  }

  // -------------------------------------------------------------- TV list

  Future<void> selectTv(String id) async {
    _selectedId = id;
    await _store.save(_tvs, _selectedId);
    _powerOn = null;
    _volume = null;
    notifyListeners();
    await connect();
  }

  Future<void> renameTv(String id, String name) async {
    _tvs = [for (final t in _tvs) t.id == id ? t.copyWith(name: name) : t];
    await _store.save(_tvs, _selectedId);
    notifyListeners();
  }

  Future<void> updateTv(
    String id, {
    String? name,
    String? host,
    String? manufacturer,
    String? model,
  }) async {
    _tvs = [
      for (final t in _tvs)
        if (t.id == id)
          t.copyWith(
            name: name,
            host: host,
            manufacturer: manufacturer,
            model: model,
          )
        else
          t,
    ];
    await _store.save(_tvs, _selectedId);
    notifyListeners();
  }

  Future<void> removeTv(String id, {bool keepPairing = false}) async {
    final tvToRemove = _tvs.where((t) => t.id == id).firstOrNull;
    _tvs = _tvs.where((t) => t.id != id).toList();

    if (keepPairing && tvToRemove != null) {
      if (!_savedPairings.any((p) => p.id == tvToRemove.id || p.host == tvToRemove.host)) {
        _savedPairings = [..._savedPairings, tvToRemove];
      }
      await _store.saveSavedPairings(_savedPairings);
    } else if (!keepPairing) {
      _savedPairings = _savedPairings.where((p) => p.id != id).toList();
      await _store.saveSavedPairings(_savedPairings);
    }

    if (_selectedId == id) {
      _selectedId = _tvs.firstOrNull?.id;
      await _teardown();
    }
    await _store.save(_tvs, _selectedId);
    if (selected == null) {
      _setStatus(TvStatus.noTv);
    } else {
      await connect();
    }
    notifyListeners();
  }

  /// Reconecta diretamente a uma TV previamente pareada (mantendo o PIN/certificado existente)
  Future<void> reconnectSavedTv(TvDevice tv) async {
    if (!_tvs.any((t) => t.id == tv.id || t.host == tv.host)) {
      _tvs = [..._tvs, tv];
    }
    _selectedId = tv.id;
    await _store.save(_tvs, _selectedId);
    _powerOn = null;
    _volume = null;
    notifyListeners();
    await connect();
  }

  /// Remove permanentemente uma TV da lista de pareamentos salvos
  Future<void> removeSavedPairing(String id) async {
    _savedPairings = _savedPairings.where((p) => p.id != id).toList();
    await _store.saveSavedPairings(_savedPairings);
    notifyListeners();
  }

  // --------------------------------------------------------------- pairing

  /// Step 1: connect to the TV and make it show the pairing code.
  Future<void> startPairing(String host) async {
    final id = _identity ?? await ClientIdentity.loadOrCreate();
    _identity = id;
    await _pairing?.close();
    _pairing = PairingClient(
      host: host,
      context: id.toSecurityContext(),
      clientCertDer: id.certDer,
      clientName: 'TV Remote (${Platform.localHostname})',
    );
    await _pairing!.start();
  }

  String? get pairingServerName => _pairing?.serverName;

  /// Step 2: send the code; on success the TV is saved and selected.
  Future<void> finishPairing(String host, String name, String code) async {
    final p = _pairing;
    if (p == null) throw PairingException('not_started');
    final detectedName = p.serverName;
    await p.finish(code);
    _pairing = null;

    TvMetadata? meta;
    try {
      meta = await TvDiscovery.resolveTvMetadata(host);
    } catch (_) {}

    String finalName = name.trim();
    if (finalName.isEmpty || finalName == host) {
      if (detectedName != null && detectedName.isNotEmpty) {
        finalName = detectedName;
      } else if (meta != null && meta.name.isNotEmpty) {
        finalName = meta.name;
      } else {
        finalName = host;
      }
    }

    final existing = _tvs.where((t) => t.host == host).firstOrNull;
    final tv = existing?.copyWith(
          name: finalName,
          manufacturer: meta?.manufacturer ?? existing.manufacturer,
          model: meta?.model ?? existing.model,
        ) ??
        TvDevice(
          id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
          name: finalName,
          host: host,
          manufacturer: meta?.manufacturer,
          model: meta?.model,
        );
    if (existing == null) {
      _tvs = [..._tvs, tv];
    } else {
      _tvs = [for (final t in _tvs) t.id == existing.id ? tv : t];
    }
    _selectedId = tv.id;
    await _store.save(_tvs, _selectedId);
    if (!_savedPairings.any((p) => p.id == tv.id || p.host == tv.host)) {
      _savedPairings = [..._savedPairings, tv];
      await _store.saveSavedPairings(_savedPairings);
    }
    _attempt = 0;
    await connect();
  }

  Future<void> cancelPairing() async {
    await _pairing?.close();
    _pairing = null;
  }

  @override
  void dispose() {
    AdbService.instance.removeListener(_onAdbChanged);
    _disposed = true;
    _reconnectTimer?.cancel();
    _voiceTimeoutTimer?.cancel();
    _audioRecorder?.dispose();
    _teardown();
    _pairing?.close();
    _externalKeystrokeCtrl.close();
    _externalBackspaceCtrl.close();
    super.dispose();
  }
}
