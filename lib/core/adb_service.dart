import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'app_settings.dart';

enum AdbState {
  idle,
  checking,
  missingAdb,
  downloadingAdb,
  connecting,
  unauthorized,
  connected,
  error,
}

enum MirrorMode {
  castMedia,
  adbScreen,
}

/// Represents an execution or connection log entry from the ADB command line.
class AdbLogEntry {
  final DateTime timestamp;
  final String command;
  final String output;
  final int exitCode;
  final bool isError;

  const AdbLogEntry({
    required this.timestamp,
    required this.command,
    required this.output,
    this.exitCode = 0,
    this.isError = false,
  });

  String get timeFormatted {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class AdbService extends ChangeNotifier {
  static final AdbService instance = AdbService._();
  AdbService._();

  final List<AdbLogEntry> _logs = [];
  List<AdbLogEntry> get logs => List.unmodifiable(_logs);

  void addLog(String command, String output, {int exitCode = 0, bool isError = false}) {
    if (_logs.length >= 250) {
      _logs.removeAt(0);
    }
    _logs.add(AdbLogEntry(
      timestamp: DateTime.now(),
      command: command,
      output: output.trim(),
      exitCode: exitCode,
      isError: isError,
    ));
    notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  AdbState _state = AdbState.idle;
  AdbState get state => _state;

  MirrorMode _mode = MirrorMode.castMedia;
  MirrorMode get mode => _mode;

  String? _adbPath;
  String? get adbPath => _adbPath;

  bool get isMinimalAdb =>
      _adbPath != null && _adbPath!.toLowerCase().contains('minimal adb');

  bool get isStandardAdb =>
      _adbPath != null && !_adbPath!.toLowerCase().contains('minimal adb');

  String get adbVariantShortName {
    if (_adbPath == null) return 'Desconhecido';
    return isMinimalAdb ? 'Minimal ADB' : 'ADB Padrão';
  }

  String get adbVariantFullName {
    if (_adbPath == null) return 'ADB não encontrado';
    return isMinimalAdb
        ? 'Minimal ADB and Fastboot'
        : 'ADB Padrão (Platform-Tools)';
  }

  String? _connectedHost;
  String? get connectedHost => _connectedHost;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  String? getErrorMessageTr() {
    if (_errorMessage == null) return null;
    if (_state == AdbState.unauthorized) {
      return appTr(
        pt: 'Aguardando autorização na TV.\nOlhe para a tela da TV e marque "Sempre permitir deste computador", depois clique em OK.',
        en: 'Waiting for authorization on TV.\nCheck the TV screen, check "Always allow from this computer", and select OK.',
        es: 'Esperando autorización en la TV.\nMira la pantalla de la TV y marca "Permitir siempre desde esta computadora", luego pulsa OK.',
      );
    }
    if (_errorMessage!.contains('offline')) {
      return appTr(
        pt: 'A TV está offline na porta $_adbPort.\nVerifique se a depuração está ativa nessa porta.',
        en: 'The TV is offline on port $_adbPort.\nCheck if debugging is enabled on this port.',
        es: 'La TV está desconectada en el puerto $_adbPort.\nComprueba si la depuración está activa en ese puerto.',
      );
    }
    if (_errorMessage!.contains('Não foi possível') ||
        _errorMessage!.contains('target') ||
        _errorMessage!.contains('conectar')) {
      final host = _connectedHost ?? 'TV';
      return appTr(
        pt: 'Não foi possível conectar a $host:$_adbPort.\nVerifique se a "Depuração por rede" ou "Depuração USB" está ativada nas Opções do Desenvolvedor da TV na porta $_adbPort.',
        en: 'Could not connect to $host:$_adbPort.\nVerify that "Network debugging" or "USB debugging" is enabled in Developer Options on the TV for port $_adbPort.',
        es: 'No se pudo conectar a $host:$_adbPort.\nVerifica si la "Depuración por red" o "Depuración USB" está activada en las Opciones de Desarrollador de la TV en el puerto $_adbPort.',
      );
    }
    return _errorMessage;
  }

  double _downloadProgress = 0.0;
  double get downloadProgress => _downloadProgress;

  Uint8List? _currentFrame;
  Uint8List? get currentFrame => _currentFrame;

  String? _currentAppPackage;
  String? get currentAppPackage => _currentAppPackage;

  String? _currentAppName;
  String? get currentAppName => _currentAppName;

  static void Function(String? pkg, String? appName, bool isScreenOn)? onAppInfoBroadcast;

  bool? _isScreenOn;
  bool? get isScreenOn => _isScreenOn;
  bool get isScreenOff => _isScreenOn == false;

  bool _isStreaming = false;
  bool get isStreaming => _isStreaming;

  Timer? _streamTimer;
  Timer? _authPollTimer;
  Timer? _appDetectTimer;
  bool _isFetchingFrame = false;
  bool _isCheckingApp = false;
  int _consecutiveCheckErrors = 0;

  int _adbPort = 5555;
  int get adbPort => _adbPort;

  void updateForegroundApp({
    String? package,
    String? appName,
    bool? isScreenOn,
    bool broadcast = true,
  }) {
    bool changed = false;
    if (isScreenOn != null && _isScreenOn != isScreenOn) {
      _isScreenOn = isScreenOn;
      changed = true;
    }
    if (package != null && package != _currentAppPackage) {
      _currentAppPackage = package;
      changed = true;
    }
    if (appName != null && appName != _currentAppName) {
      _currentAppName = appName;
      changed = true;
    }
    if (changed) {
      notifyListeners();
      if (broadcast) {
        onAppInfoBroadcast?.call(_currentAppPackage, _currentAppName, _isScreenOn ?? true);
      }
    }
  }

  void setAdbPort(int port) {
    if (_adbPort == port) return;
    _adbPort = port;
    notifyListeners();
  }

  void setMode(MirrorMode newMode) {
    if (_mode == newMode) return;
    _mode = newMode;
    notifyListeners();
    if (_mode == MirrorMode.castMedia) {
      stopStreaming();
    } else if (_mode == MirrorMode.adbScreen) {
      if (_state == AdbState.connected && !_isStreaming) {
        startStreaming();
      } else if (_connectedHost != null && _state == AdbState.idle) {
        connectToTv(_connectedHost!, port: _adbPort);
      }
    }
  }

  /// Checks if Minimal ADB and Fastboot is installed on the system
  static String? detectMinimalAdbPath() {
    final programFilesX86 = Platform.environment['ProgramFiles(x86)'];
    final programFiles = Platform.environment['ProgramFiles'];
    final localAppDir = Platform.environment['LOCALAPPDATA'];
    final paths = [
      r'C:\Program Files (x86)\Minimal ADB and Fastboot\adb.exe',
      r'C:\Program Files\Minimal ADB and Fastboot\adb.exe',
      if (programFilesX86 != null)
        '$programFilesX86\\Minimal ADB and Fastboot\\adb.exe',
      if (programFiles != null)
        '$programFiles\\Minimal ADB and Fastboot\\adb.exe',
      if (localAppDir != null)
        '$localAppDir\\Programs\\Minimal ADB and Fastboot\\adb.exe',
    ];
    for (final p in paths) {
      try {
        if (File(p).existsSync()) return p;
      } catch (_) {}
    }
    return null;
  }

  static bool get isMinimalAdbInstalled => detectMinimalAdbPath() != null;

  /// Switches between Standard ADB (Platform-Tools) and Minimal ADB and Fastboot
  Future<void> switchVariant({required bool useMinimal}) async {
    await AppSettings.instance.setUseMinimalAdb(useMinimal);
    _adbPath = null;
    await findAdb();
    if (_connectedHost != null) {
      await reRequestConnection(_connectedHost!, _adbPort);
    }
    notifyListeners();
  }

  /// Locates adb binary or flags it as missing
  Future<String?> findAdb() async {
    _state = AdbState.checking;
    notifyListeners();

    final localAppDir = Platform.environment['LOCALAPPDATA'];
    final userProfile = Platform.environment['USERPROFILE'];

    // 1. Se a opção Minimal ADB estiver ativa, verifica primeiro os caminhos do Minimal ADB
    if (AppSettings.instance.useMinimalAdb) {
      final minimalPath = detectMinimalAdbPath();
      if (minimalPath != null) {
        _adbPath = minimalPath;
        _state = AdbState.idle;
        notifyListeners();
        return _adbPath;
      }
    }

    // 2. Check all standard Platform-Tools locations (Google Official)
    final candidatePaths = [
      r'C:\platform-tools\adb.exe',
      r'C:\plataform-tools\adb.exe',
      r'C:\adb\adb.exe',
      r'C:\Android\platform-tools\adb.exe',
      if (userProfile != null) ...[
        '$userProfile\\platform-tools\\adb.exe',
        '$userProfile\\plataform-tools\\adb.exe',
        '$userProfile\\Downloads\\platform-tools\\adb.exe',
        '$userProfile\\Downloads\\platform-tools\\platform-tools\\adb.exe',
        '$userProfile\\Downloads\\plataform-tools\\adb.exe',
      ],
      if (localAppDir != null) ...[
        '$localAppDir\\tv_remote\\tools\\platform-tools\\adb.exe',
        '$localAppDir\\Android\\Sdk\\platform-tools\\adb.exe',
        '$localAppDir\\Microsoft\\WinGet\\Links\\adb.exe',
        '$localAppDir\\Microsoft\\WinGet\\Packages\\Google.PlatformTools_Microsoft.Winget.Source_8wekyb3d8bbwe\\platform-tools\\adb.exe',
      ],
      r'D:\platform-tools\adb.exe',
      r'D:\plataform-tools\adb.exe',
      r'D:\adb\adb.exe',
    ];

    for (final path in candidatePaths) {
      if (File(path).existsSync()) {
        _adbPath = path;
        _state = AdbState.idle;
        notifyListeners();
        return _adbPath;
      }
    }

    // 3. Check System PATH
    try {
      final res = await Process.run('where.exe', ['adb']);
      if (res.exitCode == 0) {
        final path = (res.stdout as String).split('\r\n').first.trim();
        if (path.isNotEmpty && File(path).existsSync()) {
          final isMinimal = path.toLowerCase().contains('minimal adb');
          if (!isMinimal || AppSettings.instance.useMinimalAdb) {
            _adbPath = path;
            _state = AdbState.idle;
            notifyListeners();
            return _adbPath;
          }
        }
      }
    } catch (_) {}

    // 4. Fallback para Minimal ADB caso o Platform-Tools padrão não tenha sido encontrado
    final fallbackMinimal = detectMinimalAdbPath();
    if (fallbackMinimal != null) {
      _adbPath = fallbackMinimal;
      _state = AdbState.idle;
      notifyListeners();
      return _adbPath;
    }

    _state = AdbState.missingAdb;
    _errorMessage = 'Platform-Tools (ADB) não encontrado.\nInstale o Google Platform-Tools ou baixe automaticamente.';
    notifyListeners();
    return null;
  }

  /// Downloads official Google Platform-Tools (ADB) standalone zip
  Future<bool> downloadPlatformTools() async {
    _state = AdbState.downloadingAdb;
    _downloadProgress = 0.05;
    _errorMessage = null;
    notifyListeners();

    try {
      final localAppDir = Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path;
      final targetToolsDir = Directory('$localAppDir\\tv_remote\\tools');
      if (!targetToolsDir.existsSync()) {
        targetToolsDir.createSync(recursive: true);
      }

      final zipPath = '${targetToolsDir.path}\\platform-tools.zip';
      final client = HttpClient();
      final request = await client.getUrl(
        Uri.parse('https://dl.google.com/android/repository/platform-tools-latest-windows.zip'),
      );
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception('Falha ao baixar do servidor do Google: HTTP ${response.statusCode}');
      }

      final totalBytes = response.contentLength;
      int downloadedBytes = 0;
      final zipFile = File(zipPath);
      final sink = zipFile.openWrite();

      await for (final chunk in response) {
        sink.add(chunk);
        downloadedBytes += chunk.length;
        if (totalBytes > 0) {
          _downloadProgress = (downloadedBytes / totalBytes).clamp(0.05, 0.95);
          notifyListeners();
        }
      }
      await sink.close();

      _downloadProgress = 0.98;
      notifyListeners();

      // Extract using PowerShell Expand-Archive
      final extractRes = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        "Expand-Archive -Path '$zipPath' -DestinationPath '${targetToolsDir.path}' -Force",
      ]);

      if (extractRes.exitCode != 0) {
        throw Exception('Erro ao descompactar platform-tools: ${extractRes.stderr}');
      }

      // Cleanup zip file
      try {
        if (zipFile.existsSync()) zipFile.deleteSync();
      } catch (_) {}

      final adbExe = File('${targetToolsDir.path}\\platform-tools\\adb.exe');
      if (adbExe.existsSync()) {
        _adbPath = adbExe.path;
        _state = AdbState.idle;
        _downloadProgress = 1.0;
        notifyListeners();
        return true;
      } else {
        throw Exception('adb.exe não encontrado após descompactação');
      }
    } catch (e) {
      _state = AdbState.error;
      _errorMessage = 'Erro no download do ADB: $e';
      notifyListeners();
      return false;
    }
  }

