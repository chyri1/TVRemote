import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_settings.dart';
import '../theme.dart';

/// Button with hover/press feedback and optional auto-repeat while held
/// (used for volume and D-pad navigation).
class PadButton extends StatefulWidget {
  final IconData? icon;
  final Widget? child;
  final String? tooltip;
  final VoidCallback? onPressed;
  final bool repeat;
  final double size;
  final double? width;
  final BorderRadius? radius;
  final Color? background;
  final Color? foreground;
  final double iconSize;

  const PadButton({
    super.key,
    this.icon,
    this.child,
    this.tooltip,
    this.onPressed,
    this.repeat = false,
    this.size = 48,
    this.width,
    this.radius,
    this.background,
    this.foreground,
    this.iconSize = 20,
  });

  @override
  State<PadButton> createState() => _PadButtonState();
}

class _PadButtonState extends State<PadButton> {
  bool _hover = false;
  bool _down = false;
  Timer? _timer;

  void _start() {
    setState(() => _down = true);
    widget.onPressed?.call();
    if (widget.repeat) {
      _timer = Timer(const Duration(milliseconds: 380), () {
        _timer = Timer.periodic(const Duration(milliseconds: 110), (_) {
          widget.onPressed?.call();
        });
      });
    }
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    if (mounted) setState(() => _down = false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final enabled = widget.onPressed != null;
    final base = widget.background ?? p.fill;
    final bg = !enabled
        ? base.withValues(alpha: base.a * 0.5)
        : _down
            ? Color.alphaBlend(p.fillPressed, base)
            : _hover
                ? Color.alphaBlend(p.fillHover, base)
                : base;
    final fg = widget.foreground ?? p.text;
    final radius = widget.radius ?? BorderRadius.circular(widget.size / 2);

    Widget content = widget.child ??
        Icon(widget.icon, size: widget.iconSize,
            color: enabled ? fg : fg.withValues(alpha: 0.4));

    final animMs = AppSettings.instance.animationDurationMs;
    final scaleDuration = animMs == 0
        ? Duration.zero
        : Duration(milliseconds: (animMs * 0.45).round());
    final containerDuration = animMs == 0
        ? Duration.zero
        : Duration(milliseconds: (animMs * 0.6).round());

    Widget btn = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) {
        setState(() => _hover = false);
        _stop();
      },
      child: Listener(
        onPointerDown: enabled ? (_) => _start() : null,
        onPointerUp: (_) => _stop(),
        onPointerCancel: (_) => _stop(),
        child: AnimatedScale(
          scale: _down ? 0.93 : 1,
          duration: scaleDuration,
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: containerDuration,
            width: widget.width ?? widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: radius,
              border: Border.all(color: p.stroke, width: 1),
            ),
            alignment: Alignment.center,
            child: IconTheme.merge(
              data: IconThemeData(color: fg),
              child: DefaultTextStyle.merge(
                style: TextStyle(color: fg),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
    if (widget.tooltip != null) {
      btn = Tooltip(message: widget.tooltip!, child: btn);
    }
    return Semantics(button: true, label: widget.tooltip, child: btn);
  }
}

/// Primary (accent) text button used in dialogs/flows.
class AccentButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  const AccentButton(
      {super.key, required this.label, this.onPressed, this.busy = false});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return PadButton(
      size: 40,
      width: double.infinity,
      radius: BorderRadius.circular(6),
      background: p.accent,
      foreground: p.onAccent,
      onPressed: busy ? null : onPressed,
      child: busy
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: p.onAccent),
            )
          : Text(label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
    );
  }
}

/// Subtle secondary text button.
class SubtleButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  const SubtleButton({super.key, required this.label, this.onPressed, this.icon});

  @override
  Widget build(BuildContext context) {
    return PadButton(
      size: 36,
      width: double.infinity,
      radius: BorderRadius.circular(6),
      onPressed: onPressed,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 8)],
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}
