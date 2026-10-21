import 'dart:async';

import 'package:flutter/material.dart';

import '../core/discovery.dart';
import '../core/pairing_client.dart';
import '../core/tv_controller.dart';
import '../core/tv_store.dart';
import '../l10n/gen/app_localizations.dart';
import 'theme.dart';
import 'widgets/chyri_credits.dart';
import 'widgets/pad_button.dart';
import 'widgets/settings_dialog.dart';

class PairingView extends StatefulWidget {
  final TvController controller;
  final VoidCallback onDone;
  final String? initialHost;
  final bool isReconfiguring;
  final void Function(int count)? onDiscoveredCountChanged;
  final void Function(PairStep step)? onStepChanged;
  final void Function(double height)? onHeightMeasured;

  const PairingView({
    super.key,
    required this.controller,
    required this.onDone,
    this.initialHost,
    this.isReconfiguring = false,
    this.onDiscoveredCountChanged,
    this.onStepChanged,
    this.onHeightMeasured,
  });

  @override
  State<PairingView> createState() => _PairingViewState();
}

enum PairStep { selectHost, enterCode, success }

class _PairingViewState extends State<PairingView> {
  PairStep _step = PairStep.selectHost;

  void _setStep(PairStep newStep) {
    if (_step != newStep) {
      setState(() {
        _step = newStep;
      });
      widget.onStepChanged?.call(newStep);
    }
  }

  final _ipController = TextEditingController();
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();

