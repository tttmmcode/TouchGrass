import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

// ── LoadingOverlay ────────────────────────────────────────────────────────────

/// Wraps [child] and shows a modal loading card on top when [isLoading] is true.
/// The underlying content is dimmed and non-interactive while loading.
class LoadingOverlay extends StatelessWidget {
  const LoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
    this.message,
  });

  final bool isLoading;
  final Widget child;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading) ...[
          const ModalBarrier(dismissible: false, color: AppColors.overlayScrim),
          Center(
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              ),
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xxxl,
                  vertical: AppSpacing.xl,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      color: AppColors.forestGreen,
                      strokeWidth: 3,
                    ),
                    if (message != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        message!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ── LoadingCard ───────────────────────────────────────────────────────────────

/// Shimmer placeholder that mimics a content card while data is loading.
/// Use inside list views or wherever a card will eventually appear.
class LoadingCard extends StatelessWidget {
  const LoadingCard({
    super.key,
    this.height = 80,
    this.borderRadius = AppSpacing.radiusMd,
  });

  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Shimmer.fromColors(
      baseColor: AppColors.shimmerBase(isDark),
      highlightColor: AppColors.shimmerHighlight(isDark),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}

// ── ShimmerBox ────────────────────────────────────────────────────────────────

/// Theme-aware shimmer placeholder for a single shape (avatar, thumbnail,
/// or any other loading region) — the shared building block behind
/// [CachedNetworkImage]'s `placeholder` across the app, so every loading
/// avatar/photo shimmers with the same, dark-mode-correct colors.
class ShimmerBox extends StatelessWidget {
  const ShimmerBox({
    super.key,
    this.width,
    this.height,
    this.shape = BoxShape.rectangle,
    this.borderRadius,
  });

  final double? width;
  final double? height;
  final BoxShape shape;

  /// Ignored when [shape] is [BoxShape.circle].
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Shimmer.fromColors(
      baseColor: AppColors.shimmerBase(isDark),
      highlightColor: AppColors.shimmerHighlight(isDark),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          shape: shape,
          borderRadius: shape == BoxShape.circle ? null : borderRadius,
        ),
        child: SizedBox(width: width, height: height),
      ),
    );
  }
}

/// A column of [count] shimmer card placeholders with [spacing] between them.
class LoadingCardList extends StatelessWidget {
  const LoadingCardList({
    super.key,
    this.count = 4,
    this.cardHeight = 80,
    this.spacing = AppSpacing.sm,
  });

  final int count;
  final double cardHeight;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) SizedBox(height: spacing),
          LoadingCard(height: cardHeight),
        ],
      ],
    );
  }
}

// ── LoadingScreen ─────────────────────────────────────────────────────────────

/// Full-screen branded loading screen.
/// Use for initial auth checks, heavy data loads, or navigation transitions.
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({
    super.key,
    this.message = 'Loading your adventure...',
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🌿', style: TextStyle(fontSize: AppSpacing.emojiLogo)),
              const SizedBox(height: AppSpacing.xl),
              const SizedBox(
                width: AppSpacing.iconXl,
                height: AppSpacing.iconXl,
                child: CircularProgressIndicator(
                  color: AppColors.forestGreen,
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