  /// Ensures ADB connection is established to target host and port without interrupting an active stream
  Future<void> ensureConnected(String host, {int? port}) async {
    final targetPort = port ?? _adbPort;
    if (_state == AdbState.connected && _connectedHost == host && _adbPort == targetPort) {
      if (!_isStreaming && _mode == MirrorMode.adbScreen) {
        startStreaming();
      }
      return;
    }
    if (_state == AdbState.connecting && _connectedHost == host && _adbPort == targetPort) {
      return;
    }
    await connectToTv(host, port: targetPort);
  }

  /// Connects to Android TV via ADB over TCP/IP (defaults to _adbPort, e.g. 5555)
  Future<void> connectToTv(String host, {int? port}) async {
    _connectedHost = host;
    final targetPort = port ?? _adbPort;
    _adbPort = targetPort;

    if (_state == AdbState.connected && _connectedHost == host && _adbPort == targetPort) {
      if (!_isStreaming && _mode == MirrorMode.adbScreen) {
        startStreaming();
      }
      return;
    }

    if (_adbPath == null || !File(_adbPath!).existsSync()) {
      final found = await findAdb();
      if (found == null) return;
    }

    _state = AdbState.connecting;
    _errorMessage = null;
    notifyListeners();

    try {
      final target = '$host:$targetPort';
      final connectRes = await Process.run(
        _adbPath!,
        ['connect', target],
      ).timeout(const Duration(seconds: 5));
      final stdout = connectRes.stdout?.toString().trim() ?? '';
      final stderr = connectRes.stderr?.toString().trim() ?? '';
      final combined = [if (stdout.isNotEmpty) stdout, if (stderr.isNotEmpty) stderr].join('\n');
      final outputLower = combined.toLowerCase();
      final isErr = connectRes.exitCode != 0 ||
          outputLower.contains('failed') ||
          outputLower.contains('cannot connect') ||
          outputLower.contains('unable');

      addLog(
        'adb connect $target',
        combined.isEmpty ? 'Processo finalizado (exitCode: ${connectRes.exitCode})' : combined,
        exitCode: connectRes.exitCode,
        isError: isErr,
      );

      if (isErr) {
        _state = AdbState.error;
        _errorMessage = 'Não foi possível conectar a $target.\nVerifique se a "Depuração por rede" ou "Depuração USB" está ativada nas Opções do Desenvolvedor da TV na porta $targetPort.';
        notifyListeners();
        return;
      }

      await checkAuthorization(host, port: targetPort);
    } catch (e) {
      addLog('adb connect $host:$targetPort', 'Erro ao executar ADB: $e', exitCode: 1, isError: true);
      _state = AdbState.error;
      _errorMessage = 'Erro ao executar ADB: $e';
      notifyListeners();
    }
  }

