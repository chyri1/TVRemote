import 'package:flutter/material.dart';

import '../../core/keycodes.dart';
import '../../core/tv_controller.dart';
import '../theme.dart';
import 'pad_button.dart';

class DPad extends StatelessWidget {
  final TvController controller;
  final double size;

  const DPad({
    super.key,
    required this.controller,
    this.size = 200,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    const buttonSize = 42.0;
    const centerSize = 58.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: p.fill,
        border: Border.all(color: p.stroke, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: p.dark ? 0.25 : 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Up
          Positioned(
            top: 8,
            child: PadButton(
              size: buttonSize,
              icon: Icons.keyboard_arrow_up_rounded,
              iconSize: 26,
              repeat: true,
              tooltip: 'Cima (↑)',
              onPressed: () => controller.sendKey(KeyCode.dpadUp),
            ),
          ),
          // Down
          Positioned(
            bottom: 8,
            child: PadButton(
              size: buttonSize,
              icon: Icons.keyboard_arrow_down_rounded,
              iconSize: 26,
              repeat: true,
              tooltip: 'Baixo (↓)',
              onPressed: () => controller.sendKey(KeyCode.dpadDown),
            ),
          ),
          // Left
          Positioned(
            left: 8,
            child: PadButton(
              size: buttonSize,
              icon: Icons.keyboard_arrow_left_rounded,
              iconSize: 26,
              repeat: true,
              tooltip: 'Esquerda (←)',
              onPressed: () => controller.sendKey(KeyCode.dpadLeft),
            ),
          ),
          // Right
          Positioned(
            right: 8,
            child: PadButton(
              size: buttonSize,
              icon: Icons.keyboard_arrow_right_rounded,
              iconSize: 26,
              repeat: true,
              tooltip: 'Direita (→)',
              onPressed: () => controller.sendKey(KeyCode.dpadRight),
            ),
          ),
          // Center OK (com espaçamento agradável e confortável)
          PadButton(
            size: centerSize,
            background: p.accent,
            foreground: p.onAccent,
            tooltip: 'OK (Enter)',
            onPressed: () => controller.sendKey(KeyCode.dpadCenter),
            child: const Text(
              'OK',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
