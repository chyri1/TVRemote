import 'dart:async';

import 'package:flutter/material.dart';

import '../core/adb_service.dart';
import '../core/app_settings.dart';
import '../core/keycodes.dart';
import '../core/tv_controller.dart';
import '../l10n/gen/app_localizations.dart';
import 'mirror_window.dart';
import 'theme.dart';
import 'widgets/app_grid.dart';
import 'widgets/dpad.dart';
import 'widgets/now_playing_card.dart';
import 'widgets/pad_button.dart';
import 'widgets/screen_mirror_card.dart';
import 'widgets/settings_dialog.dart';

class RemoteView extends StatefulWidget {
  final TvController controller;
  final VoidCallback? onOpenPairing;
  final void Function(String host)? onOpenReconfigurePin;
  final void Function(double height)? onHeightMeasured;
  final bool showScreenMirrorCard;

  const RemoteView({
    super.key,
    required this.controller,
    this.onOpenPairing,
    this.onOpenReconfigurePin,
    this.onHeightMeasured,
    this.showScreenMirrorCard = true,
  });

  @override
  State<RemoteView> createState() => _RemoteViewState();
}

class _RemoteViewState extends State<RemoteView> {
  final TextEditingController _manualCmdController = TextEditingController();
  final FocusNode _manualCmdFocus = FocusNode();

  bool _showKeyboardInput = false;
  bool _autoType = true;
  String _lastSentText = '';
  final TextEditingController _keyboardInputController = TextEditingController();
  final FocusNode _keyboardFocusNode = FocusNode();
  Timer? _keyboardDebounceTimer;

  StreamSubscription<String>? _extCharSub;
  StreamSubscription<void>? _extBackSub;

  @override
  void initState() {
    super.initState();
    _subscribeExternalKeystrokes();
  }

  void _subscribeExternalKeystrokes() {
    _extCharSub?.cancel();
    _extBackSub?.cancel();

    _extCharSub = widget.controller.onExternalKeystroke.listen((char) {
      if (!mounted) return;
      setState(() {
        _showKeyboardInput = true;
        _keyboardInputController.text += char;
        _keyboardInputController.selection = TextSelection.collapsed(
          offset: _keyboardInputController.text.length,
        );
        _lastSentText = _keyboardInputController.text;
      });
    });

    _extBackSub = widget.controller.onExternalBackspace.listen((_) {
      if (!mounted) return;
      final current = _keyboardInputController.text;
      if (current.isNotEmpty) {
        setState(() {
          _keyboardInputController.text =
              current.substring(0, current.length - 1);
          _keyboardInputController.selection = TextSelection.collapsed(
            offset: _keyboardInputController.text.length,
          );
          _lastSentText = _keyboardInputController.text;
        });
      }
    });
  }