  final _discovered = <DiscoveredTv>[];
  StreamSubscription<DiscoveredTv>? _scanSub;
  bool _scanning = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    if (widget.initialHost != null) {
      _ipController.text = widget.initialHost!;
    }
    if (widget.isReconfiguring && widget.initialHost != null) {
      // Reconfiguração explícita solicitada pelo usuário
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _requestPairing(widget.initialHost!, widget.controller.selected?.name);
      });
    } else {
      _startScan();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onStepChanged?.call(_step);
    });
  }

  @override
  void didUpdateWidget(covariant PairingView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller.tvs.length != oldWidget.controller.tvs.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onDiscoveredCountChanged?.call(_discovered.length);
      });
    }
  }

  void _startScan() {
    _scanSub?.cancel();
    setState(() {
      _scanning = true;
      _discovered.clear();
    });
    widget.onDiscoveredCountChanged?.call(0);
    _scanSub = TvDiscovery().scan().listen(
      (tv) {
        if (!mounted) return;
        setState(() {
          final idx = _discovered.indexWhere((d) => d.host == tv.host);
          if (idx >= 0) {
            _discovered[idx] = tv;
          } else {
            _discovered.add(tv);
          }
          widget.onDiscoveredCountChanged?.call(_discovered.length);
        });
      },
      onDone: () {
        if (mounted) {
          setState(() => _scanning = false);
          widget.onDiscoveredCountChanged?.call(_discovered.length);
        }
      },
    );
  }

  void _showToastAlreadyConfigured(String name, String host) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF60CDFF),
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'A TV "$name" ($host) já está configurada! Abrindo controle...',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1E1E24),
        duration: const Duration(seconds: 3),
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0x40FFFFFF), width: 1),
        ),
      ),
    );
  }

  Future<void> _requestPairing(String host, String? suggestedName) async {
    final cleanHost = host.trim();
    if (cleanHost.isEmpty) return;

    // Se o dispositivo já estiver configurado e o usuário NÃO clicou explicitamente em "Reconfigurar PIN":
    final existing =
        widget.controller.tvs.where((t) => t.host == cleanHost).firstOrNull;
    if (existing != null && !widget.isReconfiguring) {
      _showToastAlreadyConfigured(existing.name, existing.host);
      widget.controller.selectTv(existing.id);
      widget.onDone();
      return;
    }

    // Se tiver pareamento salvo previamente com PIN válido e não for reconfiguração explícita:
    final saved = widget.controller.savedPairings
        .where((sp) => sp.host == cleanHost)
        .firstOrNull;
    if (saved != null && !widget.isReconfiguring) {
      await widget.controller.reconnectSavedTv(saved);
      widget.onDone();
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await widget.controller.startPairing(cleanHost);
      if (!mounted) return;
      if (suggestedName != null && _nameController.text.isEmpty) {
        _nameController.text = suggestedName;
      }
      _ipController.text = cleanHost;
      _busy = false;
      _setStep(PairStep.enterCode);
    } catch (e) {
      if (!mounted) return;
      final loc = AppLocalizations.of(context);
      setState(() {
        _busy = false;
        _error = loc.tvUnreachable;
      });
    }
  }

  Future<void> _submitCode() async {
    final loc = AppLocalizations.of(context);
    final code = _codeController.text.trim().toUpperCase();
    if (code.length != 6) {
      setState(() => _error = loc.invalidCode);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await widget.controller.finishPairing(
        _ipController.text.trim(),
        _nameController.text.trim(),
        code,
      );
      if (!mounted) return;
      _busy = false;
      _setStep(PairStep.success);
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) widget.onDone();
    } on PairingException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.code == 'wrong_code' ? loc.wrongCode : loc.pairingFailed;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = loc.pairingFailed;
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _scanSub?.cancel();
    _ipController.dispose();
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final p = Palette.of(context);

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header with optional back button (only when entering PIN code) & settings button
            Row(
              children: [
                if (_step == PairStep.enterCode) ...[
                  PadButton(
                    size: 32,
                    icon: Icons.arrow_back_rounded,
                    iconSize: 18,
                    tooltip: loc.cancel,
                    onPressed: () {
                      widget.controller.cancelPairing();
                      _error = null;
                      _setStep(PairStep.selectHost);
                    },
                  ),
                  const SizedBox(width: 10),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.tv_rounded, size: 18, color: p.accent),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    _step == PairStep.enterCode
                        ? loc.enterCodeTitle
                        : (widget.controller.tvs.isNotEmpty
                            ? 'TV Remote'
                            : loc.pairTitle),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: p.text,
                    ),
                  ),
                ),
                PadButton(
                  size: 32,
                  icon: Icons.info_outline_rounded,
                  iconSize: 18,
                  tooltip: 'Configurações e sobre',
                  onPressed: () => SettingsDialog.show(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: p.danger.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: p.danger.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded, color: p.danger, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(color: p.danger, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            _step == PairStep.enterCode
                ? _buildEnterCodeStep(loc, p)
                : _step == PairStep.success
                    ? _buildSuccessStep(loc, p)
                    : _buildSelectHostStep(loc, p),

            const SizedBox(height: 14),
            const ChyriCredits(),
          ],
        ),
      ),
    ),
  );
}

  void _showRenameDialog(TvDevice tv) {
    final ctrl = TextEditingController(text: tv.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).rename),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: AppLocalizations.of(context).tvNameHint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          FilledButton(
            onPressed: () {
              final val = ctrl.text.trim();
              if (val.isNotEmpty) {
                widget.controller.renameTv(tv.id, val);
              }
              Navigator.pop(ctx);
            },
            child: Text(AppLocalizations.of(context).save),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(TvDevice tv) {
    bool keepPairing = true;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(AppLocalizations.of(context).removeConfirm(tv.name)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Deseja remover este dispositivo?',
                style: TextStyle(
                  fontSize: 13,
                  color: Palette.of(context).textDim,
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () {
                  setDialogState(() {
                    keepPairing = !keepPairing;
                  });
                },
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: keepPairing,
                          onChanged: (v) {
                            setDialogState(() {
                              keepPairing = v ?? false;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Manter PIN / pareamento salvo',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Palette.of(context).text,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                keepPairing
                    ? 'O aparelho será apenas desconectado. Você poderá reconectar quando quiser sem digitar o PIN novamente.'
                    : 'O pareamento será esquecido completamente. Será necessário digitar um novo PIN na próxima conexão.',
                style: TextStyle(
                  fontSize: 11,
                  color: Palette.of(context).textDim,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(context).cancel),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                widget.controller.removeTv(tv.id, keepPairing: keepPairing);
              },
              child: Text(AppLocalizations.of(context).remove),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSavedTvsSection(AppLocalizations loc, Palette p) {
    final tvs = widget.controller.tvs;
    final disconnectedSaved = widget.controller.savedPairings
        .where((sp) => !tvs.any((t) => t.id == sp.id || t.host == sp.host))
        .toList();

    if (tvs.isEmpty && disconnectedSaved.isEmpty) return const SizedBox.shrink();

    final activeLang = Localizations.localeOf(context).languageCode;
    String tr(String pt, String en, String es) {
      if (activeLang == 'en') return en;
      if (activeLang == 'es') return es;
      return pt;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tvs.isNotEmpty) ...[
          Row(
            children: [
              Icon(Icons.devices_rounded, size: 16, color: p.accent),
              const SizedBox(width: 6),
              Text(
                tr('CONTROLES SALVOS', 'SAVED REMOTES', 'CONTROLES GUARDADOS'),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: p.textDim,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${tvs.length}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: p.accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...tvs.map((tv) => _buildSavedTvCard(tv, p, loc, tr)),
        ],
        if (disconnectedSaved.isNotEmpty) ...[
          if (tvs.isNotEmpty) const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.bookmark_added_rounded, size: 15, color: p.accent),
              const SizedBox(width: 6),
              Text(
                tr('DISPOSITIVOS COM PIN SALVO', 'DEVICES WITH SAVED PIN', 'DISPOSITIVOS CON PIN GUARDADO'),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: p.textDim,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${disconnectedSaved.length}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: p.accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...disconnectedSaved.map((tv) => _buildDisconnectedTvCard(tv, p, tr)),
        ],
        const SizedBox(height: 12),
        Divider(height: 1, color: p.stroke),
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _buildDisconnectedTvCard(
    TvDevice tv,
    Palette p,
    String Function(String, String, String) tr,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: p.fill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.stroke, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: p.textDim.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.tv_off_rounded, size: 20, color: p.textDim),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          tv.name,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            color: p.text,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: p.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          tr('PIN Salvo', 'PIN Saved', 'PIN Guardado'),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: p.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${tv.host} • ${tr("Desconectado", "Disconnected", "Desconectado")}',
                    style: TextStyle(fontSize: 11, color: p.textDim),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () async {
                await widget.controller.reconnectSavedTv(tv);
                if (mounted) widget.onDone();
              },
              icon: const Icon(Icons.sync_rounded, size: 16),
              label: Text(
                tr('Reconectar', 'Reconnect', 'Reconectar'),
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(Icons.delete_outline_rounded, size: 18, color: p.danger),
              tooltip: tr('Remover PIN salvo', 'Remove saved PIN', 'Eliminar PIN'),
              visualDensity: VisualDensity.compact,
              onPressed: () {
                widget.controller.removeSavedPairing(tv.id);
                setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSavedTvCard(
    TvDevice tv,
    Palette p,
    AppLocalizations loc,
    String Function(String, String, String) tr,
  ) {
    final isSelected = widget.controller.selected?.id == tv.id;
    final status = widget.controller.status;

    // Conexão e status
    final (statusColor, statusLabel) = switch (status) {
      TvStatus.connected when isSelected => (
          p.success,
          tr('Conectado', 'Connected', 'Conectado'),
        ),
      TvStatus.connecting when isSelected => (
          p.warning,
          tr('Conectando...', 'Connecting...', 'Conectando...'),
        ),
      TvStatus.needsPairing when isSelected => (
          p.danger,
          tr('PIN necessário', 'Needs PIN', 'PIN requerido'),
        ),
      _ => (
          p.textDim,
          isSelected
              ? tr('Pronto para uso', 'Ready', 'Listo')
              : tr('Salvo', 'Saved', 'Guardado'),
        ),
    };

    // Detalhes: Fabricante, Modelo, IP
    final detailsList = <String>[];
    if (tv.manufacturer != null && tv.manufacturer!.isNotEmpty) {
      detailsList.add(tv.manufacturer!);
    }
    if (tv.model != null &&
        tv.model!.isNotEmpty &&
        tv.model != tv.manufacturer &&
        !tv.name.toLowerCase().contains(tv.model!.toLowerCase())) {
      detailsList.add(tv.model!);
    }
    detailsList.add(tv.host);
    final detailsStr = detailsList.join(' • ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? p.accent.withValues(alpha: 0.1) : p.fill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? p.accent : p.stroke,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            widget.controller.selectTv(tv.id);
            widget.onDone();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // TV Icon with connection halo
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.tv_rounded, size: 20, color: statusColor),
                ),
                const SizedBox(width: 12),

                // Name and details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              tv.name,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                                color: p.text,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
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
                                  statusLabel,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: statusColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        detailsStr,
                        style: TextStyle(
                          fontSize: 11,
                          color: p.textDim,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 4),

                // Popup menu for quick options
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert_rounded,
                      size: 18, color: p.textDim),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32),
                  onSelected: (val) {
                    if (val == 'open') {
                      widget.controller.selectTv(tv.id);
                      widget.onDone();
                    } else if (val == 'reconfig') {
                      _requestPairing(tv.host, tv.name);
                    } else if (val == 'rename') {
                      _showRenameDialog(tv);
                    } else if (val == 'remove') {
                      _showDeleteDialog(tv);
                    }
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: 'open',
                      child: Row(
                        children: [
                          const Icon(Icons.play_arrow_rounded, size: 18),
                          const SizedBox(width: 8),
                          Text(tr('Abrir controle', 'Open remote',
                              'Abrir control')),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'reconfig',
                      child: Row(
                        children: [
                          const Icon(Icons.lock_reset_rounded, size: 18),
                          const SizedBox(width: 8),
                          Text(tr('Reconfigurar PIN', 'Reconfigure PIN',
                              'Reconfigurar PIN')),
                        ],
                      ),
                    ),
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
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'remove',
                      child: Row(
                        children: [
                          Icon(Icons.link_off_rounded,
                              size: 18, color: p.danger),
                          const SizedBox(width: 8),
                          Text(loc.remove,
                              style: TextStyle(color: p.danger)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectHostStep(AppLocalizations loc, Palette p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Seção com controles salvos
        _buildSavedTvsSection(loc, p),

        Text(
          widget.controller.tvs.isNotEmpty
              ? (Localizations.localeOf(context).languageCode == 'en'
                  ? 'SEARCH NEW DEVICES ON NETWORK'
                  : Localizations.localeOf(context).languageCode == 'es'
                      ? 'BUSCAR NUEVOS DISPOSITIVOS'
                      : 'PROCURAR NOVOS DISPOSITIVOS')
              : loc.pairSubtitle,
          style: TextStyle(
            fontSize: 11,
            fontWeight: widget.controller.tvs.isNotEmpty
                ? FontWeight.bold
                : FontWeight.normal,
            color: p.textDim,
            letterSpacing: widget.controller.tvs.isNotEmpty ? 0.8 : 0,
          ),
        ),
        const SizedBox(height: 12),

        // Discovered TVs list
        if (_discovered.isNotEmpty) ...[
          Text(
            'TVs detectadas:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: p.textDim,
            ),
          ),
          const SizedBox(height: 8),
          ..._discovered.map((tv) {
            final isConfigured =
                widget.controller.tvs.any((t) => t.host == tv.host);
            final savedPairing = !isConfigured
                ? widget.controller.savedPairings
                    .where((sp) => sp.host == tv.host)
                    .firstOrNull
                : null;
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              child: PadButton(
                size: 52,
                width: double.infinity,
                radius: BorderRadius.circular(8),
                onPressed: _busy
                    ? null
                    : () {
                        if (savedPairing != null) {
                          widget.controller.reconnectSavedTv(savedPairing);
                          widget.onDone();
                        } else {
                          _requestPairing(tv.host, tv.displayName);
                        }
                      },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.tv_rounded,
                        size: 22,
                        color: isConfigured ? p.success : p.accent,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    tv.displayName,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isConfigured) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: p.success.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: p.success.withValues(alpha: 0.3),
                                        width: 0.8,
                                      ),
                                    ),
                                    child: Text(
                                      'Configurada',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: p.success,
                                      ),
                                    ),
                                  ),
                                ] else if (savedPairing != null) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: p.accent.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: p.accent.withValues(alpha: 0.3),
                                        width: 0.8,
                                      ),
                                    ),
                                    child: Text(
                                      'PIN Salvo',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: p.accent,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              tv.subtitle,
                              style: TextStyle(
                                fontSize: 11,
                                color: p.textDim,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          size: 18, color: p.textDim),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 12),
        ],

        if (_scanning) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: p.accent,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                loc.searching,
                style: TextStyle(fontSize: 12, color: p.textDim),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ] else if (_discovered.isEmpty) ...[
          SubtleButton(
            icon: Icons.refresh_rounded,
            label: loc.searchAgain,
            onPressed: _startScan,
          ),
          const SizedBox(height: 16),
        ],

        // Manual IP input
        Text(
          loc.manualIp,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: p.textDim,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _ipController,
          decoration: InputDecoration(
            hintText: loc.manualIpHint,
            prefixIcon: const Icon(Icons.lan_rounded, size: 18),
          ),
          keyboardType: TextInputType.text,
        ),
        const SizedBox(height: 10),

        Text(
          loc.tvName,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: p.textDim,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _nameController,
          decoration: InputDecoration(
            hintText: loc.tvNameHint,
            prefixIcon: const Icon(Icons.edit_rounded, size: 18),
          ),
        ),
        const SizedBox(height: 8),

        Text(
          loc.ipHelp,
          style: TextStyle(fontSize: 11, color: p.textDim),
        ),
        const SizedBox(height: 16),

        AccentButton(
          label: loc.connect,
          busy: _busy,
          onPressed: () => _requestPairing(
            _ipController.text,
            _nameController.text,
          ),
        ),
      ],
    );
  }

  Widget _buildEnterCodeStep(AppLocalizations loc, Palette p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          loc.enterCodeSubtitle,
          style: TextStyle(fontSize: 13, color: p.textDim),
        ),
        const SizedBox(height: 20),

        TextField(
          controller: _codeController,
          autofocus: true,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 28,
            letterSpacing: 10,
            fontWeight: FontWeight.bold,
          ),
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            counterText: '',
            hintText: 'A1B2C3',
            hintStyle: TextStyle(
              fontSize: 24,
              letterSpacing: 8,
              color: p.textDim.withValues(alpha: 0.3),
            ),
          ),
          onSubmitted: (_) => _submitCode(),
        ),
        const SizedBox(height: 24),

        AccentButton(
          label: loc.pair,
          busy: _busy,
          onPressed: _submitCode,
        ),
        const SizedBox(height: 10),

        SubtleButton(
          label: loc.cancel,
          onPressed: () {
            widget.controller.cancelPairing();
            _setStep(PairStep.selectHost);
          },
        ),
      ],
    );
  }

  Widget _buildSuccessStep(AppLocalizations loc, Palette p) {
    final name = _nameController.text.trim();
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 20),
          Icon(Icons.check_circle_rounded, size: 54, color: p.success),
          const SizedBox(height: 14),
          Text(
            loc.pairingSuccess,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: p.text,
            ),
          ),
          if (name.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              name,
              style: TextStyle(
                fontSize: 13,
                color: p.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
