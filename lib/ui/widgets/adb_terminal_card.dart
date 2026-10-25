import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/adb_service.dart';
import '../../core/tv_controller.dart';

/// Interactive ADB Terminal Widget that allows viewing live logs,
/// connection status, running custom commands, and quick command execution.
class AdbTerminalCard extends StatefulWidget {
  final TvController? controller;
  final VoidCallback? onClose;
  final bool isModal;

  const AdbTerminalCard({
    super.key,
    this.controller,
    this.onClose,
    this.isModal = false,
  });

  /// Opens the ADB terminal as a modal bottom sheet on mobile devices.
  static Future<void> showAsBottomSheet(BuildContext context, {TvController? controller}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0F1117),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // Drag Handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: AdbTerminalCard(
                  controller: controller,
                  onClose: () => Navigator.of(ctx).pop(),
                  isModal: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  State<AdbTerminalCard> createState() => _AdbTerminalCardState();
}

class _AdbTerminalCardState extends State<AdbTerminalCard> {
  final TextEditingController _cmdController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _cmdFocus = FocusNode();
  bool _isExecuting = false;
  int _lastLogCount = 0;

  @override
  void initState() {
    super.initState();
    _lastLogCount = AdbService.instance.logs.length;
    AdbService.instance.addListener(_onAdbChanged);
  }

  @override
  void dispose() {
    AdbService.instance.removeListener(_onAdbChanged);
    _cmdController.dispose();
    _scrollController.dispose();
    _cmdFocus.dispose();
    super.dispose();
  }

