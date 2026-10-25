// Pure helpers for composing TouchGrass's own in-app accessibility settings
// (Settings screen sliders/toggles) with the OS-level signals Flutter
// reports via MediaQuery — so enabling Reduce Motion, Dynamic Type, or
// Increase Contrast at the system level is always honored, whether or not
// the user has ever opened TouchGrass's own Settings screen.

/// Combines the OS's real text-scale factor with TouchGrass's own in-app
/// text-size preference by multiplying them.
///
/// When [appTextScale] is left at its default (1.0), this is a pure
/// passthrough of [systemTextScale] — the app never silently discards a
/// system Dynamic Type setting just because the user hasn't touched the
/// in-app slider. If the user *has* raised the in-app slider, it stacks on
/// top of whatever the system already reports.
double combinedTextScale({
  required double systemTextScale,
  required double appTextScale,
}) => systemTextScale * appTextScale;

/// True if either the OS-level "Reduce Motion" accessibility setting or
/// TouchGrass's own in-app Reduce Motion toggle is enabled. Motion should
/// stop for either reason — never require the user to configure both.
bool combinedReducedMotion({
  required bool systemReducedMotion,
  required bool appReducedMotion,
}) => systemReducedMotion || appReducedMotion;

/// True if either the OS-level "Increase Contrast" accessibility setting or
/// TouchGrass's own in-app high-contrast toggle is enabled.
bool combinedHighContrast({
  required bool systemHighContrast,
  required bool appHighContrast,
}) => systemHighContrast || appHighContrast;
