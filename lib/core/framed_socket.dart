import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'protobuf.dart';

/// TLS socket that sends/receives varint length-prefixed protobuf frames,
/// as used by both the pairing (6467) and remote (6466) services.
class FramedSocket {
  final SecureSocket socket;
  final _frames = StreamController<ProtoMessage>.broadcast();
  final _buffer = BytesBuilder(copy: false);
  late final StreamSubscription<Uint8List> _sub;
  bool _closed = false;

  FramedSocket._(this.socket) {
    socket.done.catchError((Object e) {
      if (!_frames.isClosed) _frames.addError(e);
      close();
    });
    _sub = socket.listen(
      _onData,
      onError: (Object e) {
        if (!_frames.isClosed) _frames.addError(e);
        close();
      },
      onDone: close,
      cancelOnError: true,
    );
  }

  static Future<FramedSocket> connect(
    String host,
    int port,
    SecurityContext context, {
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final s = await SecureSocket.connect(
      host,
      port,
      context: context,
      // TVs use self-signed certificates; trust is established by pairing.
      onBadCertificate: (_) => true,
      timeout: timeout,
    );
    s.setOption(SocketOption.tcpNoDelay, true);
    return FramedSocket._(s);
  }

  Stream<ProtoMessage> get frames => _frames.stream;
  bool get isClosed => _closed;
  X509Certificate? get peerCertificate => socket.peerCertificate;

  void send(ProtoWriter message) {
    if (_closed) return;
    try {
      final body = message.toBytes();
      socket.add([...ProtoWriter.varint(body.length), ...body]);
    } catch (_) {}
  }

  /// Waits for the next frame (used by the request/response pairing flow).
  Future<ProtoMessage> next({Duration timeout = const Duration(seconds: 10)}) =>
      frames.first.timeout(timeout);

  void _onData(Uint8List data) {
    _buffer.add(data);
    var bytes = _buffer.takeBytes();
    var offset = 0;
    while (true) {
      // Read varint length prefix.
      var len = 0, shift = 0, i = offset;
      var complete = false;
      while (i < bytes.length) {
        final b = bytes[i++];
        len |= (b & 0x7F) << shift;
        if (b & 0x80 == 0) {
          complete = true;
          break;
        }
        shift += 7;
      }
      if (!complete || i + len > bytes.length) break;
      final frame = Uint8List.sublistView(bytes, i, i + len);
      offset = i + len;
      try {
        _frames.add(ProtoMessage.parse(Uint8List.fromList(frame)));
      } catch (_) {
        // Ignore malformed frames instead of dropping the connection.
      }
    }
    if (offset < bytes.length) {
      _buffer.add(Uint8List.sublistView(bytes, offset));
    }
    bytes = Uint8List(0);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _sub.cancel();
    } catch (_) {}
    try {
      socket.destroy();
    } catch (_) {}
    try {
      await _frames.close();
    } catch (_) {}
  }
}
