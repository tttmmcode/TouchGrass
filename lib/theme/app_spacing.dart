/// Spacing, sizing, and radius constants for the TouchGrass design system.
///
/// All values are multiples of 4dp — the base grid unit.
abstract final class AppSpacing {
  // ── Base spacing scale ────────────────────────────────────────────────────
  // Semantic usage: xs between icon+text, sm between related controls,
  // md inside cards, lg between cards, xl between sections, xxl large
  // section spacing, xxxl major screen separation, xxxxl large screen
  // padding. betweenCards/heroSpacing fill the two extra steps (20, 40)
  // the base 4/8/12/16/24/32/48/64 progression skips.
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double betweenCards = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double majorScreen = 40;
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

  // Component-specific radii called out by the design system — prefer these
  // named tokens over the generic scale above when styling that component,
  // even where the value happens to coincide with an existing step.
  static const double radiusButton = 16;
  static const double radiusCard = 20;
  static const double radiusDialog = 24;
  static const double radiusBottomSheet = 28;
  static const double radiusTextField = 16;
  static const double radiusBadge = 12;

  // ── Screen edges ─────────────────────────────────────────────────────────
  static const double screenHorizontal = 20;
  static const double screenVertical = 16;

  // ── Component heights ─────────────────────────────────────────────────────
  static const double buttonHeight = 56;
  static const double buttonHeightSm = 44;
  static const double statsBarHeight = 56;
  static const double bottomNavHeight = 64;
  static const double textFieldHeight = 56;

  // ── Icon sizes ────────────────────────────────────────────────────────────
  static const double iconTiny = 16;
  static const double iconSm = 20;
  static const double iconMd = 24;
  static const double iconLg = 28;
  static const double iconXl = 32;

  /// "Big emoji glyph" display sizes — achievement/streak/level/companion
  /// screens render emoji as oversized `Text`, which needs its own scale
  /// distinct from icon sizes since it's measured in font-size, not box size.
  static const double emojiSm = 20;
  static const double emojiMd = 32;
  static const double emojiLg = 48;
  static const double emojiXl = 72;

  /// Shared splash/loading-screen wordmark glyph size.
  static const double emojiLogo = 56;

  // ── Avatar sizes ──────────────────────────────────────────────────────────
  static const double avatarSm = 36;
  static const double avatarMd = 48;
  static const double avatarLg = 64;
  static const double avatarXl = 96;

  // ── Stroke widths ─────────────────────────────────────────────────────────
  static const double strokeThin = 1.0;
  static const double strokeRegular = 1.5;
  static const double strokeThick = 2.0;

  // ── Challenge path ────────────────────────────────────────────────────────
  static const double challengeNodeSize = 72;
  static const double challengeNodeActiveSize = 88;
  static const double challengePathWidth = 4;
}