  /// Re-sends connection and authorization request to the TV.
  /// Disconnects existing socket to force Android TV to prompt for USB/Network debugging.
  Future<void> reRequestConnection([String? host, int? port]) async {
    final targetHost = host ?? _connectedHost;
    if (targetHost == null) return;
    final targetPort = port ?? _adbPort;
    _adbPort = targetPort;

    _state = AdbState.connecting;
    _errorMessage = null;
    _currentFrame = null;
    notifyListeners();

    if (_adbPath != null) {
      try {
        final discRes = await Process.run(_adbPath!, ['disconnect']);
        final out = discRes.stdout?.toString().trim() ?? '';
        addLog(
          'adb disconnect',
          out.isEmpty ? 'Conexões anteriores do ADB limpas' : out,
          exitCode: discRes.exitCode,
          isError: discRes.exitCode != 0,
        );
      } catch (_) {}
    }

    await connectToTv(targetHost, port: targetPort);
  }

  /// Checks device authorization status
  Future<void> checkAuthorization(String host, {int? port}) async {
    if (_adbPath == null) return;
    final targetPort = port ?? _adbPort;

    final target = '$host:$targetPort';
    try {
      final devicesRes = await Process.run(_adbPath!, ['devices']);
      final out = devicesRes.stdout?.toString() ?? '';
      final stderr = devicesRes.stderr?.toString().trim() ?? '';
      final logOut = [if (out.trim().isNotEmpty) out.trim(), if (stderr.isNotEmpty) stderr].join('\n');

      if (out.contains(target)) {
        final line = out.split('\n').firstWhere((l) => l.contains(target), orElse: () => '');
        if (line.contains('unauthorized')) {
          addLog('adb devices', logOut, exitCode: devicesRes.exitCode, isError: true);
          _state = AdbState.unauthorized;
          _errorMessage = 'Aguardando autorização na TV.\nOlhe para a tela da TV e marque "Sempre permitir deste computador", depois clique em OK.';
          notifyListeners();
          _startAuthPolling(host, targetPort);
          return;
        } else if (line.contains('device')) {
          addLog('adb devices', logOut, exitCode: devicesRes.exitCode, isError: false);
          _stopAuthPolling();
          _state = AdbState.connected;
          _errorMessage = null;
          notifyListeners();
          startStreaming();
          _startAppDetection();
          return;
        } else if (line.contains('offline')) {
          addLog('adb devices', logOut, exitCode: devicesRes.exitCode, isError: true);
          _stopAuthPolling();
          _state = AdbState.error;
          _errorMessage = 'A TV está offline na porta $targetPort.\nVerifique se a depuração está ativa nessa porta.';
          notifyListeners();
          return;
        }
      }

      addLog(
        'adb devices',
        logOut.isEmpty ? 'Dispositivo $target não listado na lista de devices' : logOut,
        exitCode: devicesRes.exitCode,
        isError: devicesRes.exitCode != 0,
      );

      // If not listed in devices yet, try re-connect once
      _state = AdbState.connecting;
      notifyListeners();
    } catch (e) {
      addLog('adb devices', 'Erro ao verificar devices: $e', exitCode: 1, isError: true);
    }
  }

