import 'dart:async';
import 'dart:io';

import 'framed_socket.dart';
import 'keycodes.dart';
import 'protobuf.dart';

/// Volume information reported by the TV.
class VolumeInfo {
  final int level;
  final int max;
  final bool muted;
  const VolumeInfo(this.level, this.max, this.muted);
}

/// Active application info reported by the TV.
/// Active application info reported by the TV.
class AppInfo {
  final String package;
  final String? label;
  const AppInfo({required this.package, this.label});
}

/// Status of the active text input field on the TV (e.g. search box, login).
class ImeStatus {
  final bool active;
  final String? value;
  final String? label;
  final int? start;
  final int? end;
  final int imeCounter;
  final int fieldCounter;

  const ImeStatus({
    required this.active,
    this.value,
    this.label,
    this.start,
    this.end,
    this.imeCounter = 0,
    this.fieldCounter = 0,
  });
}

/// The TLS session was accepted but the TV closed it before activating the
/// remote: the client certificate is unknown, so pairing is required.
class RemoteRejectedException implements Exception {
  const RemoteRejectedException();
}

/// Remote control channel on port 6466.
///
/// RemoteMessage field numbers (from the Android TV Remote v2 protocol):
/// 1 configure · 2 set_active · 3 error · 8 ping_request · 9 ping_response
/// 10 key_inject · 20 ime_key_inject · 21 ime_batch_edit · 22 ime_show_request
/// 40 start (power) · 50 set_volume_level · 90 app_link.
class RemoteClient {
  static const port = 6466;
  // ping (1) | key (2) | ime (4) | voice (8) | power (32) | volume (64) | app_link (512)
  static const _defaultFeatures = 623;
  int _features = _defaultFeatures;

  final String host;
  final SecurityContext context;
  final String deviceModel;
  final String deviceVendor;

  FramedSocket? _socket;
  StreamSubscription<ProtoMessage>? _sub;
  final _ready = Completer<void>();

  final _powerCtrl = StreamController<bool>.broadcast();
  final _volumeCtrl = StreamController<VolumeInfo>.broadcast();
  final _closedCtrl = StreamController<Object?>.broadcast();
  final _currentAppCtrl = StreamController<AppInfo>.broadcast();
  final _imeStatusCtrl = StreamController<ImeStatus>.broadcast();
  ImeStatus? _lastImeStatus;

  RemoteClient({
    required this.host,
    required this.context,
    this.deviceModel = 'TV Remote',
    this.deviceVendor = 'Chyri',
  });

  Stream<bool> get powerState => _powerCtrl.stream;
  Stream<VolumeInfo> get volume => _volumeCtrl.stream;
  Stream<AppInfo> get currentApp => _currentAppCtrl.stream;
  Stream<ImeStatus> get imeStatus => _imeStatusCtrl.stream;
  ImeStatus? get currentImeStatus => _lastImeStatus;
  bool get hasActiveIme => _lastImeStatus?.active == true;

  void clearIme() {
    _lastImeStatus = const ImeStatus(active: false);
    if (!_imeStatusCtrl.isClosed) {
      _imeStatusCtrl.add(const ImeStatus(active: false));
    }
  }

  /// Emits once when the connection drops (with the error, if any).
  Stream<Object?> get closed => _closedCtrl.stream;

  bool get isConnected => _socket != null && !_socket!.isClosed;

  /// Connects and completes once the TV accepted us as an active remote.
  /// Throws [HandshakeException]/[SocketException] if the TV rejects the
  /// certificate (i.e. pairing is required).
  Future<void> connect() async {
    _socket = await FramedSocket.connect(host, port, context);
    _sub = _socket!.frames.listen(
      _onMessage,
      onError: (Object e) => _finish(e),
      onDone: () => _finish(null),
    );
    await _ready.future.timeout(const Duration(seconds: 8));
  }

