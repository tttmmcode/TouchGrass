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
          const ModalBarrier(dismissible: false, color: Color(0x55000000)),
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
    final base =
        isDark ? const Color(0xFF2A3D30) : const Color(0xFFE0EDE5);
    final highlight =
        isDark ? const Color(0xFF3A5040) : const Color(0xFFF4FAF6);

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
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
              const Text('🌿', style: TextStyle(fontSize: 56)),
              const SizedBox(height: AppSpacing.xl),
              const SizedBox(
                width: 32,
                height: 32,
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
