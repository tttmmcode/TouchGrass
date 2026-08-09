import 'package:flutter/material.dart';

import '../theme/app_motion.dart';

/// Layers the standard TouchGrass press micro-interaction (scale to
/// [AppMotion.pressedScale] over [AppMotion.pressDuration], springing back
/// on release) on top of an existing tappable widget, without touching its
/// own tap handling — uses [Listener] (raw pointer events) rather than
/// [GestureDetector] so it never competes with an [InkWell] inside [child]
/// for the gesture arena.
///
/// Use this for custom-styled buttons that can't adopt [AppButton] outright
/// (bespoke color/shape needed for brand or gameplay reasons) but should
/// still feel consistent with the rest of the app.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.enabled = true,
    this.scale = AppMotion.pressedScale,
  });

  final Widget child;
  final bool enabled;

  /// Target scale while pressed. Defaults to the standard button press
  /// ([AppMotion.pressedScale]); pass a different value for components with
  /// their own press spec (e.g. pathway nodes use 0.96).
  final double scale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: widget.enabled ? (_) => _setPressed(true) : null,
      onPointerUp: widget.enabled ? (_) => _setPressed(false) : null,
      onPointerCancel: widget.enabled ? (_) => _setPressed(false) : null,
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1.0,
        duration: AppMotion.pressDuration,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
