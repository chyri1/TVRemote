import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/adb_service.dart';
import '../../core/app_settings.dart';
import '../theme.dart';

/// Opens an interactive dialog to change the ADB connection port for the TV.
Future<void> showAdbPortDialog(BuildContext context, String tvHost) async {
  final p = Palette.of(context);
  final adb = AdbService.instance;
  final ctrl = TextEditingController(text: adb.adbPort.toString());

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return AlertDialog(
            backgroundColor: p.panelTint,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: p.stroke, width: 1),
            ),
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF60CDFF).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.settings_ethernet_rounded,
                    size: 20,
                    color: Color(0xFF60CDFF),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    appTr(
                      pt: 'Porta de Conexão ADB',
                      en: 'ADB Connection Port',
                      es: 'Puerto de conexión ADB',
                    ),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ADB Variant Selector / Switcher
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: p.fill,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: p.stroke, width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.swap_calls_rounded, size: 14, color: p.accent),
                            const SizedBox(width: 6),
                            Text(
                              appTr(
                                pt: 'Modo de ADB em Uso',
                                en: 'Active ADB Mode',
                                es: 'Modo de ADB activo',
                              ),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: p.text,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Option 1: Standard ADB
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () async {
                            if (adb.isMinimalAdb) {
                              await adb.switchVariant(useMinimal: false);
                              setDialogState(() {});
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: !adb.isMinimalAdb
                                  ? const Color(0xFF60CDFF).withValues(alpha: 0.15)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: !adb.isMinimalAdb
                                    ? const Color(0xFF60CDFF).withValues(alpha: 0.5)
                                    : p.stroke.withValues(alpha: 0.5),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  !adb.isMinimalAdb
                                      ? Icons.radio_button_checked_rounded
                                      : Icons.radio_button_off_rounded,
                                  size: 15,
                                  color: !adb.isMinimalAdb ? const Color(0xFF60CDFF) : p.textDim,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'ADB Padrão (Platform-Tools)',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        'Google Official',
                                        style: TextStyle(fontSize: 9.5, color: p.textDim),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!adb.isMinimalAdb)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF60CDFF).withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'ATIVO',
                                      style: TextStyle(
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF60CDFF),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Option 2: Minimal ADB and Fastboot
                        Builder(
                          builder: (context) {
                            final minimalPath = AdbService.detectMinimalAdbPath();
                            final isInstalled = minimalPath != null;
                            final displayPath = minimalPath ?? r'C:\Program Files (x86)\Minimal ADB and Fastboot\adb.exe';

                            return InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () async {
                                if (!adb.isMinimalAdb) {
                                  await adb.switchVariant(useMinimal: true);
                                  setDialogState(() {});
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: adb.isMinimalAdb
                                      ? Colors.amber.withValues(alpha: 0.15)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: adb.isMinimalAdb
                                        ? Colors.amber.withValues(alpha: 0.5)
                                        : p.stroke.withValues(alpha: 0.5),
                                    width: 0.8,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      adb.isMinimalAdb
                                          ? Icons.radio_button_checked_rounded
                                          : Icons.radio_button_off_rounded,
                                      size: 15,
                                      color: adb.isMinimalAdb ? Colors.amberAccent : p.textDim,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Minimal ADB and Fastboot',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            displayPath,
                                            style: TextStyle(fontSize: 9.5, color: p.textDim),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: (adb.isMinimalAdb
                                                ? Colors.amber
                                                : (isInstalled ? Colors.green : Colors.grey))
                                            .withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        adb.isMinimalAdb
                                            ? 'ATIVO'
                                            : (isInstalled ? 'INSTALADO' : 'NÃO DETECTADO'),
                                        style: TextStyle(
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.bold,
                                          color: adb.isMinimalAdb
                                              ? Colors.amberAccent
                                              : (isInstalled ? Colors.greenAccent : Colors.grey),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  Text(
                    '${appTr(pt: 'Informe a porta TCP/IP de depuração da TV em', en: 'Enter the TV debugging TCP/IP port for', es: 'Introduce el puerto TCP/IP de depuración de la TV en')} $tvHost:',
                    style: TextStyle(fontSize: 12, color: p.textDim),
                  ),
                  const SizedBox(height: 12),

                  // Port Input Field
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(5),
                    ],
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.tag_rounded, size: 18),
                      hintText: '5555',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        tooltip: appTr(pt: 'Limpar', en: 'Clear', es: 'Borrar'),
                        onPressed: () {
                          ctrl.clear();
                          setDialogState(() {});
                        },
                      ),
                    ),
                    onSubmitted: (val) {
                      final port = int.tryParse(val.trim());
                      if (port != null && port > 0 && port <= 65535) {
                        Navigator.pop(ctx);
                        adb.reRequestConnection(tvHost, port);
                      }
                    },
                  ),
                  const SizedBox(height: 10),

                  // Quick presets
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [5555, 5556, 4321].map((port) {
                      final isSelected = ctrl.text.trim() == port.toString();
                      final defaultLabel = port == 5555
                          ? '5555 (${appTr(pt: 'Padrão', en: 'Default', es: 'Predeterminado')})'
                          : port.toString();
                      return ActionChip(
                        label: Text(
                          defaultLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? const Color(0xFF60CDFF) : p.text,
                          ),
                        ),
                        backgroundColor: isSelected
                            ? const Color(0xFF60CDFF).withValues(alpha: 0.15)
                            : p.fill,
                        side: BorderSide(
                          color: isSelected ? const Color(0xFF60CDFF) : p.stroke,
                          width: 1,
                        ),
                        onPressed: () {
                          ctrl.text = port.toString();
                          setDialogState(() {});
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),

                  // Info Tip
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: p.stroke, width: 0.8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 15,
                          color: Color(0xFF60CDFF),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            appTr(
                              pt: 'A porta padrão da "Depuração USB" na Android TV é sempre 5555.\n\nNota: A porta de 5 dígitos exibida em "Depuração por Wi-Fi" requer pareamento numérico e fica offline para transmissão direta. Use sempre 5555.',
                              en: 'The default port for "USB Debugging" on Android TV is always 5555.\n\nNote: The 5-digit port shown in "Wireless debugging" requires numeric pairing and stays offline for direct streaming. Always use 5555.',
                              es: 'El puerto predeterminado para "Depuración USB" en Android TV siempre es 5555.\n\nNota: El puerto de 5 dígitos de "Depuración por Wi-Fi" requiere emparejamiento numérico y queda desconectado para transmisión directa. Usa siempre 5555.',
                            ),
                            style: TextStyle(fontSize: 10.5, color: p.textDim, height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(appTr(pt: 'Cancelar', en: 'Cancel', es: 'Cancelar')),
              ),
              FilledButton(
                onPressed: () {
                  final port = int.tryParse(ctrl.text.trim());
                  if (port == null || port <= 0 || port > 65535) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(appTr(
                          pt: 'Porta inválida (deve ser entre 1 e 65535).',
                          en: 'Invalid port (must be between 1 and 65535).',
                          es: 'Puerto no válido (debe estar entre 1 y 65535).',
                        )),
                        backgroundColor: p.danger,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }
                  Navigator.pop(ctx);
                  adb.reRequestConnection(tvHost, port);

                  ScaffoldMessenger.of(context).clearSnackBars();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, color: Color(0xFF60CDFF), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${appTr(pt: 'Conectando via ADB na porta', en: 'Connecting via ADB on port', es: 'Conectando por ADB en el puerto')} $port ($tvHost:$port)...',
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      backgroundColor: const Color(0xFF1E1E24),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                },
                child: Text(appTr(pt: 'Conectar', en: 'Connect', es: 'Conectar')),
              ),
            ],
          );
        },
      );
    },
  );
}
