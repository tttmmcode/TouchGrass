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
    return const SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

/// Paints Google's official multi-color "G" mark, transcribed directly from
/// the path data in Google's own Identity Services "Continue with Google"
/// button markup (48x48 viewBox, four solid paths — no approximation, no
/// external asset to go missing). Renders identically at any size/DPI since
/// it's vector, not raster — supersedes the earlier plan to drop in a PNG
/// asset file (`assets/icons/google_logo.png`, never actually supplied).
class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  // Source viewBox is 0 0 48 48 — paths below are given in that space and
  // scaled to the actual widget size in [paint].
  static const _viewBoxSize = 48.0;

  static final _red = Path()
    ..moveTo(24, 9.5)
    ..cubicTo(27.54, 9.5, 30.71, 10.72, 33.21, 13.1)
    ..lineTo(40.06, 6.25)
    ..cubicTo(35.9, 2.38, 30.47, 0, 24, 0)
    ..cubicTo(14.62, 0, 6.51, 5.38, 2.56, 13.22)
    ..lineTo(10.54, 19.41)
    ..cubicTo(12.43, 13.72, 17.74, 9.5, 24, 9.5)
    ..close();

  static final _blue = Path()
    ..moveTo(46.98, 24.55)
    ..cubicTo(46.98, 22.98, 46.83, 21.46, 46.6, 20.0)
    ..lineTo(24, 20.0)
    ..lineTo(24, 29.02)
    ..lineTo(36.94, 29.02)
    ..cubicTo(36.36, 31.98, 34.68, 34.5, 32.16, 36.2)
    ..lineTo(39.89, 42.2)
    ..cubicTo(44.4, 38.02, 46.98, 31.84, 46.98, 24.55)
    ..close();

  static final _yellow = Path()
    ..moveTo(10.53, 28.59)
    ..cubicTo(10.05, 27.14, 9.77, 25.6, 9.77, 24.0)
    ..cubicTo(9.77, 22.4, 10.04, 20.86, 10.53, 19.41)
    ..lineTo(2.55, 13.22)
    ..cubicTo(0.92, 16.46, 0, 20.12, 0, 24)
    ..cubicTo(0, 27.88, 0.92, 31.54, 2.56, 34.78)
    ..lineTo(10.53, 28.59)
    ..close();

  static final _green = Path()
    ..moveTo(24, 48)
    ..cubicTo(30.48, 48, 35.93, 45.87, 39.89, 42.19)
    ..lineTo(32.16, 36.19)
    ..cubicTo(30.01, 37.64, 27.24, 38.49, 24.0, 38.49)
    ..cubicTo(17.74, 38.49, 12.43, 34.27, 10.53, 28.58)
    ..lineTo(2.55, 34.77)
    ..cubicTo(6.51, 42.62, 14.62, 48, 24, 48)
    ..close();

  static final _paths = [
    (_red, const Color(0xFFEA4335)),
    (_blue, const Color(0xFF4285F4)),
    (_yellow, const Color(0xFFFBBC05)),
    (_green, const Color(0xFF34A853)),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _viewBoxSize;
    canvas.save();
    canvas.scale(scale);
    for (final (path, color) in _paths) {
      canvas.drawPath(path, Paint()..color = color);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
