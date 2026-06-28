/// Spacing, sizing, and radius constants for the TouchGrass design system.
///
/// All values are multiples of 4dp — the base grid unit.
abstract final class AppSpacing {
  // ── Base spacing scale ────────────────────────────────────────────────────
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
  static const double xxxxl = 64;

  // ── Border radii ──────────────────────────────────────────────────────────
  static const double radiusXs = 4;
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 24;
  static const double radiusXxl = 32;
  /// Use for pill/badge shapes.
  static const double radiusFull = 999;

  // ── Screen edges ─────────────────────────────────────────────────────────
  static const double screenHorizontal = 20;
  static const double screenVertical = 16;

  // ── Component heights ─────────────────────────────────────────────────────
  static const double buttonHeight = 56;
  static const double buttonHeightSm = 44;
  static const double statsBarHeight = 56;
  static const double bottomNavHeight = 64;

  // ── Icon sizes ────────────────────────────────────────────────────────────
  static const double iconSm = 18;
  static const double iconMd = 24;
  static const double iconLg = 32;
  static const double iconXl = 48;

  // ── Avatar sizes ──────────────────────────────────────────────────────────
  static const double avatarSm = 36;
  static const double avatarMd = 48;
  static const double avatarLg = 64;
  static const double avatarXl = 96;

  // ── Challenge path ────────────────────────────────────────────────────────
  static const double challengeNodeSize = 72;
  static const double challengeNodeActiveSize = 88;
  static const double challengePathWidth = 4;
}
