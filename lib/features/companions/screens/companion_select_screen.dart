import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../companions/companion.dart';
import '../../../companions/companion_widget.dart';
import '../../../providers/companion_providers.dart';
import '../../../providers/user_providers.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';

class CompanionSelectScreen extends ConsumerStatefulWidget {
  const CompanionSelectScreen({super.key});

  @override
  ConsumerState<CompanionSelectScreen> createState() =>
      _CompanionSelectScreenState();
}

class _CompanionSelectScreenState extends ConsumerState<CompanionSelectScreen> {
  CompanionType? _saving;

  Future<void> _select(CompanionType type) async {
    if (_saving != null) return;
    final uid = ref.read(currentUserProvider).valueOrNull?.uid;
    if (uid == null) return;

    unawaited(HapticFeedback.selectionClick());
    setState(() => _saving = type);

    await ref.read(userRepositoryProvider).updateCompanionType(
          uid: uid,
          companionType: type.name,
        );

    if (!mounted) return;
    setState(() => _saving = null);

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeCompanionProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Choose Your Companion',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontWeight: FontWeight.w900,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenHorizontal,
                vertical: AppSpacing.sm,
              ),
              child: Text(
                'Your companion cheers you on after every challenge.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? AppColors.onSurfaceDark.withValues(alpha: 0.6)
                      : AppColors.onSurfaceLight.withValues(alpha: 0.55),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenHorizontal,
                  vertical: AppSpacing.sm,
                ),
                mainAxisSpacing: AppSpacing.md,
                crossAxisSpacing: AppSpacing.md,
                childAspectRatio: 0.82,
                children: CompanionType.values
                    .map(
                      (type) => _CompanionCard(
                        type: type,
                        isSelected: type == active,
                        isSaving: _saving == type,
                        onTap: () => _select(type),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}

// ── Companion card ────────────────────────────────────────────────────────────

class _CompanionCard extends StatelessWidget {
  const _CompanionCard({
    required this.type,
    required this.isSelected,
    required this.isSaving,
    required this.onTap,
  });

  final CompanionType type;
  final bool isSelected;
  final bool isSaving;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = type.primaryColor;
    final borderColor = isSelected ? primary : Colors.transparent;
    final bgColor = isDark
        ? AppColors.surfaceDark
        : AppColors.surfaceLight;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(
            color: borderColor,
            width: isSelected ? 2.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: primary.withValues(alpha: 0.30),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.md,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CompanionView(
                    type: type,
                    mood: isSelected ? CompanionMood.bounce : CompanionMood.idle,
                    size: 88,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    type.displayName,
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: isDark
                          ? AppColors.onSurfaceDark
                          : AppColors.onSurfaceLight,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    type.tagline,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? AppColors.onSurfaceDark.withValues(alpha: 0.55)
                          : AppColors.onSurfaceLight.withValues(alpha: 0.50),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            // Selected checkmark
            if (isSelected)
              Positioned(
                top: 10,
                right: 10,
                child: AnimatedScale(
                  scale: isSelected ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(3),
                      child: Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
                ),
              ),
            // Saving spinner
            if (isSaving)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
