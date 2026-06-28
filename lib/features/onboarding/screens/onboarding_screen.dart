import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../companions/companion.dart';
import '../../../companions/companion_widget.dart';
import '../../../core/constants/route_names.dart';
import '../../../providers/auth_providers.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';

/// Three-page onboarding shown to new users immediately after sign-in.
///
/// Navigates to [RouteNames.home] on completion. There is no back
/// navigation — users should not be able to return here after completing it.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  static const _pages = [
    _OnboardingPage(
      emoji: '🌿',
      title: 'Welcome to\nTouchGrass',
      subtitle:
          'The app that turns going outside into an adventure. Complete daily challenges, earn XP, and explore the world around you.',
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [AppColors.forestGreenDark, AppColors.forestGreen],
      ),
    ),
    _OnboardingPage(
      emoji: '📸',
      title: 'Complete\ndaily challenges',
      subtitle:
          'Each day you\'ll receive a new nature challenge. Head outside, snap a photo, and our AI will verify your completion.',
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [AppColors.forestGreen, AppColors.grassGreen],
      ),
    ),
    _OnboardingPage(
      emoji: '🔥',
      title: 'Build your\nstreak & level up',
      subtitle:
          'Earn XP for every challenge you complete. Maintain your streak, unlock achievements, and track your exploration on the map.',
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [AppColors.grassGreen, AppColors.forestGreenLight],
      ),
    ),
  ];

  bool get _isLastPage => _currentPage == _pages.length - 1;

  String get _firstName {
    final name = FirebaseAuth.instance.currentUser?.displayName ?? '';
    return name.split(' ').first;
  }

  /// Persists the onboarding-complete flag to SharedPreferences and updates
  /// the router provider so the redirect never sends this user to /onboarding
  /// again.
  Future<void> _markComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kOnboardingCompleteKey, true);
    ref.read(onboardingCompleteProvider.notifier).state = true;
  }

  Future<void> _nextPage() async {
    if (_isLastPage) {
      await _markComplete();
      if (!mounted) return;
      context.go(RouteNames.home);
      return;
    }
    await _pageController.nextPage(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ── Animated page content ──────────────────────────────────────
          PageView.builder(
            controller: _pageController,
            onPageChanged: (index) => setState(() => _currentPage = index),
            itemCount: _pages.length,
            itemBuilder: (context, index) {
              return _PageContent(
                page: _pages[index],
                firstName: index == 0 ? _firstName : null,
                showCompanion: index == 0,
              );
            },
          ),

          // ── Bottom controls overlay ────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenHorizontal,
                  0,
                  AppSpacing.screenHorizontal,
                  AppSpacing.xxl,
                ),
                child: Column(
                  children: [
                    // Page indicator dots
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        _pages.length,
                        (i) => AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs,
                          ),
                          width: i == _currentPage ? 24 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: i == _currentPage
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusFull,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    // CTA button
                    _OnboardingButton(
                      label: _isLastPage
                          ? "Let's go! 🚀"
                          : 'Continue',
                      onPressed: _nextPage,
                    ),

                    // Skip on non-final pages
                    if (!_isLastPage) ...[
                      const SizedBox(height: AppSpacing.md),
                      TextButton(
                        onPressed: () async {
                          await _markComplete();
                          if (!context.mounted) return;
                          context.go(RouteNames.home);
                        },
                        child: Text(
                          'Skip',
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Page content ──────────────────────────────────────────────────────────────

class _OnboardingPage {
  const _OnboardingPage({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.gradient,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final LinearGradient gradient;
}

class _PageContent extends StatefulWidget {
  const _PageContent({
    required this.page,
    this.firstName,
    this.showCompanion = false,
  });

  final _OnboardingPage page;
  final String? firstName;
  final bool showCompanion;

  @override
  State<_PageContent> createState() => _PageContentState();
}

class _PageContentState extends State<_PageContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _float;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _float = Tween<Offset>(
      begin: const Offset(0, -0.04),
      end: const Offset(0, 0.04),
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final greeting = (widget.firstName?.isNotEmpty ?? false)
        ? 'Hi ${widget.firstName}! 👋'
        : null;

    return DecoratedBox(
      decoration: BoxDecoration(gradient: widget.page.gradient),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenHorizontal,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),

              // Illustration — companion on page 1, emoji on others
              SlideTransition(
                position: _float,
                child: widget.showCompanion
                    ? const CompanionView(
                        type: CompanionType.sprout,
                        mood: CompanionMood.wave,
                        size: 140,
                        message: "Hi! I'm Sprout 🌱 Let's explore!",
                      )
                    : DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xxl),
                          child: Text(
                            widget.page.emoji,
                            style: const TextStyle(fontSize: 72),
                          ),
                        ),
                      ),
              ),

              const SizedBox(height: AppSpacing.xxxl),

              // Optional personal greeting
              if (greeting != null) ...[
                Text(
                  greeting,
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],

              // Title
              Text(
                widget.page.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1.15,
                  letterSpacing: -0.5,
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              // Subtitle
              Text(
                widget.page.subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.78),
                  height: 1.55,
                ),
              ),

              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
}

// ── CTA button ────────────────────────────────────────────────────────────────

class _OnboardingButton extends StatefulWidget {
  const _OnboardingButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  State<_OnboardingButton> createState() => _OnboardingButtonState();
}

class _OnboardingButtonState extends State<_OnboardingButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onPressed();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        padding: EdgeInsets.only(bottom: _pressed ? 0 : 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: SizedBox(
            height: AppSpacing.buttonHeight,
            child: Center(
              child: Text(
                widget.label,
                style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: AppColors.forestGreen,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
