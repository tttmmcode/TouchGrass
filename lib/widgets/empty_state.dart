import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Reusable empty-state widget: graphic + title + description + optional action.
///
/// Usage:
/// ```dart
/// EmptyState(
///   graphic: const Text('🏆', style: TextStyle(fontSize: 48)),
///   title: 'Your first badge is waiting.',
///   description: 'Complete daily challenges to unlock achievements.',
///   actionLabel: 'Start today\'s challenge',
///   onAction: () => context.go(RouteNames.home),
/// )
/// ```
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.graphic,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });

  /// The visual focal point — typically a Text emoji, Icon, or small image.
  final Widget graphic;

  /// Short declarative headline. Example: "Your first badge is waiting."
  final String title;

  /// One or two sentences of context. Example: "Complete daily challenges to
  /// unlock achievements and level up."
  final String description;

  /// Label for the primary CTA button. Omit if no action is available.
  final String? actionLabel;

  /// Called when the primary CTA button is pressed.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxxl,
        vertical: AppSpacing.xl,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // ── Graphic ─────────────────────────────────────────────────────────
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Center(child: graphic),
          ),

          const SizedBox(height: AppSpacing.xl),

          // ── Title ────────────────────────────────────────────────────────────
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: AppSpacing.sm),

          // ── Description ──────────────────────────────────────────────────────
          Text(
            description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),

          // ── Primary action ───────────────────────────────────────────────────
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.xl),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