  void _startAuthPolling(String host, int port) {
    _authPollTimer?.cancel();
    _authPollTimer = Timer.periodic(const Duration(seconds: 2), (t) async {
      if (_state != AdbState.unauthorized) {
        t.cancel();
        return;
      }
      await checkAuthorization(host, port: port);
    });
  }

  void _stopAuthPolling() {
    _authPollTimer?.cancel();
    _authPollTimer = null;
  }

  /// Starts continuous frame capture paced dynamically by ADB transfer response time
  void startStreaming() {
    if (_isStreaming) return;
    _isStreaming = true;
    _streamTimer?.cancel();
    _streamTimer = null;
    _runContinuousStream();
  }

  void stopStreaming() {
    _isStreaming = false;
    _streamTimer?.cancel();
    _streamTimer = null;
  }

  Future<void> _runContinuousStream() async {
    while (_isStreaming && _state == AdbState.connected && _adbPath != null && _connectedHost != null) {
      final success = await _fetchFrame();
      if (!_isStreaming || _state != AdbState.connected) break;
      if (!success) {
        // Pausa breve em caso de falha temporária
        await Future.delayed(const Duration(milliseconds: 350));
      } else {
        // Conforme o tempo de resposta da ADB fizer a transferência, 
        // a próxima é engatilhada imediatamente com yield mínimo para a interface
        await Future.delayed(const Duration(milliseconds: 15));
      }
    }
    _isStreaming = false;
  }

