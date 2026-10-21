import 'dart:io';

import 'package:flutter/material.dart';
import 'package:system_theme/system_theme.dart';

/// Design tokens for the translucent (Acrylic/Mica) flyout.
class Palette {
  final bool dark;
  final Color accent;
  final Color onAccent;
  final Color fill;
  final Color fillHover;
  final Color fillPressed;
  final Color stroke;
  final Color text;
  final Color textDim;
  final Color danger;
  final Color success;
  final Color warning;
  final Color panelTint;

  const Palette._({
    required this.dark,
    required this.accent,
    required this.onAccent,
    required this.fill,
    required this.fillHover,
    required this.fillPressed,
    required this.stroke,
    required this.text,
    required this.textDim,
    required this.danger,
    required this.success,
    required this.warning,
    required this.panelTint,
  });

  factory Palette.build(Brightness b) {
    final dark = b == Brightness.dark;
    final sys = SystemTheme.accentColor;
    final accent = dark ? sys.lighter : sys.dark;
    final onAccent =
        ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
            ? Colors.white
            : Colors.black;
    return Palette._(
      dark: dark,
      accent: accent,
      onAccent: onAccent,
      fill: dark ? const Color(0x14FFFFFF) : const Color(0x0A000000),
      fillHover: dark ? const Color(0x22FFFFFF) : const Color(0x14000000),
      fillPressed: dark ? const Color(0x30FFFFFF) : const Color(0x20000000),
      stroke: dark ? const Color(0x1AFFFFFF) : const Color(0x14000000),
      text: dark ? const Color(0xFFF5F5F7) : const Color(0xFF1B1B1F),
      textDim: dark ? const Color(0xA6FFFFFF) : const Color(0x99000000),
      danger: dark ? const Color(0xFFFF6B6B) : const Color(0xFFD13438),
      success: dark ? const Color(0xFF6CCB5F) : const Color(0xFF0F7B0F),
      warning: dark ? const Color(0xFFFCE100) : const Color(0xFF9D5D00),
      // Extra tint drawn by Flutter on top of the OS backdrop so contrast
      // stays good even when the backdrop effect is unavailable.
      panelTint: dark ? const Color(0xF41E1E22) : const Color(0xF8F5F5F7),
    );
  }

  static Palette of(BuildContext context) =>
      Theme.of(context).extension<PaletteExt>()!.palette;
}

class PaletteExt extends ThemeExtension<PaletteExt> {
  final Palette palette;
  const PaletteExt(this.palette);
  @override
  PaletteExt copyWith({Palette? palette}) => PaletteExt(palette ?? this.palette);
  @override
  PaletteExt lerp(PaletteExt? other, double t) => t < 0.5 ? this : (other ?? this);
}

ThemeData buildTheme(Brightness b) {
  final p = Palette.build(b);
  final base = ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: ColorScheme.fromSeed(
      seedColor: p.accent,
      brightness: b,
      primary: p.accent,
      onPrimary: p.onAccent,
    ),
    fontFamily: Platform.isWindows ? 'Segoe UI' : null,
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: Colors.transparent,
    splashFactory: NoSplash.splashFactory,
    extensions: [PaletteExt(p)],
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: p.text, displayColor: p.text),
    iconTheme: IconThemeData(color: p.text),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 600),
      decoration: BoxDecoration(
        color: p.dark ? const Color(0xFF2B2B2B) : Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: p.stroke),
      ),
      textStyle: TextStyle(color: p.text, fontSize: 12),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.dark ? const Color(0xFF2B2B2B) : const Color(0xFFF9F9F9),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: p.stroke),
      ),
      textStyle: TextStyle(color: p.text, fontSize: 13),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.fill,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      hintStyle: TextStyle(color: p.textDim),
      labelStyle: TextStyle(color: p.textDim),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: p.stroke),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: p.stroke),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: p.accent, width: 2),
      ),
    ),
  );
}