  void _onMessage(ProtoMessage m) {
    try {
      if (m.has(1)) {
        // TV announced its configuration → answer with our capabilities.
        final cfg = m.message(1);
        final tvFeatures = cfg?.int32(1);
        if (tvFeatures != null && tvFeatures > 0) {
          _features = _defaultFeatures & tvFeatures;
        }
        _send(ProtoWriter().message(
          1,
          ProtoWriter().int32(1, _features).message(
                2,
                ProtoWriter()
                    .string(1, deviceModel)
                    .string(2, deviceVendor)
                    .int32(3, 1)
                    .string(4, '1')
                    .string(5, 'com.chyri.tv_remote')
                    .string(6, '1.0.0'),
              ),
        ));
      }
      if (m.has(2)) {
        _send(ProtoWriter().message(2, ProtoWriter().int32(1, _features)));
        if (!_ready.isCompleted) _ready.complete();
      }
      final ping = m.message(8);
      if (ping != null) {
        _send(ProtoWriter().message(9, ProtoWriter().int32(1, ping.int32(1) ?? 0)));
      }

      // Track IME counters when the TV opens or updates a text field
      final imeBatch = m.message(21);
      if (imeBatch != null) {
        final ic = imeBatch.int32(1);
        final fc = imeBatch.int32(2);
        if (ic != null) _imeCounter = ic;
        if (fc != null) _fieldCounter = fc;
      }

      final imeKey = m.message(20);
      if (imeKey != null) {
        final appInfo = imeKey.message(1);
        if (appInfo != null) {
          final c = appInfo.int32(1);
          if (c != null) _imeCounter = c;
          final pkg = appInfo.string(12);
          final label = appInfo.string(10);
          if (pkg != null && pkg.isNotEmpty && !_currentAppCtrl.isClosed) {
            _currentAppCtrl.add(AppInfo(package: pkg, label: label));
          }
        }
        final status = imeKey.message(2);
        if (status != null) {
          final fc = status.int32(1);
          if (fc != null) _fieldCounter = fc;
          final val = status.string(2);
          final lbl = status.string(6);
          final st = status.int32(3);
          final en = status.int32(4);
          _updateIme(ImeStatus(
            active: true,
            value: val,
            label: lbl,
            start: st,
            end: en,
            imeCounter: _imeCounter,
            fieldCounter: _fieldCounter,
          ));
        } else if (appInfo != null) {
          _updateIme(const ImeStatus(active: false));
        }
      }

      final imeShow = m.message(22);
      if (imeShow != null) {
        final status = imeShow.message(2);
        if (status != null) {
          final fc = status.int32(1);
          if (fc != null) _fieldCounter = fc;
          final val = status.string(2);
          final lbl = status.string(6);
          final st = status.int32(3);
          final en = status.int32(4);
          _updateIme(ImeStatus(
            active: true,
            value: val,
            label: lbl,
            start: st,
            end: en,
            imeCounter: _imeCounter,
            fieldCounter: _fieldCounter,
          ));
        }
      }

      if (m.has(23)) {
        _updateIme(const ImeStatus(active: false));
      }

      final start = m.message(40);
      if (start != null && !_powerCtrl.isClosed) {
        _powerCtrl.add(start.boolean(1) ?? false);
      }

      final vol = m.message(50);
      if (vol != null && !_volumeCtrl.isClosed) {
        final max = vol.int32(6) ?? 0;
        final level = vol.int32(7) ?? 0;
        if (max > 0 && level <= max) {
          _volumeCtrl.add(VolumeInfo(level, max, vol.boolean(8) ?? false));
        }
      }
    } catch (_) {}
  }

  void _updateIme(ImeStatus s) {
    _lastImeStatus = s;
    if (!_imeStatusCtrl.isClosed) {
      _imeStatusCtrl.add(s);
    }
  }

  void _send(ProtoWriter msg) {
    final s = _socket;
    if (s == null || s.isClosed) return;
    try {
      s.send(msg);
    } catch (_) {}
  }

  int _imeCounter = 0;
  int _fieldCounter = 0;

  void sendKey(int keyCode, [KeyDirection direction = KeyDirection.short]) {
    _send(ProtoWriter().message(
      10,
      ProtoWriter().int32(1, keyCode).int32(2, direction.value),
    ));
  }

  /// Sends text to the TV input field using the Android TV Remote v2 protocol (like Google Home).
  void sendText(String text) {
    if (text.isEmpty) {
      final editInfo = ProtoWriter()
          .int32(1, 0)
          .message(
            2,
            ProtoWriter()
                .int32(1, 0)
                .int32(2, 0)
                .string(3, ''),
          );
      _send(ProtoWriter().message(
        21,
        ProtoWriter()
            .int32(1, _imeCounter)
            .int32(2, _fieldCounter)
            .message(3, editInfo),
      ));
      return;
    }

    final pos = text.length;

    // Send single batch text edit with cursor at the end (matching Google Home)
    final editInfo = ProtoWriter()
        .int32(1, 0)
        .message(
          2,
          ProtoWriter()
              .int32(1, pos)
              .int32(2, pos)
              .string(3, text),
        );
    _send(ProtoWriter().message(
      21,
      ProtoWriter()
          .int32(1, _imeCounter)
          .int32(2, _fieldCounter)
          .message(3, editInfo),
    ));
  }

  /// Sends raw alphanumeric characters as KeyCodes (for apps where IME batch edit is unsupported)
  void sendKeySequence(String text) {
    for (var i = 0; i < text.length; i++) {
      final code = charToKeyCode(text[i]);
      if (code != null) {
        sendKey(code);
      }
    }
  }

  void launchApp(String link) {
    _send(ProtoWriter().message(90, ProtoWriter().string(1, link)));
  }

  void _finish(Object? error) {
    if (!_ready.isCompleted) {
      _ready.completeError(error ?? const RemoteRejectedException());
    }
    if (!_closedCtrl.isClosed) {
      _closedCtrl.add(error);
    }
    _socket = null;
  }

  Future<void> close() async {
    await _sub?.cancel();
    await _socket?.close();
    _socket = null;
    await _powerCtrl.close();
    await _volumeCtrl.close();
    await _closedCtrl.close();
    await _currentAppCtrl.close();
    await _imeStatusCtrl.close();
  }
}

/// Converts basic characters into Android TV Remote KeyCodes
int? charToKeyCode(String char) {
  if (char.isEmpty) return null;
  final code = char.codeUnitAt(0);
  if (code >= 97 && code <= 122) return 29 + (code - 97); // a-z
  if (code >= 65 && code <= 90) return 29 + (code - 65);  // A-Z
  if (code >= 48 && code <= 57) return 7 + (code - 48);   // 0-9
  switch (char) {
    case ' ': return 62; // KEYCODE_SPACE
    case '\n':
    case '\r': return 66; // KEYCODE_ENTER
    case ',': return 55; // KEYCODE_COMMA
    case '.': return 56; // KEYCODE_PERIOD
    case '/': return 76; // KEYCODE_SLASH
    case '-': return 69; // KEYCODE_MINUS
    case '=': return 70; // KEYCODE_EQUALS
    case '@': return 77; // KEYCODE_AT
    default: return null;
  }
}
