import 'package:flutter/material.dart';

/// Fallback avatar showing a user's initials on a colored background —
/// used wherever a profile photo is missing or still loading.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({
    super.key,
    required this.initials,
    required this.backgroundColor,
    this.textColor = Colors.white,
    this.fontSize = 22,
  });

  final String initials;
  final Color backgroundColor;
  final Color textColor;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: backgroundColor,
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            color: textColor,
          ),
        ),
      ),
    );
  }
}
