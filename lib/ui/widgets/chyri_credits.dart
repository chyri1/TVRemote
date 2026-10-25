import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';

/// Opens the official Chyri website in the default system browser.
void launchChyriWebsite() async {
  final uri = Uri.parse('https://www.chyri.com.br/');
  try {
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (launched) return;
  } catch (_) {}

  try {
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.platformDefault,
    );
    if (launched) return;
  } catch (_) {}

  try {
    if (Platform.isWindows) {
      Process.run('cmd', ['/c', 'start', '', uri.toString()]);
    } else if (Platform.isMacOS) {
      Process.run('open', [uri.toString()]);
    } else if (Platform.isLinux) {
      Process.run('xdg-open', [uri.toString()]);
    }
  } catch (_) {}
}

/// A clean footer widget displaying "Criado por Chyri · 2026", where "Chyri"
/// is an interactive, clickable link leading to https://www.chyri.com.br/.
class ChyriCredits extends StatefulWidget {
  final String? appTitle;

  const ChyriCredits({super.key, this.appTitle});

  @override
  State<ChyriCredits> createState() => _ChyriCreditsState();
}

class _ChyriCreditsState extends State<ChyriCredits> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final prefix = lang == 'en'
        ? 'Created by '
        : (lang == 'es' ? 'Creado por ' : 'Criado por ');

    return Tooltip(
      message: 'https://www.chyri.com.br/',
      waitDuration: const Duration(milliseconds: 300),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: launchChyriWebsite,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.appTitle != null) ...[
                  Text(
                    widget.appTitle!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: p.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text.rich(
                  TextSpan(
                    text: prefix,
                    style: TextStyle(
                      fontSize: 11,
                      color: p.textDim,
                      letterSpacing: 0.2,
                    ),
                    children: [
                      TextSpan(
                        text: 'Chyri',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _hovered ? p.accent : p.text,
                          decoration: _hovered
                              ? TextDecoration.underline
                              : TextDecoration.none,
                          decorationColor: p.accent,
                          letterSpacing: 0.2,
                        ),
                      ),
                      TextSpan(
                        text: ' - v. 1.0 - 21/10/2026',
                        style: TextStyle(
                          fontSize: 11,
                          color: p.textDim,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
