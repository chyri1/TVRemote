import 'package:flutter/material.dart';

import '../../core/app_settings.dart';
import '../../core/keycodes.dart';
import '../../core/tv_controller.dart';
import '../theme.dart';
import 'pad_button.dart';

class VolumeControls extends StatelessWidget {
  final TvController controller;

  const VolumeControls({
    super.key,
    required this.controller,
  });

  void _changeVolume(int keyCode) {
    final step = AppSettings.instance.volumeStep;
    for (int i = 0; i < step; i++) {
      controller.sendKey(keyCode);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final vol = controller.volume;
    final isOff = controller.isScreenOff;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Volume down
        PadButton(
          size: 42,
          icon: Icons.volume_down_rounded,
          iconSize: 22,
          repeat: true,
          tooltip: 'Volume -',
          onPressed: () => _changeVolume(KeyCode.volumeDown),
        ),

        // Volume Indicator / Mute toggle
        GestureDetector(
          onTap: () => controller.sendKey(KeyCode.volumeMute),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: p.fill,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: p.stroke),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  (isOff || vol == null)
                      ? Icons.tv_off_rounded
                      : ((vol.muted)
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded),
                  size: 18,
                  color: (!isOff && (vol?.muted ?? false)) ? p.danger : p.textDim,
                ),
                if (!isOff && vol != null && !vol.muted) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${((vol.level / (vol.max > 0 ? vol.max : 100)) * 100).round()}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: p.text,
                    ),
                  ),
                ] else if (isOff || vol == null) ...[
                  const SizedBox(width: 8),
                  Text(
                    'Tela desligada',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: p.textDim,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Volume up
        PadButton(
          size: 42,
          icon: Icons.volume_up_rounded,
          iconSize: 22,
          repeat: true,
          tooltip: 'Volume +',
          onPressed: () => _changeVolume(KeyCode.volumeUp),
        ),
      ],
    );
  }
}