  Future<bool> _fetchFrame() async {
    if (_isFetchingFrame || _state != AdbState.connected || _adbPath == null || _connectedHost == null) {
      return false;
    }

    _isFetchingFrame = true;
    try {
      final target = '$_connectedHost:$_adbPort';

      // 1. Comando: adb shell screencap -p /sdcard/screenshot.png
      final capRes = await Process.run(
        _adbPath!,
        ['-s', target, 'shell', 'screencap', '-p', '/sdcard/screenshot.png'],
      ).timeout(const Duration(seconds: 4));

      if (capRes.exitCode != 0) {
        return false;
      }

      // 2. Comando: adb pull /sdcard/screenshot.png "C:\Windows\Temp"
      final targetDir = Directory(r'C:\Windows\Temp').existsSync()
          ? r'C:\Windows\Temp'
          : Directory.systemTemp.path;

      final pullRes = await Process.run(
        _adbPath!,
        ['-s', target, 'pull', '/sdcard/screenshot.png', targetDir],
      ).timeout(const Duration(seconds: 4));

      if (pullRes.exitCode != 0) {
        return false;
      }

      // 3. Lê o último screenshot salvo no Windows e atualiza a tela
      final localFile = File('$targetDir\\screenshot.png');
      if (await localFile.exists()) {
        final bytes = await localFile.readAsBytes();
        final len = bytes.length;
        // Validação rigorosa: cabeçalho PNG (0x89 0x50 0x4E 0x47) e marcador final de integridade IEND (0x49 0x45 0x4E 0x44)
        if (len > 64 &&
            bytes[0] == 0x89 &&
            bytes[1] == 0x50 &&
            bytes[2] == 0x4E &&
            bytes[3] == 0x47 &&
            bytes[len - 8] == 0x49 &&
            bytes[len - 7] == 0x45 &&
            bytes[len - 6] == 0x4E &&
            bytes[len - 5] == 0x44) {
          _currentFrame = bytes;
          notifyListeners();
          return true;
        }
      }
      return false;
    } catch (_) {
      // Ignora oscilações individuais de frame
      return false;
    } finally {
      _isFetchingFrame = false;
    }
  }

