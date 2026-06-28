import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/route_names.dart';
import '../providers/map_providers.dart';
import '../providers/notification_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// The root scaffold that wraps all main-tab screens.
///
/// Handles foreground notification banners and notification-tap navigation
/// in addition to the bottom nav bar.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  StreamSubscription<RemoteMessage>? _tapSub;

  @override
  void initState() {
    super.initState();
    // Terminated-state: app was launched by tapping a notification.
    _handleInitialMessage();
    // Background-state: user tapped notification while app was backgrounded.
    _tapSub = ref
        .read(notificationServiceProvider)
        .onTap
        .listen(_navigateFromMessage);
  }

  @override
  void dispose() {
    _tapSub?.cancel();
    super.dispose();
  }

  Future<void> _handleInitialMessage() async {
    final message =
        await ref.read(notificationServiceProvider).getInitialMessage();
    if (message != null && mounted) _navigateFromMessage(message);
  }

  void _navigateFromMessage(RemoteMessage message) {
    if (!mounted) return;
    // Senders may include a 'route' key in the data payload to deep-link.
    final route = message.data['route'] as String? ?? RouteNames.home;
    context.go(route);
  }

  void _onTabSelected(int index) {
    HapticFeedback.selectionClick();
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Kick off GPS resolution at app startup so location is ready by the time
    // the user navigates to the Map tab.
    ref.watch(currentLocationProvider);

    // Show an in-app banner for foreground messages (FCM suppresses the system
    // notification while the app is in the foreground on Android).
    ref.listen(foregroundMessageProvider, (_, next) {
      next.whenData((message) {
        final title = message.notification?.title ?? '';
        final body = message.notification?.body ?? '';
        if (title.isEmpty && body.isEmpty) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Text('🌿', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title.isNotEmpty)
                        Text(
                          title,
                          style: const TextStyle(
                            fontFamily: 'Nunito',
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                      if (body.isNotEmpty)
                        Text(
                          body,
                          style: const TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.forestGreen,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      });
    });

    return Scaffold(
      body: widget.navigationShell,
      bottomNavigationBar: _BottomNav(
        selectedIndex: widget.navigationShell.currentIndex,
        onDestinationSelected: _onTabSelected,
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: AppSpacing.bottomNavHeight,
          child: NavigationBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            elevation: 0,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.map_outlined),
                selectedIcon: Icon(Icons.map_rounded),
                label: 'Map',
              ),
              NavigationDestination(
                icon: Icon(Icons.leaderboard_outlined),
                selectedIcon: Icon(Icons.leaderboard_rounded),
                label: 'Ranks',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Profile',
              ),
              NavigationDestination(
                icon: Icon(Icons.emoji_events_outlined),
                selectedIcon: Icon(Icons.emoji_events_rounded),
                label: 'Badges',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