  void _onAdbChanged() {
    if (!mounted) return;
    final currentLogs = AdbService.instance.logs.length;
    if (currentLogs != _lastLogCount) {
      _lastLogCount = currentLogs;
      _scrollToBottom();
    }
    setState(() {});
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _executeCommand(String rawCmd) async {
    final cmd = rawCmd.trim();
    if (cmd.isEmpty || _isExecuting) return;

    _cmdController.clear();
    setState(() => _isExecuting = true);

    try {
      await AdbService.instance.runCommand(cmd);
      _scrollToBottom();
    } finally {
      if (mounted) {
        setState(() => _isExecuting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final adb = AdbService.instance;
    final tvHost = widget.controller?.selected?.host ?? adb.connectedHost ?? 'Dispositivo';

    final (statusColor, statusText) = switch (adb.state) {
      AdbState.connected => (const Color(0xFF107C41), 'Conectado'),
      AdbState.unauthorized => (Colors.amber, 'Aguardando autorização'),
      AdbState.connecting => (const Color(0xFF60CDFF), 'Conectando...'),
      AdbState.downloadingAdb => (const Color(0xFF60CDFF), 'Baixando ADB...'),
      AdbState.missingAdb => (Colors.orangeAccent, 'ADB não encontrado'),
      AdbState.error => (Colors.redAccent, 'Erro'),
      AdbState.idle || AdbState.checking => (Colors.white54, 'Ocioso'),
    };

    return Container(
      margin: widget.isModal ? EdgeInsets.zero : const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1117),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF282C38), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: widget.isModal ? MainAxisSize.max : MainAxisSize.min,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF161821),
              border: Border(
                bottom: BorderSide(color: Color(0xFF242733), width: 1),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.terminal_rounded, size: 16, color: Color(0xFF60CDFF)),
                const SizedBox(width: 6),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Terminal ADB - $tvHost:${adb.adbPort}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Status badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: statusColor.withValues(alpha: 0.4),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              statusText,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Reconnect Button
                Tooltip(
                  message: 'Reconectar ADB',
                  child: IconButton(
                    iconSize: 16,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.restart_alt_rounded, color: Colors.white70),
                    onPressed: () {
                      final host = widget.controller?.selected?.host ?? adb.connectedHost;
                      if (host != null) {
                        adb.reRequestConnection(host, adb.adbPort);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 2),
                // Copy Logs Button
                Tooltip(
                  message: 'Copiar histórico',
                  child: IconButton(
                    iconSize: 16,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.copy_rounded, color: Colors.white70),
                    onPressed: () {
                      if (adb.logs.isEmpty) return;
                      final text = adb.logs.map((l) {
                        final status = l.isError ? '[FALHA exit: ${l.exitCode}]' : '[SUCESSO]';
                        return '[${l.timeFormatted}] $status > ${l.command}\n${l.output}';
                      }).join('\n\n');
                      Clipboard.setData(ClipboardData(text: text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Logs copiados com sucesso!'),
                          duration: Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 2),
                // Clear Logs Button
                Tooltip(
                  message: 'Limpar logs',
                  child: IconButton(
                    iconSize: 16,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.white70),
                    onPressed: () => adb.clearLogs(),
                  ),
                ),
                if (widget.onClose != null) ...[
                  const SizedBox(width: 2),
                  // Close Button
                  Tooltip(
                    message: 'Fechar terminal',
                    child: IconButton(
                      iconSize: 16,
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      onPressed: widget.onClose,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Terminal Output Log Body
          SizedBox(
            height: widget.isModal ? null : 220,
            child: widget.isModal
                ? Expanded(child: _buildLogView(adb))
                : _buildLogView(adb),
          ),

          // Quick Commands Bar
          Container(
            color: const Color(0xFF12141C),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Text(
                    'Atalhos: ',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      fontFamily: 'Consolas',
                    ),
                  ),
                  _buildChip('devices', 'Listar conexões'),
                  _buildChip('shell input keyevent 66', 'OK / Enter'),
                  _buildChip('shell input keyevent 4', 'Voltar'),
                  _buildChip('shell input keyevent 3', 'Home'),
                  _buildChip('shell dumpsys power', 'Energia da TV'),
                  _buildChip('shell getprop ro.build.version.release', 'Versão Android'),
                  _buildChip('shell pm list packages -3', 'Apps instalados'),
                  _buildChip('disconnect', 'Desconectar'),
                ],
              ),
            ),
          ),

          // Command Input Field Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                    fontSize: 12,
                    fontFamily: 'Consolas',
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _cmdController,
                    focusNode: _cmdFocus,
                    scrollPadding: const EdgeInsets.only(bottom: 100),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontFamily: 'Consolas',
                    ),
                    cursorColor: const Color(0xFF60CDFF),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Digite comando ADB (ex: shell input keyevent 66)',
                      hintStyle: TextStyle(
                        color: Colors.white30,
                        fontSize: 10.5,
                        fontFamily: 'Consolas',
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 4),
                    ),
                    onSubmitted: _executeCommand,
                  ),
                ),
                if (_isExecuting)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF60CDFF),
                    ),
                  )
                else
                  IconButton(
                    iconSize: 16,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.send_rounded, color: Color(0xFF60CDFF)),
                    tooltip: 'Executar comando (Enter)',
                    onPressed: () => _executeCommand(_cmdController.text),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogView(AdbService adb) {
    if (adb.logs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.terminal_rounded, size: 28, color: Colors.white24),
              const SizedBox(height: 8),
              const Text(
                'Terminal ADB pronto.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontFamily: 'Consolas',
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Os comandos executados e saídas aparecerão aqui em tempo real.',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 10,
                  fontFamily: 'Consolas',
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFF090A0E),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: ListView.separated(
        controller: _scrollController,
        itemCount: adb.logs.length,
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (context, i) {
          final log = adb.logs[i];
          final isSuccess = !log.isError;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: log.isError
                  ? Colors.red.withValues(alpha: 0.08)
                  : Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: log.isError
                    ? Colors.redAccent.withValues(alpha: 0.25)
                    : Colors.white.withValues(alpha: 0.05),
                width: 0.8,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      '[${log.timeFormatted}] ',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 9.5,
                        fontFamily: 'Consolas',
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: (isSuccess ? const Color(0xFF107C41) : Colors.redAccent)
                            .withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        isSuccess ? 'OK' : 'ERRO (${log.exitCode})',
                        style: TextStyle(
                          color: isSuccess ? const Color(0xFF68E08F) : Colors.redAccent,
                          fontSize: 8.5,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Consolas',
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SelectableText(
                        '> ${log.command}',
                        style: const TextStyle(
                          color: Color(0xFF60CDFF),
                          fontSize: 10.5,
                          fontFamily: 'Consolas',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                if (log.output.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  SelectableText(
                    log.output,
                    style: TextStyle(
                      color: log.isError ? const Color(0xFFFF9494) : const Color(0xFFD4D7E2),
                      fontSize: 10,
                      fontFamily: 'Consolas',
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildChip(String cmd, String tooltip) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => _executeCommand(cmd),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1F2B),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white12, width: 0.8),
            ),
            child: Text(
              cmd,
              style: const TextStyle(
                color: Color(0xFF60CDFF),
                fontSize: 9.5,
                fontFamily: 'Consolas',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
