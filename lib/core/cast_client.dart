import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'protobuf.dart';

/// Status of media playing on Google Cast (Chromecast / Android TV port 8009).
class CastMediaStatus {
  final String? title;
  final String? artist;
  final String? imageUrl;
  final String? appName;
  final bool isPlaying;
  final double? duration;
  final double? currentTime;

  const CastMediaStatus({
    this.title,
    this.artist,
    this.imageUrl,
    this.appName,
    this.isPlaying = false,
    this.duration,
    this.currentTime,
  });

  bool get hasMedia =>
      (title != null && title!.isNotEmpty) ||
      (imageUrl != null && imageUrl!.isNotEmpty);

  bool get hasContent =>
      hasMedia ||
      (appName != null &&
          appName!.isNotEmpty &&
          appName != 'Backdrop' &&
          appName != 'Screen Saver');
}

/// Lightweight Google Cast (CastV2) client on port 8009.
///
/// Discovers currently playing media, title, artist, thumbnail artwork,
/// and playback state directly from the TV's Chromecast receiver.
class CastClient {
  static const port = 8009;
  final String host;

  SecureSocket? _socket;
  StreamSubscription<List<int>>? _sub;
  Timer? _heartbeatTimer;
  Timer? _pollTimer;
  Timer? _reconnectTimer;
  bool _disposed = false;
  int _requestId = 1;

  final List<int> _buffer = [];
  String? _activeTransportId;
  String? _currentAppName;
  int? _mediaSessionId;
  CastMediaStatus? _lastStatus;

  final _statusCtrl = StreamController<CastMediaStatus?>.broadcast();
  Stream<CastMediaStatus?> get mediaStatus => _statusCtrl.stream;
  CastMediaStatus? get currentStatus => _lastStatus;
  bool get isConnected => _socket != null;

  CastClient({required this.host});

  int _nextRequestId() => _requestId++;

