import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/adb_service.dart';
import '../../core/app_settings.dart';
import '../theme.dart';
import 'chyri_credits.dart';
import 'pad_button.dart';

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (ctx) => const SettingsDialog(),
    );
  }

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late final TextEditingController _volumeCtrl;

  @override
  void initState() {
    super.initState();
    _volumeCtrl = TextEditingController(
      text: AppSettings.instance.volumeStep.toString(),
    );
  }

  @override
  void dispose() {
    _volumeCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleVolumeStepChange(
    BuildContext context,
    int newStep,
    String Function(String, String, String) tr,
  ) async {
    if (newStep >= 10) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final p = Palette.of(ctx);
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: p.stroke),
            ),
            backgroundColor: p.panelTint,
            title: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: p.warning, size: 22),
                const SizedBox(width: 8),
                Text(
                  tr('Aviso de volume', 'Volume warning', 'Aviso de volumen'),
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
            content: Text(
              tr(
                'Esse salto causará uma mudança repentina de volume',
                'This step will cause a sudden volume change',
                'Este salto causará un cambio repentino de volumen',
              ),
              style: TextStyle(color: p.text, fontSize: 13.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('Reverter', 'Revert', 'Revertir')),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: p.warning),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr('Confirmar', 'Confirm', 'Confirmar')),
              ),
            ],
          );
        },
      );

      if (confirmed == true) {
        await AppSettings.instance.setVolumeStep(newStep);
        if (mounted) _volumeCtrl.text = newStep.toString();
      } else {
        if (mounted) {
          _volumeCtrl.text = AppSettings.instance.volumeStep.toString();
        }
      }
    } else if (newStep >= 1) {
      await AppSettings.instance.setVolumeStep(newStep);
      if (mounted) _volumeCtrl.text = newStep.toString();
    } else {
      if (mounted) {
        _volumeCtrl.text = AppSettings.instance.volumeStep.toString();
      }
    }
  }

  Future<void> _showAddCustomAppDialog(
    BuildContext context,
    String Function(String, String, String) tr,
  ) async {
    final nameCtrl = TextEditingController();
    final linkCtrl = TextEditingController();
    final p = Palette.of(context);

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: p.stroke),
        ),
        backgroundColor: p.panelTint,
        title: Text(
          tr('Novo aplicativo', 'New app', 'Nueva aplicación'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: tr('Nome do app', 'App name', 'Nombre de la app'),
                hintText: 'Ex: Kodi, Stremio, Crunchyroll',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: linkCtrl,
              decoration: InputDecoration(
                labelText:
                    tr('Link ou pacote', 'Link or package', 'Enlace o paquete'),
                hintText: 'Ex: https://..., org.xbmc.kodi',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Cancelar', 'Cancel', 'Cancelar')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: p.accent,
              foregroundColor: p.onAccent,
            ),
            onPressed: () {
              final name = nameCtrl.text.trim();
              final link = linkCtrl.text.trim();
              if (name.isNotEmpty && link.isNotEmpty) {
                AppSettings.instance.addCustomApp(name, link);
                Navigator.pop(ctx);
              }
            },
            child: Text(tr('Adicionar', 'Add', 'Agregar')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final settings = AppSettings.instance;

    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final currentTheme = settings.themeMode;
        final currentLocale = settings.locale?.languageCode;
        final animDurationMs = settings.animationDurationMs;
        final volumeStep = settings.volumeStep;
        final featuredApps = settings.featuredApps;

        final activeLang =
            currentLocale ?? settings.effectiveLocale.languageCode;

        String tr(String pt, String en, String es) {
          if (activeLang == 'en') return en;
          if (activeLang == 'es') return es;
          return pt;
        }

        return AlertDialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: p.stroke, width: 1),
          ),
          backgroundColor: p.panelTint,
          titlePadding: const EdgeInsets.fromLTRB(18, 16, 14, 10),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          actionsPadding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.settings_outlined, size: 18, color: p.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr('Configurações', 'Settings', 'Configuración'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: p.text,
                  ),
                ),
              ),
              PadButton(
                size: 28,
                icon: Icons.close_rounded,
                iconSize: 16,
                tooltip: tr('Fechar', 'Close', 'Cerrar'),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          content: SizedBox(
            width: 320,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. APARÊNCIA
                  _buildSectionHeader(
                      tr('APARÊNCIA', 'APPEARANCE', 'APARIENCIA'), p),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildThemeChip(
                        context,
                        label: tr('Sistema', 'System', 'Sistema'),
                        icon: Icons.brightness_auto_rounded,
                        selected: currentTheme == ThemeMode.system,
                        onTap: () => settings.setThemeMode(ThemeMode.system),
                        p: p,
                      ),
                      const SizedBox(width: 6),
                      _buildThemeChip(
                        context,
                        label: tr('Claro', 'Light', 'Claro'),
                        icon: Icons.light_mode_rounded,
                        selected: currentTheme == ThemeMode.light,
                        onTap: () => settings.setThemeMode(ThemeMode.light),
                        p: p,
                      ),
                      const SizedBox(width: 6),
                      _buildThemeChip(
                        context,
                        label: tr('Escuro', 'Dark', 'Oscuro'),
                        icon: Icons.dark_mode_rounded,
                        selected: currentTheme == ThemeMode.dark,
                        onTap: () => settings.setThemeMode(ThemeMode.dark),
                        p: p,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // TAMANHO DA JANELA
                  _buildSectionHeader(
                    tr('TAMANHO DA JANELA', 'WINDOW SIZE', 'TAMAÑO DE LA VENTANA'),
                    p,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: p.fill,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: p.stroke),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              tr('Modo atual', 'Current mode', 'Modo actual'),
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: p.text),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: settings.hasManualWindowHeight
                                    ? p.accent.withValues(alpha: 0.15)
                                    : p.stroke.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                settings.hasManualWindowHeight
                                    ? tr(
                                        'Manual (${settings.manualWindowHeight!.round()}px)',
                                        'Manual (${settings.manualWindowHeight!.round()}px)',
                                        'Manual (${settings.manualWindowHeight!.round()}px)')
                                    : tr('Automático', 'Automatic', 'Automático'),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: settings.hasManualWindowHeight
                                      ? p.accent
                                      : p.textDim,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          tr(
                            'Puxe a borda superior para redimensionar nesta sessão (volta ao automático ao reiniciar).',
                            'Drag the top edge to resize in this session (resets to automatic on restart).',
                            'Arrastra el borde superior para redimensionar en esta sesión (vuelve a automático al reiniciar).',
                          ),
                          style: TextStyle(fontSize: 11, color: p.textDim),
                        ),
                        if (settings.hasManualWindowHeight) ...[
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: p.accent,
                              side: BorderSide(color: p.accent.withValues(alpha: 0.5)),
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            icon: const Icon(Icons.restart_alt_rounded, size: 16),
                            label: Text(
                              tr('Redefinir para automático', 'Reset to automatic', 'Restablecer a automático'),
                              style: const TextStyle(fontSize: 12),
                            ),
                            onPressed: () {
                              settings.resetManualWindowHeight();
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // 2. DURAÇÃO DAS ANIMAÇÕES
                  _buildSectionHeader(
                    tr('DURAÇÃO DAS ANIMAÇÕES', 'ANIMATION DURATION',
                        'DURACIÓN DE ANIMACIONES'),
                    p,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: p.fill,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: p.stroke),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              tr('Tempo de resposta', 'Response time',
                                  'Tiempo de respuesta'),
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: p.text),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: animDurationMs == 0
                                    ? p.danger.withValues(alpha: 0.15)
                                    : p.accent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                animDurationMs == 0
                                    ? tr('0 ms (Desativadas)',
                                        '0 ms (Disabled)', '0 ms (Desactivado)')
                                    : '$animDurationMs ms',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: animDurationMs == 0
                                      ? p.danger
                                      : p.accent,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: p.accent,
                            inactiveTrackColor: p.stroke,
                            thumbColor: p.accent,
                            overlayColor: p.accent.withValues(alpha: 0.15),
                            trackHeight: 3,
                          ),
                          child: Slider(
                            value: animDurationMs.toDouble(),
                            min: 0,
                            max: 500,
                            divisions: 10,
                            onChanged: (val) {
                              settings.setAnimationDuration(val.toInt());
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // 3. PULO DO VOLUME (VOLUME STEP)
                  _buildSectionHeader(
                    tr('SALTO DE VOLUME (+ / -)', 'VOLUME STEP (+ / -)',
                        'SALTO DE VOLUMEN (+ / -)'),
                    p,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: p.fill,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: p.stroke),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                tr(
                                  'Pulos por toque no botão',
                                  'Step per button press',
                                  'Salto por toque de botón',
                                ),
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: p.text),
                              ),
                            ),
                            SizedBox(
                              width: 60,
                              height: 34,
                              child: TextField(
                                controller: _volumeCtrl,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(2),
                                ],
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: p.text,
                                ),
                                decoration: InputDecoration(
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                      vertical: 8, horizontal: 4),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: BorderSide(color: p.stroke),
                                  ),
                                ),
                                onSubmitted: (val) {
                                  final num = int.tryParse(val) ?? volumeStep;
                                  _handleVolumeStepChange(context, num, tr);
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [1, 2, 4, 5].map((step) {
                            final isSel = volumeStep == step;
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: InkWell(
                                onTap: () => _handleVolumeStepChange(
                                    context, step, tr),
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isSel
                                        ? p.accent.withValues(alpha: 0.18)
                                        : p.fillHover,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isSel ? p.accent : p.stroke,
                                      width: isSel ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Text(
                                    '+$step',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: isSel
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: isSel ? p.accent : p.text,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // 4. APPS EM DESTAQUE (FEATURED APPS)
                  _buildSectionHeader(
                    tr('APPS EM DESTAQUE', 'FEATURED APPS',
                        'APPS DESTACADAS'),
                    p,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: p.fill,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: p.stroke),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        Theme(
                          data: Theme.of(context).copyWith(
                            canvasColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                          ),
                          child: ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            buildDefaultDragHandles: false,
                            itemCount: featuredApps.length,
                            // ignore: deprecated_member_use
                            onReorder: (oldIndex, newIndex) {
                              settings.reorderApps(oldIndex, newIndex);
                            },
                            proxyDecorator: (child, index, animation) {
                              return Material(
                                color: p.panelTint.withValues(alpha: 0.96),
                                elevation: 4,
                                shadowColor: Colors.black45,
                                borderRadius: BorderRadius.circular(6),
                                child: child,
                              );
                            },
                            itemBuilder: (context, index) {
                              final app = featuredApps[index];
                              return Column(
                                key: ValueKey(app.id),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    child: Row(
                                      children: [
                                        Checkbox(
                                          value: app.enabled,
                                          activeColor: p.accent,
                                          visualDensity: VisualDensity.compact,
                                          onChanged: (val) {
                                            settings.toggleApp(
                                                app.id, val ?? false);
                                          },
                                        ),
                                        Container(
                                          width: 9,
                                          height: 9,
                                          decoration: BoxDecoration(
                                            color: Color(app.color),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                app.label,
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w500,
                                                  color: p.text,
                                                ),
                                              ),
                                              Text(
                                                app.link,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: p.textDim,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (app.isCustom)
                                          IconButton(
                                            iconSize: 16,
                                            visualDensity: VisualDensity.compact,
                                            tooltip: tr('Remover', 'Remove',
                                                'Eliminar'),
                                            icon: Icon(Icons.delete_outline_rounded,
                                                color: p.danger),
                                            onPressed: () =>
                                                settings.removeCustomApp(app.id),
                                          ),
                                        // Controles para mudar a ordem no canto direito
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // Botão Mover para cima
                                            IconButton(
                                              iconSize: 18,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                  minWidth: 26, minHeight: 28),
                                              visualDensity: VisualDensity.compact,
                                              tooltip: tr('Mover para cima',
                                                  'Move up', 'Mover arriba'),
                                              icon: Icon(
                                                Icons.keyboard_arrow_up_rounded,
                                                color: index > 0
                                                    ? p.textDim
                                                    : p.textDim.withValues(alpha: 0.2),
                                              ),
                                              onPressed: index > 0
                                                  ? () => settings.moveApp(
                                                      index, index - 1)
                                                  : null,
                                            ),
                                            // Botão Mover para baixo
                                            IconButton(
                                              iconSize: 18,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                  minWidth: 26, minHeight: 28),
                                              visualDensity: VisualDensity.compact,
                                              tooltip: tr('Mover para baixo',
                                                  'Move down', 'Mover abajo'),
                                              icon: Icon(
                                                Icons.keyboard_arrow_down_rounded,
                                                color: index < featuredApps.length - 1
                                                    ? p.textDim
                                                    : p.textDim.withValues(alpha: 0.2),
                                              ),
                                              onPressed: index < featuredApps.length - 1
                                                  ? () => settings.moveApp(
                                                      index, index + 1)
                                                  : null,
                                            ),
                                            const SizedBox(width: 2),
                                            // Alça para arrastar e soltar (Drag Handle)
                                            ReorderableDragStartListener(
                                              index: index,
                                              child: MouseRegion(
                                                cursor: SystemMouseCursors.grab,
                                                child: Tooltip(
                                                  message: tr(
                                                      'Arrastar para reordenar',
                                                      'Drag to reorder',
                                                      'Arrastrar para reordenar'),
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(
                                                        horizontal: 4, vertical: 6),
                                                    color: Colors.transparent,
                                                    child: Icon(
                                                      Icons.drag_indicator_rounded,
                                                      size: 18,
                                                      color: p.textDim.withValues(alpha: 0.7),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (index < featuredApps.length - 1)
                                    Divider(height: 1, color: p.stroke),
                                ],
                              );
                            },
                          ),
                        ),
                        Divider(height: 1, color: p.stroke),
                        InkWell(
                          onTap: () => _showAddCustomAppDialog(context, tr),
                          borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(8)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 10, horizontal: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_rounded,
                                    size: 16, color: p.accent),
                                const SizedBox(width: 6),
                                Text(
                                  tr(
                                    '+ Adicionar aplicativo personalizado',
                                    '+ Add custom application',
                                    '+ Agregar app personalizada',
                                  ),
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: p.accent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // 5. IDIOMA
                  _buildSectionHeader(
                      tr('IDIOMA', 'LANGUAGE', 'IDIOMA'), p),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: p.fill,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: p.stroke, width: 1),
                    ),
                    child: Column(
                      children: [
                        _buildLocaleTile(
                          title: tr('Seguir o sistema', 'Follow system',
                              'Seguir el sistema'),
                          subtitle: tr('Padrão do Windows', 'Windows default',
                              'Predeterminado de Windows'),
                          selected: currentLocale == null,
                          onTap: () => settings.setLocale(null),
                          p: p,
                        ),
                        Divider(height: 1, color: p.stroke),
                        _buildLocaleTile(
                          title: 'Português (Brasil)',
                          subtitle: 'pt-BR',
                          selected: currentLocale == 'pt',
                          onTap: () => settings.setLocale(const Locale('pt')),
                          p: p,
                        ),
                        Divider(height: 1, color: p.stroke),
                        _buildLocaleTile(
                          title: 'English',
                          subtitle: 'en-US',
                          selected: currentLocale == 'en',
                          onTap: () => settings.setLocale(const Locale('en')),
                          p: p,
                        ),
                        Divider(height: 1, color: p.stroke),
                        _buildLocaleTile(
                          title: 'Español',
                          subtitle: 'es',
                          selected: currentLocale == 'es',
                          onTap: () => settings.setLocale(const Locale('es')),
                          p: p,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // 6. DEPURAÇÃO ADB & PLATFORM-TOOLS
                  _buildSectionHeader(
                    tr('DEPURAÇÃO ADB', 'ADB DEBUGGING', 'DEPURACIÓN ADB'),
                    p,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: p.fill,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: p.stroke),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    tr('Suporte a Minimal ADB (Legado)',
                                        'Minimal ADB support (Legacy)',
                                        'Soporte a Minimal ADB (Legado)'),
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: p.text,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    tr('O Google Platform-Tools é o recomendado. Ative apenas se precisar usar uma instalação antiga do Minimal ADB.',
                                        'Google Platform-Tools is recommended. Only enable if using an old Minimal ADB install.',
                                        'Se recomienda Google Platform-Tools. Active solo si usa una instalación antigua de Minimal ADB.'),
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: p.textDim,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: settings.useMinimalAdb,
                              activeThumbColor: p.accent,
                              onChanged: (val) => settings.setUseMinimalAdb(val),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: p.fillHover,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: p.stroke),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                AdbService.instance.isMinimalAdb
                                    ? Icons.flash_on_rounded
                                    : Icons.verified_rounded,
                                size: 15,
                                color: AdbService.instance.isMinimalAdb
                                    ? Colors.amberAccent
                                    : p.accent,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${tr("Executável ativo", "Active binary", "Ejecutable activo")}: ${AdbService.instance.adbVariantFullName}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: p.text,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // 7. ESPELHAMENTO DE TELA (SCREEN MIRROR)
                  _buildSectionHeader(
                    tr('ESPELHAMENTO DE TELA', 'SCREEN MIRRORING', 'DUPLICACIÓN DE PANTALLA'),
                    p,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: p.fill,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: p.stroke),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr(
                            'Exibir espelhamento de tela',
                            'Show screen mirror on remote',
                            'Mostrar duplicación de pantalla',
                          ),
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: p.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          tr(
                            'Mostra o quadro de transmissão ou tela ADB diretamente no controle.',
                            'Displays media cast or ADB screen mirror inside the remote view.',
                            'Muestra la transmisión o pantalla ADB directamente en el control.',
                          ),
                          style: TextStyle(
                            fontSize: 10.5,
                            color: p.textDim,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _buildOptionChip(
                              label: tr('Não', 'No', 'No'),
                              selected: settings.screenMirrorOption == ScreenMirrorOption.no,
                              onTap: () => settings.setScreenMirrorOption(ScreenMirrorOption.no),
                              p: p,
                            ),
                            const SizedBox(width: 6),
                            _buildOptionChip(
                              label: tr('Apenas nessa sessão', 'Session only', 'Solo en esta sesión'),
                              selected: settings.screenMirrorOption == ScreenMirrorOption.sessionOnly,
                              onTap: () => settings.setScreenMirrorOption(ScreenMirrorOption.sessionOnly),
                              p: p,
                            ),
                            const SizedBox(width: 6),
                            _buildOptionChip(
                              label: tr('Sim', 'Yes', 'Sí'),
                              selected: settings.screenMirrorOption == ScreenMirrorOption.yes,
                              onTap: () => settings.setScreenMirrorOption(ScreenMirrorOption.yes),
                              p: p,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // 8. COMANDO MANUAL PARA TV
                  _buildSectionHeader(
                    tr('COMANDO MANUAL PARA TV', 'MANUAL TV COMMAND', 'COMANDO MANUAL PARA TV'),
                    p,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: p.fill,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: p.stroke),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr('Habilitar comando manual',
                                    'Enable manual command box',
                                    'Habilitar comando manual'),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: p.text,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                tr('Abre uma caixa no controle com botão de envio para testar keycodes e comandos na TV.',
                                    'Opens a text input with send button on the remote to test keycodes and commands.',
                                    'Abre una caja en el control con botón de envío para probar keycodes y comandos.'),
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: p.textDim,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: settings.manualCommandEnabled,
                          activeThumbColor: p.accent,
                          onChanged: (val) => settings.setManualCommandEnabled(val),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // 9. NOME REAL DO APP / PACOTE EM TEMPO REAL
                  _buildSectionHeader(
                    tr('EXIBIÇÃO DE NOMES DE APPS', 'APP NAMES DISPLAY', 'VISUALIZACIÓN DE NOMBRES'),
                    p,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: p.fill,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: p.stroke),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr('Mostrar nome real recebido da TV',
                                    'Show raw name from Android TV',
                                    'Mostrar nombre real de Android TV'),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: p.text,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                tr('Exibe o identificador ou nome bruto original recebido em tempo real em vez do nome normatizado.',
                                    'Displays the raw app or package name received in real-time instead of the normalized name.',
                                    'Muestra el identificador o nombre original recibido en tiempo real en vez del normalizado.'),
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: p.textDim,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: settings.showRawPackageName,
                          activeThumbColor: p.accent,
                          onChanged: (val) => settings.setShowRawPackageName(val),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 9. RODAPÉ DE CRÉDITOS
                  const Center(
                    child: ChyriCredits(appTitle: 'TV Remote by Chyri'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: p.accent,
                  foregroundColor: p.onAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => Navigator.pop(context),
                child: Text(tr('Concluir', 'Done', 'Listo')),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSectionHeader(String title, Palette p) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.8,
        color: p.textDim,
      ),
    );
  }

  Widget _buildThemeChip(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
    required Palette p,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? p.accent.withValues(alpha: 0.18) : p.fill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? p.accent : p.stroke,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? p.accent : p.textDim,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  color: selected ? p.text : p.textDim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required Palette p,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? p.accent.withValues(alpha: 0.18) : p.fillHover,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? p.accent : p.stroke,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected ? p.accent : p.text,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLocaleTile({
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
    required Palette p,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.normal,
                      color: selected ? p.text : p.text.withValues(alpha: 0.8),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10,
                      color: p.textDim,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, size: 18, color: p.accent)
            else
              Icon(Icons.radio_button_unchecked_rounded,
                  size: 16, color: p.textDim.withValues(alpha: 0.4)),
          ],
        ),
      ),
    );
  }
}