  @override
  void didUpdateWidget(RemoteView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _subscribeExternalKeystrokes();
    }
  }

  @override
  void dispose() {
    _extCharSub?.cancel();
    _extBackSub?.cancel();
    _manualCmdController.dispose();
    _manualCmdFocus.dispose();
    _keyboardInputController.dispose();
    _keyboardFocusNode.dispose();
    _keyboardDebounceTimer?.cancel();
    super.dispose();
  }

  void _executeManualCommand(TvController c, String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return;

    // 1. Numeric keycode (ex: 3, 166, 24)
    final numericCode = int.tryParse(trimmed);
    if (numericCode != null) {
      c.sendKey(numericCode);
      _showCommandFeedback('Keycode $numericCode enviado para a TV');
      return;
    }

    // 2. Named keycode (ex: KEYCODE_CHANNEL_UP, GUIDE, MUTE)
    final namedCode = _resolveKeycodeName(trimmed);
    if (namedCode != null) {
      c.sendKey(namedCode);
      _showCommandFeedback('$trimmed (keycode $namedCode) enviado');
      return;
    }

    // 3. ADB shell / input commands
    if (trimmed.startsWith('adb ') || trimmed.startsWith('shell ') || trimmed.startsWith('input ')) {
      final adb = AdbService.instance;
      if (adb.state == AdbState.connected) {
        adb.runCommand(trimmed).then((out) {
          if (mounted) _showCommandFeedback(out.isNotEmpty ? out.trim() : 'Comando ADB executado');
        });
        return;
      }
    }

    // 4. App links / URLs
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://') || trimmed.contains('://') || trimmed.endsWith(':')) {
      c.launchApp(trimmed);
      _showCommandFeedback('Abrindo link: $trimmed');
      return;
    }

    // 5. Text fallback
    c.sendText(trimmed);
    _showCommandFeedback('Texto enviado: $trimmed');
  }

  int? _resolveKeycodeName(String name) {
    var clean = name.trim().toUpperCase();
    if (clean.startsWith('KEYCODE_')) {
      clean = clean.substring(8);
    }
    switch (clean) {
      case 'HOME': return KeyCode.home;
      case 'BACK': return KeyCode.back;
      case 'DPAD_UP': case 'UP': return KeyCode.dpadUp;
      case 'DPAD_DOWN': case 'DOWN': return KeyCode.dpadDown;
      case 'DPAD_LEFT': case 'LEFT': return KeyCode.dpadLeft;
      case 'DPAD_RIGHT': case 'RIGHT': return KeyCode.dpadRight;
      case 'DPAD_CENTER': case 'CENTER': case 'OK': case 'ENTER': case 'SELECT': return KeyCode.dpadCenter;
      case 'VOLUME_UP': case 'VOLUP': case 'VOL_UP': return KeyCode.volumeUp;
      case 'VOLUME_DOWN': case 'VOLDOWN': case 'VOL_DOWN': return KeyCode.volumeDown;
      case 'VOLUME_MUTE': case 'MUTE': return KeyCode.volumeMute;
      case 'POWER': return KeyCode.power;
      case 'MENU': return KeyCode.menu;
      case 'SEARCH': return KeyCode.search;
      case 'MEDIA_PLAY_PAUSE': case 'PLAY_PAUSE': case 'PLAY': case 'PAUSE': return KeyCode.mediaPlayPause;
      case 'MEDIA_NEXT': case 'NEXT': return KeyCode.mediaNext;
      case 'MEDIA_PREVIOUS': case 'PREV': case 'PREVIOUS': return KeyCode.mediaPrevious;
      case 'MEDIA_REWIND': case 'REWIND': return KeyCode.mediaRewind;
      case 'MEDIA_FAST_FORWARD': case 'FAST_FORWARD': case 'FORWARD': return KeyCode.mediaFastForward;
      case 'CHANNEL_UP': case 'CH_UP': case 'CHUP': return KeyCode.channelUp;
      case 'CHANNEL_DOWN': case 'CH_DOWN': case 'CHDOWN': return KeyCode.channelDown;
      case 'SETTINGS': return KeyCode.settings;
      case 'TV_INPUT': case 'INPUT': case 'SOURCE': return KeyCode.tvInput;
      case 'GUIDE': return 172;
      case 'INFO': return 165;
      case 'CAPTIONS': case 'SUBTITLE': return 175;
      case 'PROG_RED': case 'RED': return 183;
      case 'PROG_GREEN': case 'GREEN': return 184;
      case 'PROG_YELLOW': case 'YELLOW': return 185;
      case 'PROG_BLUE': case 'BLUE': return 186;
      case '0': return 7;
      case '1': return 8;
      case '2': return 9;
      case '3': return 10;
      case '4': return 11;
      case '5': return 12;
      case '6': return 13;
      case '7': return 14;
      case '8': return 15;
      case '9': return 16;
      default: return null;
    }
  }

  void _showCommandFeedback(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 12)),
        duration: const Duration(milliseconds: 1500),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    );
  }



  void _toggleKeyboardInput() {
    setState(() {
      _showKeyboardInput = !_showKeyboardInput;
      if (_showKeyboardInput) {
        final initial = widget.controller.imeStatus?.value ?? '';
        if (initial.isNotEmpty && _keyboardInputController.text.isEmpty) {
          _keyboardInputController.text = initial;
          _keyboardInputController.selection =
              TextSelection.collapsed(offset: initial.length);
        }
        _lastSentText = _keyboardInputController.text;
        _keyboardFocusNode.requestFocus();
      } else {
        _lastSentText = '';
        _keyboardFocusNode.unfocus();
        widget.controller.clearIme();
      }
    });
  }

  void _onKeyboardTextChanged(String currentText) {
    if (!_autoType) return;
    _keyboardDebounceTimer?.cancel();
    _keyboardDebounceTimer = Timer(const Duration(milliseconds: 120), () {
      _syncDeltaText(currentText);
    });
  }

  void _syncDeltaText(String currentText) {
    final prev = _lastSentText;
    if (currentText == prev) return;

    if (currentText.startsWith(prev)) {
      // Novos caracteres digitados no fim (envia apenas o delta)
      final added = currentText.substring(prev.length);
      widget.controller.sendText(added, submit: false);
    } else if (prev.startsWith(currentText)) {
      // Caracteres apagados com Backspace
      final deleteCount = prev.length - currentText.length;
      for (int i = 0; i < deleteCount; i++) {
        widget.controller.sendKey(KeyCode.del);
      }
    } else {
      // Texto substituído ou colado: apaga os anteriores e envia o novo
      for (int i = 0; i < prev.length; i++) {
        widget.controller.sendKey(KeyCode.del);
      }
      if (currentText.isNotEmpty) {
        widget.controller.sendText(currentText, submit: false);
      }
    }
    _lastSentText = currentText;
  }

  void _sendKeyboardManual(String text) {
    _keyboardDebounceTimer?.cancel();
    if (text.isEmpty) return;
    widget.controller.sendText(text, submit: false);
    _lastSentText = text;
  }

  void _clearKeyboardText() {
    _keyboardInputController.clear();
    _keyboardDebounceTimer?.cancel();
    if (_autoType && _lastSentText.isNotEmpty) {
      for (int i = 0; i < _lastSentText.length; i++) {
        widget.controller.sendKey(KeyCode.del);
      }
    }
    _lastSentText = '';
    setState(() {});
  }

  void _confirmDeleteTv(String id, String name) {
    final loc = AppLocalizations.of(context);
    final p = Palette.of(context);
    bool keepPairing = true;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: Text(loc.removeConfirm(name)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setDlgState(() => keepPairing = !keepPairing),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Checkbox(
                        value: keepPairing,
                        activeColor: p.accent,
                        onChanged: (v) =>
                            setDlgState(() => keepPairing = v ?? false),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          appTr(
                            pt: 'Manter PIN / pareamento salvo',
                            en: 'Keep PIN / pairing saved',
                            es: 'Mantener PIN / emparejamiento guardado',
                          ),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 44, right: 8),
                child: Text(
                  keepPairing
                      ? appTr(
                          pt: 'O dispositivo ficará desconectado, mas você poderá reconectar a qualquer momento sem digitar um novo PIN na tela.',
                          en: 'The device will be disconnected, but you can reconnect anytime without entering a new PIN on the screen.',
                          es: 'El dispositivo quedará desconectado, pero puedes reconectarlo en cualquier momento sin introducir un nuevo PIN en la pantalla.',
                        )
                      : appTr(
                          pt: 'O pareamento será esquecido completamente e exigirá um novo PIN na TV para conectar.',
                          en: 'The pairing will be completely forgotten and will require a new PIN on the TV to connect.',
                          es: 'El emparejamiento se olvidará por completo y requerirá un nuevo PIN en la TV para conectarse.',
                        ),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(loc.cancel),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                widget.controller.removeTv(id, keepPairing: keepPairing);
              },
              child: Text(loc.remove),
            ),
          ],
        ),
      ),
    );
  }

  void _renameTv(String id, String currentName) {
    final loc = AppLocalizations.of(context);
    final renameCtrl = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.rename),
        content: TextField(
          controller: renameCtrl,
          autofocus: true,
          decoration: InputDecoration(hintText: loc.tvNameHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(loc.cancel),
          ),
          FilledButton(
            onPressed: () {
              final val = renameCtrl.text.trim();
              if (val.isNotEmpty) {
                widget.controller.renameTv(id, val);
              }
              Navigator.pop(ctx);
            },
            child: Text(loc.save),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final p = Palette.of(context);
    final c = widget.controller;
    final tv = c.selected;

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            // Top Header: TV Selector & Power
            _buildHeader(loc, p, c),

            // Body
            if (c.status == TvStatus.noTv)
              _buildNoTvState(loc, p)
            else if (c.status == TvStatus.needsPairing)
              _buildNeedsPairingState(loc, p, tv?.host)
            else
              _buildControls(loc, p, c),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations loc, Palette p, TvController c) {
    final tv = c.selected;
    final (statusColor, statusText) = switch (c.status) {
      TvStatus.connected => (p.success, loc.statusConnected),
      TvStatus.connecting => (p.warning, loc.statusConnecting),
      TvStatus.needsPairing => (p.danger, loc.statusNeedsPairing),
      TvStatus.offline => (p.textDim, loc.statusOffline),
      TvStatus.noTv => (p.textDim, loc.statusNoTv),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.stroke, width: 1)),
      ),
      child: Row(
        children: [
          // TV Switcher & Status
          Expanded(
            child: PopupMenuButton<String>(
              tooltip: loc.myTvs,
              onSelected: (val) {
                if (val == '__add__') {
                  widget.onOpenPairing?.call();
                } else {
                  c.selectTv(val);
                }
              },
              itemBuilder: (ctx) => [
                ...c.tvs.map(
                  (t) => PopupMenuItem(
                    value: t.id,
                    child: Row(
                      children: [
                        Icon(
                          Icons.tv_rounded,
                          size: 18,
                          color: t.id == tv?.id ? p.accent : p.textDim,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            t.name,
                            style: TextStyle(
                              fontWeight: t.id == tv?.id
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (t.id == tv?.id)
                          Icon(Icons.check_rounded, size: 16, color: p.accent),
                      ],
                    ),
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: '__add__',
                  child: Row(
                    children: [
                      Icon(Icons.add_rounded, size: 18, color: p.accent),
                      const SizedBox(width: 8),
                      Text(loc.addTv),
                    ],
                  ),
                ),
              ],
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                tv?.name ?? loc.appTitle,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down_rounded, size: 20),
                          ],
                        ),
                        Text(
                          statusText,
                          style: TextStyle(fontSize: 11, color: p.textDim),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Edit/Delete current TV popup menu
          if (tv != null)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, size: 18, color: p.textDim),
              tooltip: 'Opções da TV',
              onSelected: (action) {
                if (action == 'rename') {
                  _renameTv(tv.id, tv.name);
                } else if (action == 'remove') {
                  _confirmDeleteTv(tv.id, tv.name);
                } else if (action == 'pair') {
                  widget.onOpenReconfigurePin != null
                      ? widget.onOpenReconfigurePin!(tv.host)
                      : widget.onOpenPairing?.call();
                } else if (action == 'settings') {
                  SettingsDialog.show(context);
                }
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'rename',
                  child: Row(
                    children: [
                      const Icon(Icons.edit_rounded, size: 16),
                      const SizedBox(width: 8),
                      Text(loc.rename),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'pair',
                  child: Row(
                    children: [
                      const Icon(Icons.lock_reset_rounded, size: 18),
                      const SizedBox(width: 8),
                      Text(loc.pairAgain),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'settings',
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 18),
                      const SizedBox(width: 8),
                      Text(appTr(
                        pt: 'Configurações e sobre',
                        en: 'Settings and about',
                        es: 'Configuración y acerca de',
                      )),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'remove',
                  child: Row(
                    children: [
                      Icon(Icons.link_off_rounded,
                          size: 18, color: p.danger),
                      const SizedBox(width: 8),
                      Text(loc.remove, style: TextStyle(color: p.danger)),
                    ],
                  ),
                ),
              ],
            ),

          const SizedBox(width: 4),

          // Power Button
          PadButton(
            size: 38,
            icon: Icons.power_settings_new_rounded,
            iconSize: 20,
            tooltip: loc.power,
            foreground: p.danger,
            onPressed: () => c.sendKey(KeyCode.power),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(AppLocalizations loc, Palette p, TvController c) {
    final isPlaying = c.nowPlaying?.isPlaying ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
            // Active TV Keyboard Banner (Google Home style)
            if (c.hasActiveIme) ...[
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _toggleKeyboardInput,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: p.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: p.accent.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.keyboard_rounded, size: 20, color: p.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          c.imeStatus?.label != null && c.imeStatus!.label!.isNotEmpty
                              ? 'Teclado na TV: ${c.imeStatus!.label}'
                              : 'Teclado ativo na TV',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: p.accent,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, size: 18, color: p.accent),
                    ],
                  ),
                ),
              ),
            ],

            // Navigation Row: Back, Home, TV_INPUT, Menu
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                PadButton(
                  size: 42,
                  icon: Icons.arrow_back_rounded,
                  tooltip: '${loc.back} (Esc)',
                  onPressed: () => c.sendKey(KeyCode.back),
                ),
                PadButton(
                  size: 42,
                  icon: Icons.home_rounded,
                  tooltip: loc.home,
                  onPressed: () => c.sendKey(KeyCode.home),
                ),
                PadButton(
                  size: 42,
                  icon: Icons.input_rounded,
                  tooltip: appTr(
                    pt: 'Entrada / Source (TV_INPUT)',
                    en: 'Input / Source (TV_INPUT)',
                    es: 'Entrada / Fuente (TV_INPUT)',
                  ),
                  onPressed: () => c.sendKey(KeyCode.tvInput),
                ),
                PadButton(
                  size: 42,
                  icon: Icons.menu_rounded,
                  tooltip: loc.menu,
                  onPressed: () => c.sendKey(KeyCode.menu),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // D-Pad flanked by Channel Pillar + EPG (Left) and Volume Pillar + EXIT (Right)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildChannelPillar(p, c),
                    const SizedBox(height: 8),
                    _buildEpgButton(p, c),
                  ],
                ),
                DPad(controller: c, size: 176),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildVolumePillar(p, c),
                    const SizedBox(height: 8),
                    _buildExitButton(p, c),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Espelhamento de tela (Screen Mirror) se ativado e permitido
            if (widget.showScreenMirrorCard)
              ListenableBuilder(
                listenable: AppSettings.instance,
                builder: (ctx, _) {
                  if (!AppSettings.instance.screenMirrorEnabled) {
                    return const SizedBox.shrink();
                  }
                  return ScreenMirrorCard(
                    controller: c,
                    onOpenPopout: () => openScreenMirrorPopout(context, c),
                  );
                },
              ),

            // Now Playing Banner (Title, Artist, Artwork in 16:9 & App)
            NowPlayingCard(controller: c),

            // Media Controls & Extra buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                PadButton(
                  size: 38,
                  icon: Icons.fast_rewind_rounded,
                  iconSize: 18,
                  tooltip: loc.rewind,
                  onPressed: () => c.sendKey(KeyCode.mediaRewind),
                ),
                PadButton(
                  size: 42,
                  icon: isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  iconSize: 24,
                  tooltip: isPlaying
                      ? appTr(pt: 'Pausar', en: 'Pause', es: 'Pausar')
                      : loc.playPause,
                  onPressed: () => c.sendKey(KeyCode.mediaPlayPause),
                ),
                PadButton(
                  size: 38,
                  icon: Icons.fast_forward_rounded,
                  iconSize: 18,
                  tooltip: loc.fastForward,
                  onPressed: () => c.sendKey(KeyCode.mediaFastForward),
                ),
                PadButton(
                  size: 38,
                  icon: Icons.keyboard_rounded,
                  iconSize: 18,
                  foreground: _showKeyboardInput ? p.accent : null,
                  background: _showKeyboardInput ? p.accent.withValues(alpha: 0.2) : null,
                  tooltip: _showKeyboardInput
                      ? appTr(pt: 'Fechar teclado', en: 'Close keyboard', es: 'Cerrar teclado')
                      : appTr(
                          pt: 'Digitar texto',
                          en: 'Type text',
                          es: 'Escribir texto',
                        ),
                  onPressed: _toggleKeyboardInput,
                ),
                PadButton(
                  size: 38,
                  icon: Icons.mic_rounded,
                  iconSize: 20,
                  tooltip: appTr(
                    pt: 'Google Assistente / Assistente de voz',
                    en: 'Google Assistant / Voice assistant',
                    es: 'Asistente de Google / Asistente de voz',
                  ),
                  foreground: const Color(0xFF4285F4),
                  onPressed: () => c.sendKey(KeyCode.assist),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Teclado Inline (Google Home style, sem pop-up)
            if (_showKeyboardInput) ...[
              _buildInlineKeyboard(context, c, p, loc),
              const SizedBox(height: 14),
            ],

            // Caixa de Comando Manual (se ativado nas configurações)
            ListenableBuilder(
              listenable: AppSettings.instance,
              builder: (ctx, _) {
                if (!AppSettings.instance.manualCommandEnabled) {
                  return const SizedBox.shrink();
                }
                return _buildManualCommandCard(context, c, p, loc);
              },
            ),

            // App Shortcuts
            Text(
              loc.apps,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: p.textDim,
              ),
            ),
            const SizedBox(height: 8),
            AppGrid(controller: c),
            const SizedBox(height: 14),

            // Keyboard navigation tip
            Text(
              loc.keyboardHint,
              style: TextStyle(fontSize: 11, color: p.textDim),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
          ],
        ),
      );
    }

  Widget _buildChannelPillar(Palette p, TvController c) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 3),
      decoration: BoxDecoration(
        color: p.fill,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: p.stroke, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: p.dark ? 0.2 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PadButton(
            size: 38,
            icon: Icons.add_rounded,
            iconSize: 20,
            repeat: true,
            tooltip: appTr(pt: 'Canal + (CH+)', en: 'Channel + (CH+)', es: 'Canal + (CH+)'),
            onPressed: () => c.sendKey(KeyCode.channelUp),
          ),
          const SizedBox(height: 4),
          PadButton(
            size: 38,
            tooltip: appTr(pt: 'Informações (Info)', en: 'Information (Info)', es: 'Información (Info)'),
            onPressed: () => c.sendKey(KeyCode.info),
            child: Text(
              'INFO',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: p.textDim,
              ),
            ),
          ),
          const SizedBox(height: 4),
          PadButton(
            size: 38,
            icon: Icons.remove_rounded,
            iconSize: 20,
            repeat: true,
            tooltip: appTr(pt: 'Canal - (CH-)', en: 'Channel - (CH-)', es: 'Canal - (CH-)'),
            onPressed: () => c.sendKey(KeyCode.channelDown),
          ),
        ],
      ),
    );
  }

  Widget _buildVolumePillar(Palette p, TvController c) {
    final vol = c.volume;
    final isMuted = vol?.muted ?? false;
    final volPercent = vol != null && vol.max > 0
        ? '${((vol.level / vol.max) * 100).round()}%'
        : '';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 3),
      decoration: BoxDecoration(
        color: p.fill,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: p.stroke, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: p.dark ? 0.2 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PadButton(
            size: 38,
            icon: Icons.add_rounded,
            iconSize: 20,
            repeat: true,
            tooltip: appTr(pt: 'Volume + (VOL+)', en: 'Volume + (VOL+)', es: 'Volumen + (VOL+)'),
            onPressed: () => _changeVolume(c, KeyCode.volumeUp),
          ),
          const SizedBox(height: 4),
          PadButton(
            size: 38,
            tooltip: isMuted
                ? appTr(pt: 'Desativar Mudo', en: 'Unmute', es: 'Reactivar sonido')
                : (volPercent.isNotEmpty
                    ? '${appTr(pt: 'Mudo', en: 'Mute', es: 'Silenciar')} ($volPercent)'
                    : appTr(pt: 'Mudo', en: 'Mute', es: 'Silenciar')),
            onPressed: () => c.sendKey(KeyCode.volumeMute),
            child: isMuted
                ? Icon(Icons.volume_off_rounded, size: 19, color: p.danger)
                : Text(
                    appTr(pt: 'MUDO', en: 'MUTE', es: 'MUDO'),
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                      color: p.textDim,
                    ),
                  ),
          ),
          const SizedBox(height: 4),
          PadButton(
            size: 38,
            icon: Icons.remove_rounded,
            iconSize: 20,
            repeat: true,
            tooltip: appTr(pt: 'Volume - (VOL-)', en: 'Volume - (VOL-)', es: 'Volumen - (VOL-)'),
            onPressed: () => _changeVolume(c, KeyCode.volumeDown),
          ),
        ],
      ),
    );
  }

  void _changeVolume(TvController c, int keyCode) {
    final step = AppSettings.instance.volumeStep;
    for (int i = 0; i < step; i++) {
      c.sendKey(keyCode);
    }
  }

  Widget _buildEpgButton(Palette p, TvController c) {
    return PadButton(
      size: 36,
      width: 44,
      radius: BorderRadius.circular(10),
      tooltip: appTr(
        pt: 'Guia de Programação (EPG / Guide)',
        en: 'Program Guide (EPG / Guide)',
        es: 'Guía de programación (EPG / Guide)',
      ),
      onPressed: () => c.sendKey(KeyCode.guide),
      child: Text(
        'EPG',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
          color: p.text,
        ),
      ),
    );
  }

  Widget _buildExitButton(Palette p, TvController c) {
    return PadButton(
      size: 36,
      width: 44,
      radius: BorderRadius.circular(10),
      tooltip: appTr(
        pt: 'Sair (Exit / Voltar)',
        en: 'Exit / Back',
        es: 'Salir / Volver',
      ),
      onPressed: () => c.sendKey(KeyCode.back),
      child: Text(
        'EXIT',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
          color: p.danger.withValues(alpha: 0.95),
        ),
      ),
    );
  }

  Widget _buildManualCommandCard(
    BuildContext context,
    TvController c,
    Palette p,
    AppLocalizations loc,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: p.fill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.stroke, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.terminal_rounded, size: 14, color: p.accent),
              const SizedBox(width: 6),
              Text(
                appTr(
                  pt: 'Comando manual para a TV',
                  en: 'Manual command to TV',
                  es: 'Comando manual a la TV',
                ),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: p.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: TextField(
              controller: _manualCmdController,
              focusNode: _manualCmdFocus,
              textAlignVertical: TextAlignVertical.center,
              style: TextStyle(fontSize: 12.5, color: p.text),
              decoration: InputDecoration(
                hintText: appTr(
                  pt: 'Keycode (ex: 166, GUIDE, 3) ou texto...',
                  en: 'Keycode (e.g. 166, GUIDE, 3) or text...',
                  es: 'Keycode (ej: 166, GUIDE, 3) o texto...',
                ),
                hintStyle: TextStyle(fontSize: 11, color: p.textDim),
                isDense: true,
                contentPadding:
                    const EdgeInsets.only(left: 12, right: 6, top: 8, bottom: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: p.stroke),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: p.stroke),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: p.accent),
                ),
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: Tooltip(
                    message: appTr(
                      pt: 'Enviar comando',
                      en: 'Send command',
                      es: 'Enviar comando',
                    ),
                    child: Material(
                      color: p.accent,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () =>
                            _executeManualCommand(c, _manualCmdController.text),
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 2),
                              child: Icon(
                                Icons.send_rounded,
                                size: 14,
                                color: p.onAccent,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
              ),
              onSubmitted: (txt) => _executeManualCommand(c, txt),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoTvState(AppLocalizations loc, Palette p) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tv_off_rounded, size: 54, color: p.textDim),
            const SizedBox(height: 14),
            Text(
              loc.statusNoTv,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              loc.noTvBody,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: p.textDim),
            ),
            const SizedBox(height: 20),
            AccentButton(
              label: loc.addTv,
              onPressed: widget.onOpenPairing,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNeedsPairingState(
      AppLocalizations loc, Palette p, String? host) {
    final tv = widget.controller.selected;
    final targetHost = host ?? tv?.host ?? '';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline_rounded, size: 54, color: p.warning),
            const SizedBox(height: 14),
            Text(
              loc.statusNeedsPairing,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              loc.needsPairingBody,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: p.textDim),
            ),
            const SizedBox(height: 20),
            AccentButton(
              label: loc.pairAgain,
              onPressed: () => widget.onOpenReconfigurePin != null
                  ? widget.onOpenReconfigurePin!(targetHost)
                  : widget.onOpenPairing?.call(),
            ),
            if (tv != null) ...[
              const SizedBox(height: 10),
              SubtleButton(
                label: loc.remove,
                icon: Icons.link_off_rounded,
                onPressed: () => _confirmDeleteTv(tv.id, tv.name),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInlineKeyboard(
    BuildContext context,
    TvController c,
    Palette p,
    AppLocalizations loc,
  ) {
    final imeLabel = c.imeStatus?.label;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: p.fill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.stroke, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.keyboard_rounded, size: 14, color: p.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  imeLabel != null && imeLabel.isNotEmpty
                      ? 'Digitar na TV ($imeLabel)'
                      : 'Teclado na TV',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: p.text,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                iconSize: 16,
                padding: const EdgeInsets.all(2),
                constraints: const BoxConstraints(),
                icon: Icon(Icons.close_rounded, color: p.textDim),
                tooltip: 'Fechar teclado',
                onPressed: _toggleKeyboardInput,
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _keyboardInputController,
            focusNode: _keyboardFocusNode,
            autofocus: true,
            style: TextStyle(color: p.text, fontSize: 12.5),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Digite o texto a ser enviado...',
              hintStyle: TextStyle(color: p.textDim, fontSize: 11),
              filled: true,
              fillColor: p.panelTint,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: p.stroke),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: p.stroke),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: p.accent),
              ),
              suffixIcon: _keyboardInputController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 16),
                      onPressed: _clearKeyboardText,
                    )
                  : null,
            ),
            onChanged: (val) {
              setState(() {});
              _onKeyboardTextChanged(val);
            },
            onSubmitted: (txt) => _sendKeyboardManual(txt),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () {
                  setState(() {
                    _autoType = !_autoType;
                    _lastSentText = _keyboardInputController.text;
                  });
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 20,
                      width: 32,
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: Switch(
                          value: _autoType,
                          activeThumbColor: p.accent,
                          onChanged: (val) {
                            setState(() {
                              _autoType = val;
                              _lastSentText = _keyboardInputController.text;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Digitar automaticamente',
                      style: TextStyle(
                        fontSize: 11,
                        color: _autoType ? p.text : p.textDim,
                        fontWeight:
                            _autoType ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(right: 5),
                child: Tooltip(
                  message: appTr(
                    pt: 'Enviar texto',
                    en: 'Send text',
                    es: 'Enviar texto',
                  ),
                  child: Material(
                    color: p.accent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () =>
                          _sendKeyboardManual(_keyboardInputController.text),
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 2),
                            child: Icon(
                              Icons.send_rounded,
                              size: 14,
                              color: p.onAccent,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
