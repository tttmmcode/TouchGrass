import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Shared "3D push" press interaction — a Duolingo-style depth press where
/// the button face's bottom padding collapses to 0 on tap-down, simulating
/// it lifting off a colored shadow layer, and springs back on release.
///
/// This is a deliberately different feel from [PressableScale]'s uniform
/// scale-down; used by CTA/social-sign-in buttons that want that specific
/// tactile character. Consolidates what used to be two near-identical
/// hand-rolled implementations (onboarding CTA, social sign-in buttons).
class Push3DButton extends StatefulWidget {
  const Push3DButton({
    super.key,
    required this.face,
    required this.shadowColor,
    this.onPressed,
    this.disabled = false,
    this.depth = 5,
    this.borderRadius,
  });

  /// The button's visible content (background, label, icon, etc.).
  final Widget face;

  /// Color of the "shadow" layer the face appears to lift off of.
  final Color shadowColor;
  final VoidCallback? onPressed;
  final bool disabled;
  final double depth;
  final BorderRadius? borderRadius;

  @override
  State<Push3DButton> createState() => _Push3DButtonState();
}

class _Push3DButtonState extends State<Push3DButton> {
  bool _pressed = false;

  bool get _enabled => !widget.disabled && widget.onPressed != null;

  @override
  Widget build(BuildContext context) {
    final radius =
        widget.borderRadius ?? BorderRadius.circular(AppSpacing.radiusButton);

    return GestureDetector(
      onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: _enabled
          ? (_) {
              setState(() => _pressed = false);
              widget.onPressed?.call();
            }
          : null,
      onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(
          bottom: (_pressed || !_enabled) ? 0 : widget.depth,
        ),
        decoration: BoxDecoration(color: widget.shadowColor, borderRadius: radius),
        child: widget.face,
      ),
    );
  }
}