  Future<void> connect() async {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    await _closeSocket();

    try {
      final s = await SecureSocket.connect(
        host,
        port,
        context: SecurityContext(withTrustedRoots: false),
        onBadCertificate: (cert) => true,
        timeout: const Duration(seconds: 4),
      );
      if (_disposed) {
        await s.close();
        return;
      }
      _socket = s;
      s.done.catchError((_) {});
      _buffer.clear();
      _sub = s.listen(
        _onData,
        onError: (_) => _scheduleReconnect(),
        onDone: () => _scheduleReconnect(),
        cancelOnError: true,
      );

      // 1. Establish connection to receiver-0
      _send(
        sourceId: 'sender-0',
        destinationId: 'receiver-0',
        namespace: 'urn:x-cast:com.google.cast.tp.connection',
        payload: {'type': 'CONNECT'},
      );

      // 2. Query initial receiver status
      _requestReceiverStatus();

      // 3. Keep connection alive with periodic heartbeats & status refresh
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        _send(
          sourceId: 'sender-0',
          destinationId: 'receiver-0',
          namespace: 'urn:x-cast:com.google.cast.tp.heartbeat',
          payload: {'type': 'PING'},
        );
      });

      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 6), (_) {
        _requestReceiverStatus();
        if (_activeTransportId != null) {
          _requestMediaStatus(_activeTransportId!);
        }
      });
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _heartbeatTimer?.cancel();
    _pollTimer?.cancel();
    _closeSocket();
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 10), connect);
  }

  Future<void> _closeSocket() async {
    try {
      await _sub?.cancel();
    } catch (_) {}
    _sub = null;
    try {
      _socket?.destroy();
    } catch (_) {}
    _socket = null;
  }

  void _onData(List<int> chunk) {
    _buffer.addAll(chunk);
    while (true) {
      if (_buffer.length < 4) break;
      final len = (_buffer[0] << 24) |
          (_buffer[1] << 16) |
          (_buffer[2] << 8) |
          _buffer[3];
      if (_buffer.length < 4 + len) break;
      final payload = Uint8List.fromList(_buffer.sublist(4, 4 + len));
      _buffer.removeRange(0, 4 + len);
      try {
        final msg = ProtoMessage.parse(payload);
        _handleCastMessage(msg);
      } catch (_) {}
    }
  }

  void _handleCastMessage(ProtoMessage msg) {
    final ns = msg.string(4);
    final payloadUtf8 = msg.string(6);
    if (ns == null || payloadUtf8 == null) return;

    Map<String, dynamic> data;
    try {
      data = jsonDecode(payloadUtf8) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final type = data['type'] as String?;

    if (ns == 'urn:x-cast:com.google.cast.tp.heartbeat') {
      if (type == 'PING') {
        _send(
          sourceId: 'sender-0',
          destinationId: 'receiver-0',
          namespace: 'urn:x-cast:com.google.cast.tp.heartbeat',
          payload: {'type': 'PONG'},
        );
      }
    } else if (ns == 'urn:x-cast:com.google.cast.receiver') {
      if (type == 'RECEIVER_STATUS') {
        _handleReceiverStatus(data);
      }
    } else if (ns == 'urn:x-cast:com.google.cast.media') {
      if (type == 'MEDIA_STATUS') {
        _handleMediaStatus(data);
      }
    }
  }

  void _handleReceiverStatus(Map<String, dynamic> data) {
    final status = data['status'] as Map<String, dynamic>?;
    final apps = status?['applications'] as List?;
    if (apps == null || apps.isEmpty) {
      _activeTransportId = null;
      _currentAppName = null;
      _emitStatus(null);
      return;
    }

    final app = apps.first as Map<String, dynamic>;
    final displayName = app['displayName'] as String?;
    final transportId = app['transportId'] as String?;
    _currentAppName = displayName;

    final namespaces = (app['namespaces'] as List?)
            ?.map((e) => (e as Map)['name']?.toString())
            .toList() ??
        [];

    final isSystemIdle = displayName == null ||
        displayName.isEmpty ||
        displayName == 'Backdrop' ||
        displayName == 'Screen Saver' ||
        displayName == 'Ambient Mode' ||
        displayName == 'Default Media Receiver';

    if (transportId != null &&
        namespaces.contains('urn:x-cast:com.google.cast.media')) {
      if (_activeTransportId != transportId) {
        _activeTransportId = transportId;
        _send(
          sourceId: 'sender-0',
          destinationId: transportId,
          namespace: 'urn:x-cast:com.google.cast.tp.connection',
          payload: {'type': 'CONNECT'},
        );
        _requestMediaStatus(transportId);
      }

      // Immediately emit status so appName is known without waiting for media to play
      if (!isSystemIdle) {
        if (_lastStatus != null && _lastStatus?.appName == displayName) {
          _emitStatus(_lastStatus);
        } else {
          _emitStatus(CastMediaStatus(
            appName: displayName,
            isPlaying: false,
          ));
        }
      } else {
        _emitStatus(null);
      }
    } else {
      _activeTransportId = null;
      if (!isSystemIdle) {
        _emitStatus(CastMediaStatus(
          appName: displayName,
          isPlaying: false,
        ));
      } else {
        _emitStatus(null);
      }
    }
  }

  void _handleMediaStatus(Map<String, dynamic> data) {
    final statuses = data['status'] as List?;
    if (statuses == null || statuses.isEmpty) {
      if (_currentAppName != null &&
          _currentAppName != 'Backdrop' &&
          _currentAppName != 'Screen Saver' &&
          _currentAppName != 'Ambient Mode' &&
          _currentAppName != 'Default Media Receiver') {
        _emitStatus(CastMediaStatus(
          appName: _currentAppName,
          isPlaying: false,
        ));
      } else {
        _emitStatus(null);
      }
      return;
    }

    final s = statuses.first as Map<String, dynamic>;
    _mediaSessionId = (s['mediaSessionId'] as num?)?.toInt();
    final playerState = s['playerState'] as String?;
    final isPlaying = playerState == 'PLAYING' || playerState == 'BUFFERING';

    final media = s['media'] as Map<String, dynamic>?;
    final metadata = media?['metadata'] as Map<String, dynamic>?;

    final title = metadata?['title'] as String? ??
        metadata?['seriesTitle'] as String? ??
        metadata?['episodeTitle'] as String?;
    final artist = metadata?['artist'] as String? ??
        metadata?['subtitle'] as String? ??
        metadata?['studio'] as String?;

    final images = metadata?['images'] as List?;
    String? imageUrl;
    if (images != null && images.isNotEmpty) {
      final img = images.first as Map<String, dynamic>?;
      imageUrl = img?['url'] as String?;
    }

    final duration = (media?['duration'] as num?)?.toDouble();
    final currentTime = (s['currentTime'] as num?)?.toDouble();

    final status = CastMediaStatus(
      title: title,
      artist: artist,
      imageUrl: imageUrl,
      appName: _currentAppName,
      isPlaying: isPlaying,
      duration: duration,
      currentTime: currentTime,
    );
    _emitStatus(status);
  }

  void _emitStatus(CastMediaStatus? s) {
    _lastStatus = s;
    if (!_disposed && !_statusCtrl.isClosed) {
      _statusCtrl.add(s);
    }
  }

  void _requestReceiverStatus() {
    _send(
      sourceId: 'sender-0',
      destinationId: 'receiver-0',
      namespace: 'urn:x-cast:com.google.cast.receiver',
      payload: {'type': 'GET_STATUS', 'requestId': _nextRequestId()},
    );
  }

  void _requestMediaStatus(String transportId) {
    _send(
      sourceId: 'sender-0',
      destinationId: transportId,
      namespace: 'urn:x-cast:com.google.cast.media',
      payload: {'type': 'GET_STATUS', 'requestId': _nextRequestId()},
    );
  }

  void seek(double seconds) {
    if (_activeTransportId == null) return;
    final payload = <String, dynamic>{
      'type': 'SEEK',
      'requestId': _nextRequestId(),
      'currentTime': seconds,
    };
    if (_mediaSessionId != null) {
      payload['mediaSessionId'] = _mediaSessionId;
    }
    _send(
      sourceId: 'sender-0',
      destinationId: _activeTransportId!,
      namespace: 'urn:x-cast:com.google.cast.media',
      payload: payload,
    );
  }

  void _send({
    required String sourceId,
    required String destinationId,
    required String namespace,
    required Map<String, dynamic> payload,
  }) {
    final s = _socket;
    if (s == null) return;
    try {
      final payloadStr = jsonEncode(payload);
      final body = ProtoWriter()
          .int32(1, 0)
          .string(2, sourceId)
          .string(3, destinationId)
          .string(4, namespace)
          .int32(5, 0)
          .string(6, payloadStr)
          .toBytes();

      final header = Uint8List(4);
      ByteData.view(header.buffer).setUint32(0, body.length, Endian.big);
      s.add(header);
      s.add(body);
    } catch (_) {}
  }

  Future<void> close() async {
    _disposed = true;
    _heartbeatTimer?.cancel();
    _pollTimer?.cancel();
    _reconnectTimer?.cancel();
    await _closeSocket();
    await _statusCtrl.close();
  }
}