  /// Force capture a single fresh screenshot
  Future<void> refreshFrame() async {
    await _fetchFrame();
  }

  /// Runs an arbitrary command via connected ADB device
  Future<String> runCommand(String command) async {
    if (_adbPath == null || !File(_adbPath!).existsSync()) {
      const msg = 'ADB não encontrado no sistema.';
      addLog(command, msg, exitCode: 1, isError: true);
      return msg;
    }
    try {
      var cleanCmd = command.trim();
      if (cleanCmd.startsWith('adb ')) {
        cleanCmd = cleanCmd.substring(4).trim();
      }
      if (cleanCmd.isEmpty) return '';

      List<String> args;
      final isGlobalAdb = cleanCmd == 'devices' ||
          cleanCmd == 'version' ||
          cleanCmd.startsWith('kill-server') ||
          cleanCmd.startsWith('start-server') ||
          cleanCmd.startsWith('connect') ||
          cleanCmd.startsWith('disconnect');

      if (_connectedHost != null && !isGlobalAdb) {
        final target = '$_connectedHost:$_adbPort';
        if (cleanCmd.startsWith('shell ')) {
          args = ['-s', target, 'shell', cleanCmd.substring(6).trim()];
        } else {
          args = ['-s', target, ...cleanCmd.split(RegExp(r'\s+'))];
        }
      } else {
        args = cleanCmd.split(RegExp(r'\s+'));
      }

      final res = await Process.run(_adbPath!, args).timeout(const Duration(seconds: 10));
      final stdout = res.stdout?.toString().trim() ?? '';
      final stderr = res.stderr?.toString().trim() ?? '';
      final combined = [if (stdout.isNotEmpty) stdout, if (stderr.isNotEmpty) stderr].join('\n');
      final result = combined.isNotEmpty
          ? combined
          : '(Comando executado sem saída - exitCode: ${res.exitCode})';

      addLog(
        'adb ${args.join(' ')}',
        result,
        exitCode: res.exitCode,
        isError: res.exitCode != 0,
      );
      return result;
    } catch (e) {
      final err = 'Erro ao executar comando ADB: $e';
      addLog(command, err, exitCode: 1, isError: true);
      return err;
    }
  }

