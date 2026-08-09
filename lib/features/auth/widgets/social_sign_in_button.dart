import 'package:flutter/material.dart';

import '../../../theme/app_spacing.dart';
import '../../../widgets/push3d_button.dart';

/// A pressable social sign-in button with a Duolingo-style 3-D push animation.
///
/// Handles its own loading state — pass [isLoading] to show a spinner.
/// The button is disabled while loading to prevent double-taps.
class SocialSignInButton extends StatefulWidget {
  const SocialSignInButton({
    super.key,
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.shadowColor,
    required this.onPressed,
    this.isLoading = false,
    this.border,
  });

  final String label;
  final Widget icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color shadowColor;
  final VoidCallback? onPressed;
  final bool isLoading;
  final BoxBorder? border;

  @override
  State<SocialSignInButton> createState() => _SocialSignInButtonState();
}

class _SocialSignInButtonState extends State<SocialSignInButton> {
  @override
  Widget build(BuildContext context) {
    final disabled = widget.isLoading || widget.onPressed == null;

    return Push3DButton(
      onPressed: widget.onPressed,
      disabled: disabled,
      shadowColor: disabled
          ? widget.shadowColor.withValues(alpha: 0.5)
          : widget.shadowColor,
      face: _ButtonFace(
        label: widget.label,
        icon: widget.icon,
        backgroundColor: disabled
            ? widget.backgroundColor.withValues(alpha: 0.7)
            : widget.backgroundColor,
        foregroundColor: widget.foregroundColor,
        isLoading: widget.isLoading,
        border: widget.border,
      ),
    );
  }
}

class _ButtonFace extends StatelessWidget {
  const _ButtonFace({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.isLoading,
    this.border,
  });

  final String label;
  final Widget icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final bool isLoading;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
        border: border,
      ),
      child: SizedBox(
        height: AppSpacing.buttonHeight,
        child: Center(
          child: isLoading
              ? SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: foregroundColor,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icon,
                    const SizedBox(width: AppSpacing.md),
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: foregroundColor,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ── Pre-configured variants ─────────────────────────────────────────────────

class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    super.key,
    required this.onPressed,
    this.isLoading = false,
  });

  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SocialSignInButton(
      label: 'Continue with Google',
      icon: _GoogleIcon(),
      backgroundColor: Colors.white,
      foregroundColor: const Color(0xFF3C4043),
      shadowColor: const Color(0xFFDADADA),
      onPressed: onPressed,
      isLoading: isLoading,
      border: Border.all(color: const Color(0xFFDADADA), width: 1.5),
    );
  }
}

class AppleSignInButton extends StatelessWidget {
  const AppleSignInButton({
    super.key,
    required this.onPressed,
    this.isLoading = false,
  });

  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.white : Colors.black;
    final fg = isDark ? Colors.black : Colors.white;
    final shadow = isDark ? const Color(0xFFCCCCCC) : const Color(0xFF333333);

    return SocialSignInButton(
      label: 'Continue with Apple',
      icon: Icon(Icons.apple, color: fg, size: 22),
      backgroundColor: bg,
      foregroundColor: fg,
      shadowColor: shadow,
      onPressed: onPressed,
      isLoading: isLoading,
    );
  }
}

// ── Google "G" icon ─────────────────────────────────────────────────────────

class _GoogleIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(painter: _GoogleGPainter()),
    );
  }
}

/// Paints the Google "G" logo using the brand colour quadrants.
class _GoogleGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Clip to circle
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: radius)));

    final rect = Rect.fromCircle(center: center, radius: radius);

    // Google brand colours, positioned correctly:
    //   blue  → 12–3 o'clock (top-right)
    //   green → 3–6 o'clock  (bottom-right)
    //   yellow→ 6–9 o'clock  (bottom-left)
    //   red   → 9–12 o'clock (top-left)
    final paints = [
      (const Color(0xFF4285F4), -90.0, 90.0),  // blue  top-right
      (const Color(0xFF34A853), 0.0, 90.0),    // green bottom-right
      (const Color(0xFFFBBC05), 90.0, 90.0),   // yellow bottom-left
      (const Color(0xFFEA4335), 180.0, 90.0),  // red   top-left
    ];

    for (final (color, start, sweep) in paints) {
      canvas.drawArc(
        rect,
        _deg(start),
        _deg(sweep),
        true,
        Paint()..color = color,
      );
    }

    // White inner circle to create the ring shape
    canvas.drawCircle(center, radius * 0.62, Paint()..color = Colors.white);

    // Blue right notch (the horizontal bar of the G)
    final notchRect = Rect.fromLTWH(
      center.dx,
      center.dy - radius * 0.18,
      radius,
      radius * 0.36,
    );
    canvas.drawRect(notchRect, Paint()..color = const Color(0xFF4285F4));

    // White inner circle again to complete the G shape
    canvas.drawCircle(center, radius * 0.42, Paint()..color = Colors.white);
  }

  double _deg(double degrees) => degrees * 3.14159265 / 180;

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
