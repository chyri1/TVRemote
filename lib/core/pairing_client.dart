import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'der.dart';
import 'framed_socket.dart';
import 'protobuf.dart';

class PairingException implements Exception {
  final String code;
  PairingException(this.code);
  @override
  String toString() => 'PairingException($code)';
}

/// Implements the "Polo" pairing handshake on port 6467.
///
/// Flow: PairingRequest → Options → Configuration → (TV shows 6-hex code)
/// → Secret. The secret proves both sides saw the same code and binds the
/// client certificate to the TV.
class PairingClient {
  static const port = 6467;
  static const _statusOk = 200;

  final String host;
  final SecurityContext context;
  final Uint8List clientCertDer;
  final String clientName;

  FramedSocket? _socket;

  PairingClient({
    required this.host,
    required this.context,
    required this.clientCertDer,
    required this.clientName,
  });

  ProtoWriter _outer() => ProtoWriter().int32(1, 2).int32(2, _statusOk);

  ProtoWriter _hexEncoding() => ProtoWriter().int32(1, 3).int32(2, 6);

  Future<ProtoMessage> _exchange(ProtoWriter msg, int expectField) async {
    final s = _socket!;
    final reply = s.next(timeout: const Duration(seconds: 15));
    s.send(msg);
    final m = await reply;
    final status = m.int32(2) ?? _statusOk;
    if (status != _statusOk) throw PairingException('status_$status');
    if (!m.has(expectField)) throw PairingException('unexpected_reply');
    return m;
  }

  String? _serverName;
  String? get serverName => _serverName;

  /// Opens the connection and asks the TV to display the pairing code.
  Future<void> start() async {
    await close();
    _socket = await FramedSocket.connect(host, port, context);

    final ack = await _exchange(
      _outer().message(
        10,
        ProtoWriter().string(1, 'atvremote').string(2, clientName),
      ),
      11,
    );
    _serverName = ack.message(11)?.string(1);
    await _exchange(
      _outer().message(
        20,
        ProtoWriter().message(1, _hexEncoding()).int32(3, 1),
      ),
      20,
    );
    await _exchange(
      _outer().message(
        30,
        ProtoWriter().message(1, _hexEncoding()).int32(2, 1),
      ),
      31,
    );
    // The TV now shows the code on screen.
  }

  /// Sends the secret derived from the 6-character code shown on the TV.
  Future<void> finish(String code) async {
    final s = _socket;
    if (s == null || s.isClosed) throw PairingException('not_started');
    final clean = code.trim().toUpperCase();
    if (!RegExp(r'^[0-9A-F]{6}$').hasMatch(clean)) {
      throw PairingException('invalid_code');
    }
    final serverDer = s.peerCertificate?.der;
    if (serverDer == null) throw PairingException('no_server_cert');

    final client = rsaPublicKeyFromCertificateDer(clientCertDer);
    final server = rsaPublicKeyFromCertificateDer(Uint8List.fromList(serverDer));

    final codeBytes = <int>[
      for (var i = 2; i < 6; i += 2) int.parse(clean.substring(i, i + 2), radix: 16),
    ];
    final digest = sha256.convert([
      ...client.modulus,
      ...client.exponent,
      ...server.modulus,
      ...server.exponent,
      ...codeBytes,
    ]).bytes;

    // The first byte of the hash must match the first code byte; this
    // detects typos locally before bothering the TV.
    if (digest[0] != int.parse(clean.substring(0, 2), radix: 16)) {
      throw PairingException('wrong_code');
    }

    await _exchange(
      _outer().message(40, ProtoWriter().bytes(1, digest)),
      41,
    );
    await close();
  }

  Future<void> close() async {
    await _socket?.close();
    _socket = null;
  }
}
