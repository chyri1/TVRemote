import 'package:flutter/material.dart';

import '../../core/app_settings.dart';
import '../../core/tv_controller.dart';
import '../theme.dart';

class AppGrid extends StatelessWidget {
  final TvController controller;

  const AppGrid({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final settings = AppSettings.instance;

    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final apps = settings.enabledApps;
        if (apps.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              appTr(
                pt: 'Nenhum aplicativo ativado',
                en: 'No apps enabled',
                es: 'Ninguna aplicación activada',
              ),
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: p.textDim,
              ),
            ),
          );
        }

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: apps.map((app) {
            final color = Color(app.color);
            String label = app.label;
            if (app.id == 'settings' || app.link == 'settings') {
              label = appTr(
                pt: 'Configurações',
                en: 'Settings',
                es: 'Configuración',
              );
            }
            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => controller.launchApp(app.link),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: p.fill,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: p.stroke),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: p.text,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
