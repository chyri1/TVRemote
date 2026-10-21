import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../core/app_settings.dart';
import '../core/keycodes.dart';
import '../core/tv_controller.dart';
import 'mirror_window.dart';
import 'pairing_view.dart';
import 'remote_view.dart';
import 'theme.dart';

class FlyoutShell extends StatefulWidget {
  final TvController controller;

  const FlyoutShell({super.key, required this.controller});

  @override
  State<FlyoutShell> createState() => _FlyoutShellState();
}

class _FlyoutShellState extends State<FlyoutShell>
    with WindowListener, TrayListener, WidgetsBindingObserver {
  // Inicia sempre na tela de parear/selecionar controles ao iniciar o processo!
  bool _showPairing = true;
  String? _reconfigureHost;
  final FocusNode _focusNode = FocusNode();

  Timer? _keyRepeatTimer;
  Timer? _keyInitialDelayTimer;
  LogicalKeyboardKey? _heldKey;
  double _currentWindowHeight = 800.0;
  int _discoveredTvCount = 0;
  PairStep _currentPairStep = PairStep.selectHost;
  bool _isResizing = false;
  Timer? _debounceResizeTimer;

  bool _isDraggingManualResize = false;
  double? _dragFixedX;
  double? _dragBaseBottomY;
  double? _dragMaxAvailableHeight;
  double _dragAccumulatedHeight = 820.0;
  bool _isSettingBounds = false;
  double? _pendingSetBoundsHeight;

  bool get _isShowingPairing =>
      _showPairing || widget.controller.status == TvStatus.noTv;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentWindowHeight = _calculateDesiredHeight();
    windowManager.addListener(this);
    trayManager.addListener(this);
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
    widget.controller.addListener(_onStateChanged);
    AppSettings.instance.addListener(_onStateChanged);
    _initTray();
  }

  void _onStateChanged() {
    if (!mounted || _isDraggingManualResize) return;
    if (widget.controller.status == TvStatus.noTv) {
      _showPairing = true;
      _discoveredTvCount = 0;
      _currentPairStep = PairStep.selectHost;
    }
    _scheduleCheckAndUpdateWindowSize();
  }

  void _onDiscoveredCountChanged(int count) {
    if (_discoveredTvCount != count) {
      _discoveredTvCount = count;
      _scheduleCheckAndUpdateWindowSize();
    }
  }

  void _onStepChanged(PairStep step) {
    if (_currentPairStep != step) {
      _currentPairStep = step;
      _scheduleCheckAndUpdateWindowSize();
    }
  }

  void _scheduleCheckAndUpdateWindowSize() {
    _debounceResizeTimer?.cancel();
    _debounceResizeTimer = Timer(const Duration(milliseconds: 60), () {
      if (mounted) _checkAndUpdateWindowSize();
    });
  }

  double _calculateDesiredHeight() {
    // Se o usuário redimensionou manualmente nesta sessão, respeita a escolha do usuário
    final manualHeight = AppSettings.instance.manualWindowHeight;
    if (manualHeight != null) {
      return manualHeight;
    }

    if (_isShowingPairing) {
      if (_currentPairStep == PairStep.enterCode) {
        return 370.0;
      }
      if (_currentPairStep == PairStep.success) {
        return 280.0;
      }

      final int savedCount = widget.controller.tvs.length;
      final int discoveredCount = _discoveredTvCount;

      // Base: cabeçalho + busca + campos IP/Nome + botão conectar + créditos Chyri
      double height = 400.0;
      if (savedCount > 0) {
        height += 28.0 + (savedCount * 68.0);
      }
      if (discoveredCount > 0) {
        height += 24.0 + (discoveredCount * 58.0);
      }
      // Aumentado o tamanho máximo permitido conforme solicitado (expande até 960px sem forçar rolagens)
      return height.clamp(400.0, 960.0);
    }

    // Altura calculada para a tela do controle remoto
    // Sem espelhamento de tela: base compacta (~590px para topo + nav + dpad/pilares + mídia + apps + dicas)
    double height = 590.0;

    // Se o espelhamento de tela estiver ativo, soma o card de visualização 16:9 + abas de modo (~230px)
    if (AppSettings.instance.screenMirrorEnabled) {
      height += 230.0;
    }

    // Se o comando manual estiver ativado nas configurações, soma o campo (~70px)
    if (AppSettings.instance.manualCommandEnabled) {
      height += 70.0;
    }

    return height;
  }

  Future<void> _startManualResizeDrag() async {
    if (!Platform.isWindows) return;
    _isDraggingManualResize = true;
    _dragAccumulatedHeight = _currentWindowHeight;
    try {
      final primaryDisplay = await screenRetriever.getPrimaryDisplay();
      final visiblePos = primaryDisplay.visiblePosition ?? Offset.zero;
      final visibleSize = primaryDisplay.visibleSize ?? primaryDisplay.size;
      _dragFixedX = visiblePos.dx + visibleSize.width - 360 - 12;
      _dragBaseBottomY = visiblePos.dy + visibleSize.height - 12;
      _dragMaxAvailableHeight = visibleSize.height - 24;
    } catch (_) {}
  }

  void _updateManualResizeDrag(double dy) {
    if (!_isDraggingManualResize) return;
    final maxHeight = _dragMaxAvailableHeight ?? 960.0;
    _dragAccumulatedHeight = (_dragAccumulatedHeight - dy).clamp(280.0, maxHeight);
    _currentWindowHeight = _dragAccumulatedHeight;
    _pendingSetBoundsHeight = _dragAccumulatedHeight;
    _processManualResizeLoop();
  }

  Future<void> _processManualResizeLoop() async {
    if (_isSettingBounds) return;
    _isSettingBounds = true;
    while (_pendingSetBoundsHeight != null) {
      final target = _pendingSetBoundsHeight!;
      _pendingSetBoundsHeight = null;
      final x = _dragFixedX;
      final baseBottom = _dragBaseBottomY;
      if (x != null && baseBottom != null) {
        try {
          await windowManager.setBounds(
            Rect.fromLTWH(x, baseBottom - target, 360, target),
            animate: false,
          );
        } catch (_) {}
      }
    }
    _isSettingBounds = false;
  }

  Future<void> _endManualResizeDrag() async {
    _isDraggingManualResize = false;
    if (_pendingSetBoundsHeight != null) {
      await _processManualResizeLoop();
    }
    // Salva na sessão em AppSettings apenas ao soltar o mouse para evitar rebuild e flicker contínuo
    AppSettings.instance.setManualWindowHeight(_currentWindowHeight);
  }

  Future<void> _animateToWindowHeight(double targetHeight) async {
    if (!Platform.isWindows || _isResizing || _isDraggingManualResize) return;
    _isResizing = true;

    try {
      final primaryDisplay = await screenRetriever.getPrimaryDisplay();
      final visiblePos = primaryDisplay.visiblePosition ?? Offset.zero;
      final visibleSize = primaryDisplay.visibleSize ?? primaryDisplay.size;
      final double fixedX = visiblePos.dx + visibleSize.width - 360 - 12;
      final double baseBottomY = visiblePos.dy + visibleSize.height - 12;
      // Expande até o topo da tela conforme o conteúdo real necessário
      final double maxAvailableHeight = visibleSize.height - 24;

      final double clampedTarget = targetHeight.clamp(260.0, maxAvailableHeight);
      if ((clampedTarget - _currentWindowHeight).abs() < 2) return;

      _currentWindowHeight = clampedTarget;
      await windowManager.setBounds(
        Rect.fromLTWH(fixedX, baseBottomY - clampedTarget, 360, clampedTarget),
        animate: false,
      );
    } catch (e) {
      debugPrint('Error animating window height: $e');
    } finally {
      _isResizing = false;
    }
  }

  Future<void> _checkAndUpdateWindowSize() async {
    if (!Platform.isWindows || _isResizing || _isDraggingManualResize) return;
    try {
      final isVisible = await windowManager.isVisible();
      if (!isVisible) return;

      final desiredHeight = _calculateDesiredHeight();
      if ((desiredHeight - _currentWindowHeight).abs() > 4) {
        await _animateToWindowHeight(desiredHeight);
      }
    } catch (_) {}
  }

  Future<void> _positionAboveTray(Size windowSize) async {
    try {
      final primaryDisplay = await screenRetriever.getPrimaryDisplay();
      final visiblePos = primaryDisplay.visiblePosition ?? Offset.zero;
      final visibleSize = primaryDisplay.visibleSize ?? primaryDisplay.size;

      // Posiciona no canto inferior direito, a 12px da barra de tarefas
      final x = visiblePos.dx + visibleSize.width - windowSize.width - 12;
      final y = visiblePos.dy + visibleSize.height - windowSize.height - 12;

      await windowManager.setPosition(Offset(x, y));
    } catch (_) {
      await windowManager.setAlignment(Alignment.bottomRight);
    }
  }

  Future<void> _initTray() async {
    if (!Platform.isWindows) return;

    try {
      await trayManager.setIcon('assets/tray_icon.ico');
      await trayManager.setToolTip('TV Remote by Chyri');

      final menu = Menu(
        items: [
          MenuItem(key: 'open', label: 'Abrir controle'),
          MenuItem.separator(),
          MenuItem(key: 'exit', label: 'Encerrar'),
        ],
      );
      await trayManager.setContextMenu(menu);
    } catch (e) {
      debugPrint('Tray init error: $e');
    }
  }

  Future<void> _toggleFlyout() async {
    final isVisible = await windowManager.isVisible();
    if (isVisible) {
      await windowManager.hide();
    } else {
      _currentWindowHeight = _calculateDesiredHeight();
      final windowSize = Size(360, _currentWindowHeight);
      await windowManager.setSize(windowSize);
      await _positionAboveTray(windowSize);
      widget.controller.ensureConnected();
      await windowManager.show();
      await windowManager.focus();
      _focusNode.requestFocus();
    }
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    MirrorTracker.killAllMirrors();
    return AppExitResponse.exit;
  }

  Future<void> _exitApp() async {
    MirrorTracker.killAllMirrors();
    try {
      await trayManager.destroy();
      await windowManager.destroy();
    } catch (_) {}
    exit(0);
  }

  @override
  void onTrayIconMouseDown() {
    _toggleFlyout();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'open') {
      _toggleFlyout();
    } else if (menuItem.key == 'exit') {
      _exitApp();
    }
  }

  @override
  void onWindowBlur() {
    _cancelKeyRepeat();
    // Fecha automaticamente ao perder o foco (igual aos flyouts nativos do Windows 11)
    windowManager.hide();
  }

  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (_isShowingPairing) {
      _cancelKeyRepeat();
      return false;
    }

    // Se o usuário está interagindo com qualquer campo de texto no app (ex: dialog de Digitar na TV ou Renomear),
    // não intercepta para permitir navegação e digitação local.
    final primaryFocus = FocusManager.instance.primaryFocus;
    final isEditingText = primaryFocus != null &&
        (primaryFocus.context?.widget is EditableText ||
            primaryFocus.context?.findAncestorWidgetOfExactType<EditableText>() !=
                null ||
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

    // Teclas direcionais e de navegação contínua
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
        key == LogicalKeyboardKey.equal) {
      repeatableKeyCode = KeyCode.volumeUp;
    } else if (key == LogicalKeyboardKey.minus) {
      repeatableKeyCode = KeyCode.volumeDown;
    } else if (key == LogicalKeyboardKey.backspace) {
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
          key == LogicalKeyboardKey.numpadEnter) {
        c.sendKey(KeyCode.dpadCenter);
        return true;
      } else if (key == LogicalKeyboardKey.escape) {
        c.sendKey(KeyCode.back);
        return true;
      } else if (key == LogicalKeyboardKey.home) {
        c.sendKey(KeyCode.home);
        return true;
      } else if (event.character != null && event.character!.isNotEmpty) {
        // Digitação em tempo real do teclado do PC direto na TV
        c.sendText(event.character!);
        c.reportExternalCharacter(event.character!);
        return true;
      }
    }

    return false;
  }

  void _cancelKeyRepeat() {
    _heldKey = null;
    _keyInitialDelayTimer?.cancel();
    _keyInitialDelayTimer = null;
    _keyRepeatTimer?.cancel();
    _keyRepeatTimer = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounceResizeTimer?.cancel();
    widget.controller.removeListener(_onStateChanged);
    AppSettings.instance.removeListener(_onStateChanged);
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    _cancelKeyRepeat();
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final settings = AppSettings.instance;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          decoration: BoxDecoration(
            color: p.panelTint,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.stroke, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: p.dark ? 0.35 : 0.15),
                blurRadius: 24,
                spreadRadius: 2,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(
                child: ListenableBuilder(
                  listenable: widget.controller,
                  builder: (ctx, _) {
                    return AnimatedSwitcher(
                      duration: settings.animationDuration,
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      layoutBuilder: (currentChild, previousChildren) => Stack(
                        alignment: Alignment.topCenter,
                        children: [
                          ...previousChildren,
                          ?currentChild,
                        ],
                      ),
                      transitionBuilder: (child, animation) {
                        if (settings.animationDurationMs == 0) {
                          return child;
                        }
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0.0, 0.03),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: _isShowingPairing
                          ? KeyedSubtree(
                              key: const ValueKey('pairing_view'),
                              child: PairingView(
                                controller: widget.controller,
                                initialHost: _reconfigureHost ??
                                    widget.controller.selected?.host,
                                isReconfiguring: _reconfigureHost != null,
                                onDiscoveredCountChanged:
                                    _onDiscoveredCountChanged,
                                onStepChanged: _onStepChanged,
                                onDone: () => setState(() {
                                  _showPairing = false;
                                  _reconfigureHost = null;
                                  _scheduleCheckAndUpdateWindowSize();
                                }),
                              ),
                            )
                          : KeyedSubtree(
                              key: const ValueKey('remote_view'),
                              child: RemoteView(
                                controller: widget.controller,
                                onOpenPairing: () => setState(() {
                                  _showPairing = true;
                                  _discoveredTvCount = 0;
                                  _currentPairStep = PairStep.selectHost;
                                  _reconfigureHost = null;
                                  _scheduleCheckAndUpdateWindowSize();
                                }),
                                onOpenReconfigurePin: (host) => setState(() {
                                  _showPairing = true;
                                  _discoveredTvCount = 0;
                                  _currentPairStep = PairStep.enterCode;
                                  _reconfigureHost = host;
                                  _scheduleCheckAndUpdateWindowSize();
                                }),
                              ),
                            ),
                    );
                  },
                ),
              ),

              // Borda superior redimensionável manualmente puxando com o mouse
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 14,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeUpDown,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onVerticalDragStart: (_) => _startManualResizeDrag(),
                    onVerticalDragUpdate: (details) {
                      _updateManualResizeDrag(details.delta.dy);
                    },
                    onVerticalDragEnd: (_) => _endManualResizeDrag(),
                    onVerticalDragCancel: () => _endManualResizeDrag(),
                    child: Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 3),
                        width: 32,
                        height: 3.5,
                        decoration: BoxDecoration(
                          color: p.textDim.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
