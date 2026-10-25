import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_adb/flutter_adb.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pure Dart ADB client using the flutter_adb package.
/// Implements full ADB state machine with persistent RSA-2048 authentication,
/// CNXN/AUTH/STLS handshakes, and an active interactive shell stream for instant keyevents.
class AdbSocketClient {
  static const String _cryptoPrefKey = 'tv_remote_adb_crypto_hex';

  final String host;
  final int port;

  VoidCallback? onWaitingAuth;

  AdbConnection? _connection;
  AdbStream? _shellStream;
  AdbCrypto? _crypto;

  bool _connected = false;
  bool _unauthorized = false;
  bool _isConnecting = false;

  AdbSocketClient({required this.host, this.port = 5555});

  bool get isConnected => _connected && _connection != null && _connection!.connected;
  bool get isUnauthorized => _unauthorized;

  /// Loads the persisted RSA-2048 keypair from SharedPreferences or generates a new one.
  /// Ensuring the keypair is persistent prevents Android TV from asking for permission on every connection.
  static Future<AdbCrypto> loadOrCreateCrypto() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_cryptoPrefKey);
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        final keyPair = AdbCrypto.keyPairFromStorageMap(map);
        return AdbCrypto(
          keyPair: keyPair,
          adbKeyName: 'TVRemote@Android',
        );
      } catch (e) {
        debugPrint('Error loading saved AdbCrypto keypair: $e');
      }
    }

    final crypto = AdbCrypto(adbKeyName: 'TVRemote@Android');
    try {
      final exported = crypto.exportKeyPairForStorage();
      await prefs.setString(_cryptoPrefKey, jsonEncode(exported));
    } catch (e) {
      debugPrint('Error saving AdbCrypto keypair: $e');
    }
    return crypto;
  }

  static Future<String> _resolveIp(String targetHost) async {
    final parsed = InternetAddress.tryParse(targetHost);
    if (parsed != null) return parsed.address;
    try {
      final lookup = await InternetAddress.lookup(targetHost);
      if (lookup.isNotEmpty) return lookup.first.address;
    } catch (_) {}
    return targetHost;
  }

  /// Connects and performs initial ADB handshake (CNXN + RSA AUTH)
  Future<bool> connect({
    Duration connectTimeout = const Duration(seconds: 4),
    Duration? timeout,
    Duration authWaitTimeout = const Duration(seconds: 60),
  }) async {
    if (_isConnecting) return false;
    _isConnecting = true;
    _unauthorized = false;
    _connected = false;

    await disconnect();

    try {
      _crypto ??= await loadOrCreateCrypto();
      final targetIp = await _resolveIp(host);

      final conn = AdbConnection(targetIp, port, _crypto!);
      _connection = conn;

      // Timer: If not connected after 1.2s, the TV is displaying the "Allow USB debugging" prompt
      final authTimer = Timer(const Duration(milliseconds: 1200), () {
        if (!_connected && _isConnecting) {
          _unauthorized = true;
          onWaitingAuth?.call();
        }
      });

      // Connect: waits for TV to accept RSA signature or user to press Allow on TV screen
      final ok = await conn.connect().timeout(
        authWaitTimeout,
        onTimeout: () => false,
      );

      authTimer.cancel();

      if (ok) {
        _connected = true;
        _unauthorized = false;

        // Open persistent interactive shell stream for instant keyevents / typing
        try {
          _shellStream = await conn.open('shell:\x00');
        } catch (e) {
          debugPrint('Could not open persistent shell stream: $e');
        }

        return true;
      } else {
        await disconnect();
        return false;
      }
    } catch (e) {
      debugPrint('AdbSocketClient connection error: $e');
      await disconnect();
      return false;
    } finally {
      _isConnecting = false;
    }
  }

  /// Fast-path: writes directly to the active interactive shell stream (Zero-Latency Remote Control)
  Future<bool> sendKeyEvent(int keyCode) async {
    if (!isConnected) {
      final ok = await connect();
      if (!ok) return false;
    }

    if (_shellStream != null && !_shellStream!.isClosed) {
      try {
        final ok = await _shellStream!.writeString('input keyevent $keyCode\n');
        if (ok) return true;
      } catch (e) {
        debugPrint('Error writing keyevent to shell stream: $e');
      }
    }

    // Fallback: dedicated stream
    final res = await exec('input keyevent $keyCode');
    return !res.toLowerCase().contains('error');
  }

  /// Fast-path: writes directly to the active interactive shell stream
  Future<bool> sendText(String escapedText) async {
    if (!isConnected) {
      final ok = await connect();
      if (!ok) return false;
    }

    if (_shellStream != null && !_shellStream!.isClosed) {
      try {
        final ok = await _shellStream!.writeString('input text $escapedText\n');
        if (ok) return true;
      } catch (e) {
        debugPrint('Error writing text to shell stream: $e');
      }
    }

    // Fallback: dedicated stream
    final res = await exec('input text $escapedText');
    return !res.toLowerCase().contains('error');
  }

  /// Executes an arbitrary shell command over ADB socket
  Future<String> exec(String cmd, {Duration timeout = const Duration(seconds: 8)}) async {
    if (!isConnected) {
      final ok = await connect();
      if (!ok) return 'Não conectado ao ADB';
    }

    var cleanCmd = cmd.trim();
    if (cleanCmd.startsWith('adb ')) {
      cleanCmd = cleanCmd.substring(4).trim();
    }
    if (cleanCmd.startsWith('shell ')) {
      cleanCmd = cleanCmd.substring(6).trim();
    }

    // 1. Try opening a dedicated stream for this command: 'shell:<command>\x00'
    try {
      final stream = await _connection!.open('shell:$cleanCmd\x00');
      final outputBuffer = StringBuffer();
      final completer = Completer<String>();

      late StreamSubscription sub;
      sub = stream.onPayload.listen(
        (data) {
          outputBuffer.write(utf8.decode(data, allowMalformed: true));
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.complete(outputBuffer.toString());
          }
        },
        onError: (err) {
          if (!completer.isCompleted) {
            completer.complete(outputBuffer.toString());
          }
        },
      );

      final result = await completer.future.timeout(
        timeout,
        onTimeout: () {
          sub.cancel();
          return outputBuffer.toString();
        },
      );

      return result.trim();
    } catch (_) {
      // 2. Fallback: write to persistent shell stream if open
      if (_shellStream != null && !_shellStream!.isClosed) {
        try {
          await _shellStream!.writeString('$cleanCmd\n');
          return '';
        } catch (_) {}
      }
      return '';
    }
  }

  /// Captures a screenshot to /sdcard/screenshot.png on TV, then pulls the binary bytes
  Future<Uint8List?> fetchScreenshot({Duration timeout = const Duration(seconds: 4)}) async {
    if (!isConnected) {
      final ok = await connect();
      if (!ok) return null;
    }

    try {
      // 1. Direct stream capture via exec:screencap -p\x00
      try {
        final stream = await _connection!.open('exec:screencap -p\x00');
        final bytesBuilder = BytesBuilder(copy: false);
        final completer = Completer<Uint8List?>();

        late StreamSubscription sub;
        sub = stream.onPayload.listen(
          (chunk) {
            bytesBuilder.add(chunk);
          },
          onDone: () {
            if (!completer.isCompleted) {
              final raw = bytesBuilder.takeBytes();
              completer.complete(raw.isNotEmpty ? raw : null);
            }
          },
          onError: (_) {
            if (!completer.isCompleted) completer.complete(null);
          },
        );

        final rawBytes = await completer.future.timeout(
          timeout,
          onTimeout: () {
            sub.cancel();
            return null;
          },
        );

        if (rawBytes != null &&
            rawBytes.length > 10240 &&
            rawBytes[0] == 0x89 &&
            rawBytes[1] == 0x50 &&
            rawBytes[2] == 0x4E &&
            rawBytes[3] == 0x47) {
          return rawBytes;
        }
      } catch (_) {}

      // 2. Fallback: Save to /sdcard/screenshot.png and read base64
      await exec('screencap -p /sdcard/screenshot.png', timeout: const Duration(seconds: 2));
      final b64 = await exec('base64 /sdcard/screenshot.png', timeout: const Duration(seconds: 3));
      final clean = b64.replaceAll('\r', '').replaceAll('\n', '').trim();
      if (clean.isNotEmpty) {
        try {
          final decoded = base64Decode(clean);
          if (decoded.length > 10240 &&
              decoded[0] == 0x89 &&
              decoded[1] == 0x50 &&
              decoded[2] == 0x4E &&
              decoded[3] == 0x47) {
            return decoded;
          }
        } catch (_) {}
      }
    } catch (_) {}

    return null;
  }

  Future<void> disconnect() async {
    _connected = false;
    _unauthorized = false;
    try {
      _shellStream?.close();
    } catch (_) {}
    _shellStream = null;

    try {
      await _connection?.disconnect();
    } catch (_) {}
    _connection = null;
  }
}