  /// Types text directly into the focused field on Android TV via ADB
  Future<bool> sendText(String text) async {
    if (_state != AdbState.connected || _connectedHost == null || _adbPath == null) {
      addLog('adb shell input text "$text"', 'Erro: ADB não conectado', exitCode: 1, isError: true);
      return false;
    }
    try {
      final target = '$_connectedHost:$_adbPort';
      // In Android adb input text, space is represented as %s and special chars must be escaped
      final escaped = text
          .replaceAll(' ', '%s')
          .replaceAll(r'\', r'\\')
          .replaceAll('"', r'\"')
          .replaceAll("'", r"\'")
          .replaceAll('&', r'\&')
          .replaceAll('(', r'\(')
          .replaceAll(')', r'\)')
          .replaceAll('<', r'\<')
          .replaceAll('>', r'\>')
          .replaceAll('|', r'\|')
          .replaceAll(';', r'\;')
          .replaceAll('\$', r'\$')
          .replaceAll('`', r'\`');
      final res = await Process.run(
        _adbPath!,
        ['-s', target, 'shell', 'input', 'text', escaped],
      ).timeout(const Duration(seconds: 4));
      final stdout = res.stdout?.toString().trim() ?? '';
      final stderr = res.stderr?.toString().trim() ?? '';
      final out = [if (stdout.isNotEmpty) stdout, if (stderr.isNotEmpty) stderr].join('\n');
      addLog(
        'adb shell input text "$text"',
        out.isEmpty ? 'Texto enviado com sucesso' : out,
        exitCode: res.exitCode,
        isError: res.exitCode != 0,
      );
      return res.exitCode == 0;
    } catch (e) {
      addLog('adb shell input text "$text"', 'Erro: $e', exitCode: 1, isError: true);
      return false;
    }
  }

  /// Sends a keyevent code directly via ADB (e.g. 66 for ENTER, 67 for DEL)
  Future<bool> sendKeyEvent(int keyCode) async {
    if (_state != AdbState.connected || _connectedHost == null || _adbPath == null) {
      addLog('adb shell input keyevent $keyCode', 'Erro: ADB não conectado', exitCode: 1, isError: true);
      return false;
    }
    try {
      final target = '$_connectedHost:$_adbPort';
      final res = await Process.run(
        _adbPath!,
        ['-s', target, 'shell', 'input', 'keyevent', keyCode.toString()],
      ).timeout(const Duration(seconds: 4));
      final stdout = res.stdout?.toString().trim() ?? '';
      final stderr = res.stderr?.toString().trim() ?? '';
      final out = [if (stdout.isNotEmpty) stdout, if (stderr.isNotEmpty) stderr].join('\n');
      addLog(
        'adb shell input keyevent $keyCode',
        out.isEmpty ? 'KeyCode $keyCode enviado' : out,
        exitCode: res.exitCode,
        isError: res.exitCode != 0,
      );
      return res.exitCode == 0;
    } catch (e) {
      addLog('adb shell input keyevent $keyCode', 'Erro: $e', exitCode: 1, isError: true);
      return false;
    }
  }

  void _startAppDetection() {
    _appDetectTimer?.cancel();
    _appDetectTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _checkForegroundApp();
    });
    _checkForegroundApp();
  }

  void _stopAppDetection() {
    _appDetectTimer?.cancel();
    _appDetectTimer = null;
    _currentAppPackage = null;
    _currentAppName = null;
    _isScreenOn = null;
  }

  /// Manually triggers a check for the active foreground app and screen wakefulness
  Future<void> checkForegroundApp() async => _checkForegroundApp();

  Future<void> _checkForegroundApp() async {
    if (_isCheckingApp || _adbPath == null || _connectedHost == null) {
      return;
    }
    // If we're disconnected or in error, attempt periodic reconnection
    if (_state != AdbState.connected) {
      if (_state == AdbState.error || _state == AdbState.idle) {
        _consecutiveCheckErrors++;
        if (_consecutiveCheckErrors >= 3) {
          _consecutiveCheckErrors = 0;
          unawaited(connectToTv(_connectedHost!, port: _adbPort));
        }
      }
      return;
    }

    _isCheckingApp = true;
    try {
      final target = '$_connectedHost:$_adbPort';
      final res = await Process.run(
        _adbPath!,
        ['-s', target, 'shell', 'dumpsys power | grep mWakefulness ; dumpsys window | grep -E "mCurrentFocus|mFocusedApp"'],
      ).timeout(const Duration(seconds: 4));

      final stdoutStr = res.stdout?.toString() ?? '';
      final stderrStr = res.stderr?.toString() ?? '';
      final combined = '$stdoutStr $stderrStr'.toLowerCase();

      if (res.exitCode == 0 && stdoutStr.isNotEmpty) {
        _consecutiveCheckErrors = 0;
        if (combined.contains('offline') ||
            combined.contains('not found') ||
            combined.contains('closed') ||
            combined.contains('device offline')) {
          _handleAdbDisconnect();
        } else {
          _parseForegroundApp(stdoutStr);
        }
      } else {
        if (combined.contains('offline') ||
            combined.contains('not found') ||
            combined.contains('closed') ||
            combined.contains('no devices')) {
          _handleAdbDisconnect();
        } else {
          _consecutiveCheckErrors++;
          if (_consecutiveCheckErrors >= 2) {
            _handleAdbDisconnect();
          }
        }
      }
    } catch (_) {
      _consecutiveCheckErrors++;
      if (_consecutiveCheckErrors >= 2) {
        _handleAdbDisconnect();
      }
    } finally {
      _isCheckingApp = false;
    }
  }

  void _handleAdbDisconnect() {
    _consecutiveCheckErrors = 0;
    if (_connectedHost != null && _state == AdbState.connected) {
      _state = AdbState.connecting;
      notifyListeners();
      unawaited(connectToTv(_connectedHost!, port: _adbPort));
    }
  }

  void _parseForegroundApp(String out) {
    // 1. Checar se a tela da TV está em modo de espera/dormindo (Standby)
    if (out.contains('mWakefulness=Asleep') || out.contains('mWakefulness=Dozing')) {
      final changed = _isScreenOn != false || _currentAppPackage != null || _currentAppName != null;
      _isScreenOn = false;
      _currentAppPackage = null;
      _currentAppName = null;
      if (changed) {
        notifyListeners();
        onAppInfoBroadcast?.call(null, null, false);
      }
      return;
    }

    // 2. Protetor de tela ativo (Daydream / Backdrop)
    if (out.contains('mWakefulness=Dreaming')) {
      final changed = _isScreenOn != true || _currentAppPackage != 'com.google.android.backdrop';
      _isScreenOn = true;
      _currentAppPackage = 'com.google.android.backdrop';
      _currentAppName = getScreenSaverTitle();
      if (changed) {
        notifyListeners();
        onAppInfoBroadcast?.call(_currentAppPackage, _currentAppName, true);
      }
      return;
    }

    if (out.contains('mWakefulness=Awake')) {
      final wasOff = _isScreenOn != true;
      _isScreenOn = true;
      if (wasOff) {
        notifyListeners();
        onAppInfoBroadcast?.call(_currentAppPackage, _currentAppName, true);
      }
    }

    // 3. Extrair aplicativo ativo da janela em foco
    final match = RegExp(r'([a-zA-Z0-9_\.]+(?:\.[a-zA-Z0-9_]+)+)\/([a-zA-Z0-9_\.]+)').firstMatch(out);
    if (match != null) {
      final pkg = match.group(1);
      if (pkg != null && pkg.isNotEmpty && (pkg != _currentAppPackage || _currentAppName == null)) {
        _currentAppPackage = pkg;
        _currentAppName = _resolveAppNameFromPackage(pkg);
        notifyListeners();
        onAppInfoBroadcast?.call(_currentAppPackage, _currentAppName, _isScreenOn ?? true);
      }
    }
  }

  String _resolveAppNameFromPackage(String pkg) {
    if (AppSettings.instance.showRawPackageName) return pkg;
    final lower = pkg.toLowerCase();
    if (lower.contains('google.android.backdrop') ||
        lower.contains('backdrop') ||
        lower.contains('screensaver')) {
      return getScreenSaverTitle();
    }
    if (lower.contains('projengmenu') || lower.contains('projectivy')) return 'Projectivy Launcher';
    if (lower.contains('sendfilestotv') || lower.contains('sendfiles') || lower.contains('send_files_to_tv')) return 'Send Files to TV';
    if (lower.contains('bitchord')) return 'BitChord';
    if (lower.contains('youcine')) return 'YouCine';
    if (lower.contains('isiclite') || lower.contains('intelbras')) return 'ISIC Lite';
    if (lower.contains('mediatek.wwtv') || lower.contains('wwtv')) return 'TV / HDMI / AV';
    if (lower.contains('tvlauncher') ||
        lower.contains('launcherx') ||
        lower.contains('nexuslauncher') ||
        lower.contains('katniss')) {
      return 'Tela Inicial';
    }
    if (lower.contains('vending')) return 'Google Play Store';
    if (lower.contains('wbd') || lower.contains('max') || lower.contains('hbo')) return 'Max';
    if (lower.contains('smarttube') || lower.contains('teamsmart') || lower.contains('liskovsoft')) return 'SmartTube';
    if (lower.contains('tizentube')) return 'TizenTube';
    if (lower.contains('youtube')) return 'YouTube';
    if (lower.contains('netflix')) return 'Netflix';
    if (lower.contains('amazonvideo') || lower.contains('primevideo') || lower.contains('amazon.avod')) return 'Prime Video';
    if (lower.contains('spotify')) return 'Spotify';
    if (lower.contains('disney')) return 'Disney+';
    if (lower.contains('globo')) return 'Globoplay';
    if (lower.contains('kodi')) return 'Kodi';
    if (lower.contains('twitch')) return 'Twitch';
    if (lower.contains('videolan.vlc') || lower == 'org.videolan.vlc') return 'VLC';
    if (lower.contains('stremio')) return 'Stremio';
    if (lower.contains('pluto')) return 'Pluto TV';
    if (lower.contains('crunchyroll')) return 'Crunchyroll';
    if (lower.contains('plex')) return 'Plex';
    if (lower.contains('apple') && (lower.contains('tv') || lower.contains('atv'))) return 'Apple TV';
    if (lower.contains('deezer')) return 'Deezer';
    if (lower.contains('tidal')) return 'Tidal';
    if (lower.contains('paramount')) return 'Paramount+';
    if (lower.contains('starplus')) return 'Star+';
    if (lower.contains('steamlink')) return 'Steam Link';
    if (lower.contains('tv.settings') || lower.contains('settings')) return 'Configurações';
    if (lower.contains('google.android.videos')) return 'Google TV';

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

  /// Disconnects ADB connection
  Future<void> disconnect() async {
    stopStreaming();
    _stopAppDetection();
    _stopAuthPolling();
    if (_adbPath != null && _connectedHost != null) {
      try {
        await Process.run(_adbPath!, ['disconnect', '$_connectedHost:$_adbPort']);
      } catch (_) {}
    }
    _state = AdbState.idle;
    _currentFrame = null;
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    stopStreaming();
    _stopAppDetection();
    _stopAuthPolling();
    super.dispose();
  }
}
