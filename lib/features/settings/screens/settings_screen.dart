import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/privacy_copy.dart';
import '../../../core/constants/support_contact.dart';
import '../../../core/services/error_service.dart';
import '../../../models/app_theme_mode.dart';
import '../../../models/challenge_model.dart';
import '../../../models/league_definition.dart';
import '../../../models/user_model.dart';
import '../../../providers/location_privacy_providers.dart';
import '../../../providers/memory_providers.dart';
import '../../../providers/settings_providers.dart';
import '../../../providers/user_providers.dart';
import '../../../repositories/feedback_repository.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_spacing.dart';
import '../../../widgets/error_retry_view.dart';
import '../../../widgets/initials_avatar.dart';
import '../../../widgets/legal_dialogs.dart';
import '../../../widgets/loading_widgets.dart';
import '../../../widgets/permission_primer.dart';
import '../widgets/account_deletion_progress.dart';
import '../widgets/remove_saved_locations.dart';

/// What to tell the user when picking a profile photo fails (audit D-20) —
/// most often because camera or photo access was denied. Never shows the
/// raw platform error.
@visibleForTesting
String profilePhotoPickErrorMessage(Object error) {
  final code = error is PlatformException ? error.code : '';
  if (code == 'camera_access_denied') {
    return "TouchGrass can't use your camera. You can allow camera access "
        'for TouchGrass in your device settings.';
  }
  if (code == 'photo_access_denied') {
    return "TouchGrass can't open your photos. You can allow photo access "
        'for TouchGrass in your device settings.';
  }
  return "Couldn't open that photo. Please try again.";
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _uploadingPhoto = false;

  /// True while `deleteAccount` runs: the screen is covered and can't be
  /// left, and a second deletion can't be started (Phase 7H).
  bool _deletingAccount = false;

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    final user = ref.watch(currentUserProvider).valueOrNull;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: !_deletingAccount,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Stack(
          children: [
            settingsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorRetryView(
                message: ErrorService.friendlyMessage(e),
                onRetry: () => ref.invalidate(settingsProvider),
              ),
              data: (settings) => ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenHorizontal,
                  0,
                  AppSpacing.screenHorizontal,
                  AppSpacing.xxxl,
                ),
                children: [
                  // ── Profile summary ────────────────────────────────────────────
                  const SizedBox(height: AppSpacing.md),
                  if (user != null) _ProfileSummary(user: user, isDark: isDark),
                  const SizedBox(height: AppSpacing.xxl),

                  // ── Account ────────────────────────────────────────────────────
                  _SectionLabel('Account', isDark: isDark),
                  const SizedBox(height: AppSpacing.sm),
                  _SettingsCard(
                    isDark: isDark,
                    children: [
                      _NavTile(
                        icon: Icons.person_outline_rounded,
                        iconColor: AppColors.grassGreen,
                        title: 'Edit Profile',
                        subtitle: 'Name, username',
                        isDark: isDark,
                        onTap: user != null
                            ? () => _editProfile(context, user)
                            : null,
                      ),
                      _Divider(isDark: isDark),
                      _NavTile(
                        icon: Icons.photo_camera_outlined,
                        iconColor: AppColors.grassGreen,
                        title: 'Change Profile Photo',
                        subtitle: _uploadingPhoto ? 'Uploading…' : null,
                        isDark: isDark,
                        trailing: _uploadingPhoto
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : null,
                        onTap: user != null && !_uploadingPhoto
                            ? () => _changeProfilePhoto(user.uid)
                            : null,
                      ),
                      if (user != null) ...[
                        _Divider(isDark: isDark),
                        _InfoTile(
                          icon: Icons.email_outlined,
                          label: 'Email',
                          value: user.email.isEmpty ? '—' : user.email,
                          isDark: isDark,
                        ),
                        _Divider(isDark: isDark),
                        _InfoTile(
                          icon: Icons.emoji_events_outlined,
                          label: 'League',
                          value: LeagueDef.forXp(user.xp).name,
                          isDark: isDark,
                        ),
                        _Divider(isDark: isDark),
                        _InfoTile(
                          icon: Icons.bolt_rounded,
                          label: 'Level / XP',
                          value:
                              'Lv.${AppConstants.levelForXp(user.xp)}  ·  ${user.xp} XP',
                          isDark: isDark,
                        ),
                        _Divider(isDark: isDark),
                        _InfoTile(
                          icon: Icons.calendar_today_outlined,
                          label: 'Member since',
                          value: _formatDate(user.createdAt),
                          isDark: isDark,
                        ),
                      ],
                      _Divider(isDark: isDark),
                      _ActionTile(
                        icon: Icons.logout_rounded,
                        iconColor: AppColors.error,
                        title: 'Sign Out',
                        titleColor: AppColors.error,
                        isDark: isDark,
                        onTap: () => _confirmSignOut(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxl),

                  // ── Appearance ─────────────────────────────────────────────────
                  _SectionLabel('Appearance', isDark: isDark),
                  const SizedBox(height: AppSpacing.sm),
                  _SettingsCard(
                    isDark: isDark,
                    children: [
                      _ThemeSelector(
                        current: settings.themeMode,
                        isDark: isDark,
                        onSelect: (mode) => ref
                            .read(settingsProvider.notifier)
                            .setThemeMode(mode),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxl),

                  // ── Notifications ──────────────────────────────────────────────
                  // Hidden while no reminders exist (Phase 8): these
                  // toggles controlled messages nothing sends.
                  if (AppConstants.remindersAvailable) ...[
                    _SectionLabel('Notifications', isDark: isDark),
                    const SizedBox(height: AppSpacing.sm),
                    _SettingsCard(
                      isDark: isDark,
                      children: [
                        SettingsToggleTile(
                          icon: Icons.wb_sunny_outlined,
                          iconColor: AppColors.grassGreen,
                          title: 'Daily Challenge',
                          subtitle: 'Remind me to complete today\'s challenge',
                          value: settings.dailyNotifications,
                          isDark: isDark,
                          onChanged: (_) => ref
                              .read(settingsProvider.notifier)
                              .toggleDailyNotifications(),
                        ),
                        _Divider(isDark: isDark),
                        SettingsToggleTile(
                          icon: Icons.local_fire_department_outlined,
                          iconColor: Colors.deepOrange,
                          title: 'Streak Alert',
                          subtitle: 'Warn me before my streak breaks',
                          value: settings.streakNotifications,
                          isDark: isDark,
                          onChanged: (_) => ref
                              .read(settingsProvider.notifier)
                              .toggleStreakNotifications(),
                        ),
                        _Divider(isDark: isDark),
                        SettingsToggleTile(
                          icon: Icons.emoji_events_outlined,
                          iconColor: const Color(0xFFFFB800),
                          title: 'League Ending Soon',
                          subtitle: 'Alert me when the weekly league resets',
                          value: settings.leagueNotifications,
                          isDark: isDark,
                          onChanged: (_) => ref
                              .read(settingsProvider.notifier)
                              .toggleLeagueNotifications(),
                        ),
                        _Divider(isDark: isDark),
                        SettingsToggleTile(
                          icon: Icons.stars_rounded,
                          iconColor: const Color(0xFF7B68EE),
                          title: 'Achievement Unlocked',
                          subtitle: 'Celebrate when I earn a new achievement',
                          value: settings.achievementNotifications,
                          isDark: isDark,
                          onChanged: (_) => ref
                              .read(settingsProvider.notifier)
                              .toggleAchievementNotifications(),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                  ],

                  // ── Streak Protection ──────────────────────────────────────────
                  _SectionLabel('Streak Protection', isDark: isDark),
                  const SizedBox(height: AppSpacing.sm),
                  _SettingsCard(
                    isDark: isDark,
                    children: [
                      _NavTile(
                        icon: Icons.ac_unit_rounded,
                        iconColor: const Color(0xFF42A5F5),
                        title: 'Streak Freezes',
                        subtitle: user != null
                            ? '${user.settings.streakFreezesOwned} owned  ·  ${AppConstants.streakFreezeCostXp} XP each'
                            : 'Protect your streak when you miss a day',
                        isDark: isDark,
                        onTap: user != null
                            ? () => _buyStreakFreeze(context, user, isDark)
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxl),

                  // ── Accessibility ──────────────────────────────────────────────
                  _SectionLabel('Accessibility', isDark: isDark),
                  const SizedBox(height: AppSpacing.sm),
                  _SettingsCard(
                    isDark: isDark,
                    children: [
                      _NavTile(
                        icon: Icons.text_fields_rounded,
                        iconColor: AppColors.forestGreen,
                        title: 'Text Size',
                        subtitle: _textSizeName(settings.textScale),
                        isDark: isDark,
                        onTap: () =>
                            _showTextSizeDialog(context, settings.textScale),
                      ),
                      _Divider(isDark: isDark),
                      SettingsToggleTile(
                        icon: Icons.animation_rounded,
                        iconColor: AppColors.forestGreen,
                        title: 'Reduce Motion',
                        subtitle: 'Minimise animations throughout the app',
                        value: settings.reducedMotion,
                        isDark: isDark,
                        onChanged: (_) => ref
                            .read(settingsProvider.notifier)
                            .toggleReducedMotion(),
                      ),
                      _Divider(isDark: isDark),
                      SettingsToggleTile(
                        icon: Icons.contrast_rounded,
                        iconColor: AppColors.forestGreen,
                        title: 'High Contrast',
                        subtitle: 'Increase contrast for better readability',
                        value: settings.highContrast,
                        isDark: isDark,
                        onChanged: (_) => ref
                            .read(settingsProvider.notifier)
                            .toggleHighContrast(),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxl),

                  // Leagues moved to the Leaderboard screen's "Leagues" tab — no
                  // longer a standalone Profile Settings destination (previously
                  // the only tile in a now-removed "Progress" section).

                  // ── Challenge preferences ──────────────────────────────────────
                  _SectionLabel('Challenge Preferences', isDark: isDark),
                  const SizedBox(height: AppSpacing.sm),
                  _SettingsCard(
                    isDark: isDark,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.md,
                          AppSpacing.lg,
                          AppSpacing.sm,
                        ),
                        child: Text(
                          'Pick the categories you want your daily challenges drawn '
                          'from. Leave none selected for a mix of everything.',
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppColors.onSurfaceVariantDark
                                : AppColors.onSurfaceVariantLight,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          0,
                          AppSpacing.lg,
                          AppSpacing.md,
                        ),
                        child: _CategoryPreferenceChips(
                          user: user,
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxl),

                  // ── Privacy ────────────────────────────────────────────────────
                  _SectionLabel('Privacy', isDark: isDark),
                  const SizedBox(height: AppSpacing.sm),
                  _SettingsCard(
                    isDark: isDark,
                    children: [
                      SettingsToggleTile(
                        icon: Icons.location_on_outlined,
                        iconColor: AppColors.forestGreen,
                        title: PrivacyCopy.locationSettingTitle,
                        subtitle: PrivacyCopy.locationSettingSubtitle(
                          enabled: user?.settings.locationEnabled ?? true,
                        ),
                        value: user?.settings.locationEnabled ?? true,
                        isDark: isDark,
                        onChanged: user != null
                            ? (val) => _setLocationEnabled(
                                context,
                                ref,
                                user.uid,
                                val,
                              )
                            : (_) {},
                      ),
                      _Divider(isDark: isDark),
                      _NavTile(
                        icon: Icons.location_off_outlined,
                        iconColor: AppColors.forestGreen,
                        title: PrivacyCopy.removeLocationsTitle,
                        subtitle: PrivacyCopy.removeLocationsSubtitle,
                        isDark: isDark,
                        onTap: user != null
                            ? () => confirmAndRemoveSavedLocations(
                                context,
                                uid: user.uid,
                                locationSettingOn:
                                    user.settings.locationEnabled,
                                repository: ref.read(
                                  locationHistoryRepositoryProvider,
                                ),
                                onChanged: () =>
                                    ref.invalidate(memoriesControllerProvider),
                              )
                            : null,
                      ),
                      _Divider(isDark: isDark),
                      SettingsToggleTile(
                        icon: Icons.leaderboard_outlined,
                        iconColor: AppColors.forestGreen,
                        title: 'Show on Leaderboard',
                        subtitle: 'Appear in league rankings',
                        value: user?.settings.profilePublic ?? true,
                        isDark: isDark,
                        onChanged: user != null
                            ? (val) => ref
                                  .read(userRepositoryProvider)
                                  .setProfilePublic(user.uid, val)
                            : (_) {},
                      ),
                      _Divider(isDark: isDark),
                      _NavTile(
                        icon: Icons.security_outlined,
                        iconColor: AppColors.forestGreen,
                        title: 'Manage Permissions',
                        subtitle: 'Camera, location, notifications',
                        isDark: isDark,
                        onTap: () => _managePermissions(context),
                      ),
                      _Divider(isDark: isDark),
                      _NavTile(
                        icon: Icons.copy_outlined,
                        iconColor: AppColors.forestGreen,
                        title: 'Export My Data',
                        // Accurate about what actually happens today: this copies
                        // a stats summary to the clipboard, not a downloaded file
                        // — it does not include photos or full challenge history.
                        // Don't promise a "download" the app doesn't perform.
                        subtitle:
                            'Copy a summary of your stats to your clipboard',
                        isDark: isDark,
                        onTap: user != null
                            ? () => _showDataExportDialog(context, user, isDark)
                            : null,
                      ),
                      _Divider(isDark: isDark),
                      _ActionTile(
                        icon: Icons.delete_forever_outlined,
                        iconColor: AppColors.error,
                        title: 'Delete Account',
                        titleColor: AppColors.error,
                        isDark: isDark,
                        onTap: () => _confirmDeleteAccount(context, isDark),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxl),

                  // ── Support ────────────────────────────────────────────────────
                  _SectionLabel('Support', isDark: isDark),
                  const SizedBox(height: AppSpacing.sm),
                  _SettingsCard(
                    isDark: isDark,
                    children: [
                      _NavTile(
                        icon: Icons.help_outline_rounded,
                        iconColor: AppColors.forestGreen,
                        title: 'Help & Support',
                        isDark: isDark,
                        onTap: () => _showHelpDialog(context, isDark),
                      ),
                      _Divider(isDark: isDark),
                      _NavTile(
                        icon: Icons.feedback_outlined,
                        iconColor: AppColors.forestGreen,
                        title: 'Send Feedback',
                        isDark: isDark,
                        onTap: () => _showFeedbackDialog(context, isDark),
                      ),
                      _Divider(isDark: isDark),
                      _NavTile(
                        icon: Icons.bug_report_outlined,
                        iconColor: AppColors.forestGreen,
                        title: 'Report a Bug',
                        isDark: isDark,
                        onTap: () => _showReportBugDialog(context, isDark),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxl),

                  // ── Legal ──────────────────────────────────────────────────────
                  _SectionLabel('Legal', isDark: isDark),
                  const SizedBox(height: AppSpacing.sm),
                  _SettingsCard(
                    isDark: isDark,
                    children: [
                      _NavTile(
                        icon: Icons.privacy_tip_outlined,
                        iconColor: AppColors.forestGreen,
                        title: 'Privacy Policy',
                        isDark: isDark,
                        onTap: () => showPrivacyPolicyDialog(context),
                      ),
                      _Divider(isDark: isDark),
                      _NavTile(
                        icon: Icons.gavel_rounded,
                        iconColor: AppColors.forestGreen,
                        title: 'Terms of Service',
                        isDark: isDark,
                        onTap: () => showTermsDialog(context),
                      ),
                      _Divider(isDark: isDark),
                      _NavTile(
                        icon: Icons.handshake_outlined,
                        iconColor: AppColors.forestGreen,
                        title: 'Community Guidelines',
                        isDark: isDark,
                        onTap: () =>
                            _showCommunityGuidelinesDialog(context, isDark),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxl),

                  // ── About ──────────────────────────────────────────────────────
                  _SectionLabel('About', isDark: isDark),
                  const SizedBox(height: AppSpacing.sm),
                  _SettingsCard(
                    isDark: isDark,
                    children: [
                      _NavTile(
                        icon: Icons.eco_outlined,
                        iconColor: AppColors.forestGreen,
                        title: 'About TouchGrass',
                        subtitle: 'Version 1.0.0',
                        isDark: isDark,
                        onTap: () => _showAbout(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_deletingAccount)
              const Positioned.fill(child: AccountDeletionProgress()),
          ],
        ),
      ),
    );
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _buyStreakFreeze(
    BuildContext context,
    UserModel user,
    bool isDark,
  ) async {
    final freezesOwned = user.settings.streakFreezesOwned;
    final hasEnoughXp = user.xp >= AppConstants.streakFreezeCostXp;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark
            ? AppColors.surfaceVariantDark
            : AppColors.surfaceLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        title: const Text(
          'Streak Freeze ❄️',
          style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A streak freeze protects your streak for one missed day. '
              'It activates automatically when you miss a day without completing a challenge.',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 14,
                color: isDark
                    ? AppColors.onSurfaceVariantDark
                    : AppColors.onSurfaceVariantLight,
              ),
            ),
            const SizedBox(height: 16),
            _FreezeInfoRow(
              label: 'You own',
              value: '$freezesOwned freeze${freezesOwned == 1 ? '' : 's'}',
            ),
            const _FreezeInfoRow(
              label: 'Cost',
              value: '${AppConstants.streakFreezeCostXp} XP',
            ),
            _FreezeInfoRow(label: 'Your XP', value: '${user.xp} XP'),
            if (!hasEnoughXp) ...[
              const SizedBox(height: 12),
              Text(
                'You need ${AppConstants.streakFreezeCostXp - user.xp} more XP to buy a freeze.',
                style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 13,
                  color: AppColors.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (hasEnoughXp)
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF42A5F5),
              ),
              child: const Text(
                'Buy Freeze',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final uid = ref.read(currentUserProvider).valueOrNull?.uid;
    if (uid == null) return;

    final result = await ref.read(userRepositoryProvider).buyStreakFreeze(uid);

    if (!mounted) return;
    result.when(
      ok: (_) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            '❄️ Streak freeze purchased!',
            style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w700),
          ),
          backgroundColor: const Color(0xFF42A5F5),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          margin: const EdgeInsets.all(AppSpacing.md),
        ),
      ),
      err: (e) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.message,
            style: const TextStyle(
              fontFamily: 'Nunito',
              fontWeight: FontWeight.w700,
            ),
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          margin: const EdgeInsets.all(AppSpacing.md),
        ),
      ),
    );
  }

  Future<void> _editProfile(BuildContext context, UserModel user) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark
        ? AppColors.surfaceVariantDark
        : AppColors.surfaceLight;
    final nameCtrl = TextEditingController(text: user.displayName);
    final usernameCtrl = TextEditingController(text: user.username);
    try {
      await _showEditProfileDialog(
        context,
        isDark,
        surface,
        nameCtrl,
        usernameCtrl,
        user,
      );
    } finally {
      nameCtrl.dispose();
      usernameCtrl.dispose();
    }
  }

  Future<void> _showEditProfileDialog(
    BuildContext context,
    bool isDark,
    Color surface,
    TextEditingController nameCtrl,
    TextEditingController usernameCtrl,
    UserModel user,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          String? usernameError;
          return AlertDialog(
            backgroundColor: surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
            ),
            title: const Text(
              'Edit Profile',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w900,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  maxLength: 32,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Display Name',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: usernameCtrl,
                  maxLength: 20,
                  decoration: InputDecoration(
                    labelText: 'Username',
                    counterText: '',
                    prefixText: '@',
                    errorText: usernameError,
                  ),
                  onChanged: (v) {
                    final valid = RegExp(r'^[a-z0-9_]*$').hasMatch(v);
                    setS(
                      () => usernameError = valid || v.isEmpty
                          ? null
                          : 'Only lowercase letters, numbers, underscores',
                    );
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w700,
                    color: AppColors.forestGreenLight,
                  ),
                ),
              ),
              TextButton(
                onPressed: usernameError != null
                    ? null
                    : () => Navigator.of(ctx).pop(true),
                child: const Text(
                  'Save',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w900,
                    color: AppColors.grassGreen,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    if (saved != true || !mounted) return;
    final newName = nameCtrl.text.trim();
    final newUsername = usernameCtrl.text.trim().toLowerCase();

    if (newName.isNotEmpty && newName != user.displayName) {
      await ref.read(userRepositoryProvider).updateUserFields(user.uid, {
        'displayName': newName,
      });
    }

    if (newUsername.isNotEmpty && newUsername != user.username) {
      final result = await ref
          .read(userRepositoryProvider)
          .updateUsername(
            uid: user.uid,
            currentUsername: user.username,
            newUsername: newUsername,
          );
      if (!mounted) return;
      result.onErr((e) => ErrorService.showError(context, e));
    }
  }

  Future<void> _changeProfilePhoto(String uid) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text(
                'Choose from Gallery',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.w700,
                ),
              ),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text(
                'Take a Photo',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.w700,
                ),
              ),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source == null || !mounted) return;

    // Explain before the OS camera prompt, as CameraScreen does (audit D-20).
    if (source == ImageSource.camera) {
      await maybeShowPermissionPrimer(context, PermissionPrimerKind.camera);
      if (!mounted) return;
    }

    final Uint8List bytes;
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 90,
      );
      if (picked == null || !mounted) return;
      bytes = await picked.readAsBytes();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(profilePhotoPickErrorMessage(e))),
        );
      }
      return;
    }
    if (!mounted) return;

    final croppedBytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute<Uint8List>(
        fullscreenDialog: true,
        builder: (_) => _CropScreen(imageBytes: bytes),
      ),
    );

    if (croppedBytes == null || !mounted) return;

    setState(() => _uploadingPhoto = true);
    final result = await ref
        .read(userRepositoryProvider)
        .uploadProfilePhoto(uid: uid, imageBytes: croppedBytes);
    if (!mounted) return;
    setState(() => _uploadingPhoto = false);
    result.when(
      ok: (_) {}, // stream update via currentUserProvider refreshes the UI
      err: (e) => ErrorService.showError(context, e),
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark
        ? AppColors.surfaceVariantDark
        : AppColors.surfaceLight;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        ),
        title: const Text(
          'Sign Out?',
          style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900),
        ),
        content: const Text(
          'Your progress is saved in the cloud — you can sign back in anytime.',
          style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w500),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w700,
                color: AppColors.forestGreenLight,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text(
              'Sign Out',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(settingsProvider.notifier).signOut();
    }
  }

  Future<void> _showTextSizeDialog(
    BuildContext context,
    double currentScale,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark
        ? AppColors.surfaceVariantDark
        : AppColors.surfaceLight;
    final textStrong = isDark
        ? AppColors.onSurfaceDark
        : AppColors.onSurfaceLight;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        ),
        title: Text(
          'Text Size',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontWeight: FontWeight.w900,
            color: textStrong,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in [
              (1.0, 'Normal'),
              (1.15, 'Large'),
              (1.3, 'Extra Large'),
            ])
              ListTile(
                title: Text(
                  option.$2,
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: textStrong,
                  ),
                ),
                trailing: currentScale == option.$1
                    ? const Icon(
                        Icons.check_rounded,
                        color: AppColors.grassGreen,
                        size: 20,
                      )
                    : null,
                onTap: () {
                  ref.read(settingsProvider.notifier).setTextScale(option.$1);
                  Navigator.of(ctx).pop();
                },
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Done',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w700,
                color: AppColors.forestGreenLight,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Turning optional location off is confirmed first, with exactly what
  /// stops working (audit D-09); turning it on needs no confirmation. The
  /// app never changes this setting on the user's behalf.
  Future<void> _setLocationEnabled(
    BuildContext context,
    WidgetRef ref,
    String uid,
    bool enabled,
  ) async {
    if (!enabled) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text(PrivacyCopy.locationOffDialogTitle),
          content: const SingleChildScrollView(
            child: Text(PrivacyCopy.locationOffEffects),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Keep on'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Turn off'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    final result = await ref.read(userRepositoryProvider).updateUserFields(
      uid,
      {'settings.locationEnabled': enabled},
    );
    if (result.isErr && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't update this setting. Please try again."),
        ),
      );
    }
  }

  Future<void> _confirmDeleteAccount(BuildContext context, bool isDark) async {
    final surface = isDark
        ? AppColors.surfaceVariantDark
        : AppColors.surfaceLight;

    // Step 1: Confirmation dialog.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        ),
        title: const Text(
          'Delete Account?',
          style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900),
        ),
        content: const Text(
          PrivacyCopy.deleteAccountWarning,
          style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w500),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w700,
                color: AppColors.forestGreenLight,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text(
              'Delete Forever',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted || _deletingAccount) return;

    final uid = ref.read(currentUserProvider).valueOrNull?.uid;
    if (uid == null) return;

    // Step 2: Determine provider so we know how to reauthenticate.
    final firebaseUser = ref.read(authServiceProvider).currentUser;
    final providerId = firebaseUser?.providerData.isNotEmpty == true
        ? firebaseUser!.providerData.first.providerId
        : null;
    final isEmailUser = providerId == 'password';

    // Step 3: For email users, collect their password before proceeding.
    String? password;
    if (isEmailUser) {
      password = await _showPasswordDialog(this.context, isDark);
      if (password == null || !mounted) return;
    }

    // Step 4: Re-authenticate, then the server-side deleteAccount function
    // removes all data and the Auth account (retry-safe). Success is only
    // reported once the server confirms everything is gone. The app-wide
    // messenger is captured first: on success, signing out replaces this
    // screen before the confirmation is shown.
    final messenger = ScaffoldMessenger.of(this.context);
    setState(() => _deletingAccount = true);
    final result = await ref
        .read(userRepositoryProvider)
        .deleteAccount(
          uid: uid,
          password:
              password, // null → Google/Apple reauth flow inside repository
          providerId: providerId,
        );

    if (mounted) setState(() => _deletingAccount = false);
    result.when(
      // GoRouter's redirect leaves this screen when auth state clears.
      ok: (_) => messenger
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text(PrivacyCopy.deleteAccountDone),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        ),
      err: (e) {
        if (mounted) ErrorService.showError(this.context, e);
      },
    );
  }

  Future<String?> _showPasswordDialog(BuildContext context, bool isDark) async {
    final surface = isDark
        ? AppColors.surfaceVariantDark
        : AppColors.surfaceLight;
    final controller = TextEditingController();

    try {
      return await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          ),
          title: const Text(
            'Confirm Password',
            style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter your password to confirm account deletion.',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Password'),
                onSubmitted: (v) => Navigator.of(ctx).pop(v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.w700,
                  color: AppColors.forestGreenLight,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text(
                'Delete Account',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _showHelpDialog(BuildContext context, bool isDark) async {
    final surface = isDark
        ? AppColors.surfaceVariantDark
        : AppColors.surfaceLight;
    final textStrong = isDark
        ? AppColors.onSurfaceDark
        : AppColors.onSurfaceLight;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        ),
        title: Text(
          'Help & Support',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontWeight: FontWeight.w900,
            color: textStrong,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HelpItem(
              title: 'How do I complete a challenge?',
              body:
                  'Tap the active lily pad on your home screen, then take a photo of your outdoor activity to complete it.',
              isDark: isDark,
            ),
            const SizedBox(height: 14),
            _HelpItem(
              title: 'Why did my streak reset?',
              body:
                  'Streaks reset if you miss a day. Complete at least one challenge per day to keep it alive.',
              isDark: isDark,
            ),
            const SizedBox(height: 14),
            _HelpItem(
              title: 'Contact us',
              body: SupportContact.contactLine,
              isDark: isDark,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Close',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w700,
                color: AppColors.forestGreenLight,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showFeedbackDialog(BuildContext context, bool isDark) async {
    await _showFeedbackForm(
      context: context,
      isDark: isDark,
      title: 'Send Feedback',
      hint: 'Feature ideas, general feedback, anything…',
      type: FeedbackType.feedback,
    );
  }

  Future<void> _showReportBugDialog(BuildContext context, bool isDark) async {
    await _showFeedbackForm(
      context: context,
      isDark: isDark,
      title: 'Report a Bug',
      hint: 'Describe what happened and how to reproduce it…',
      type: FeedbackType.bug,
    );
  }

  Future<void> _showFeedbackForm({
    required BuildContext context,
    required bool isDark,
    required String title,
    required String hint,
    required FeedbackType type,
  }) async {
    final surface = isDark
        ? AppColors.surfaceVariantDark
        : AppColors.surfaceLight;
    final textStrong = isDark
        ? AppColors.onSurfaceDark
        : AppColors.onSurfaceLight;
    final messenger = ScaffoldMessenger.of(context);
    final ctrl = TextEditingController();
    var submitting = false;

    final uid = ref.read(currentUserProvider).valueOrNull?.uid;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontWeight: FontWeight.w900,
              color: textStrong,
            ),
          ),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            // Rebuild so "Send" enables as soon as there's text (Phase 8:
            // without this it stayed disabled on desktop web, where no
            // keyboard inset change happens to rebuild the dialog).
            onChanged: (_) => setS(() {}),
            minLines: 4,
            maxLines: 8,
            maxLength: 1000,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w500,
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.of(ctx).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.w700,
                  color: AppColors.forestGreenLight,
                ),
              ),
            ),
            FilledButton(
              onPressed: submitting || ctrl.text.trim().isEmpty
                  ? null
                  : () async {
                      setS(() => submitting = true);
                      try {
                        (await ref
                                .read(feedbackRepositoryProvider)
                                .submit(
                                  userId: uid,
                                  type: type,
                                  message: ctrl.text,
                                ))
                            .valueOrThrow;
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              type == FeedbackType.bug
                                  ? '🐛 Bug report submitted — thank you!'
                                  : '💚 Feedback received — thank you!',
                              style: const TextStyle(
                                fontFamily: 'Nunito',
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            backgroundColor: AppColors.grassGreen,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusMd,
                              ),
                            ),
                            margin: const EdgeInsets.all(AppSpacing.md),
                          ),
                        );
                      } catch (e) {
                        setS(() => submitting = false);
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(ErrorService.friendlyMessage(e)),
                          ),
                        );
                      }
                    },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.grassGreen,
              ),
              child: submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Send',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
  }

  /// `openAppSettings()` has no web implementation — there's no OS-level
  /// settings screen to deep-link to in a browser. On web, permissions are
  /// managed per-site by the browser itself (address-bar padlock icon), so
  /// point the user there instead of calling into an unimplemented channel.
  Future<void> _managePermissions(BuildContext context) async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'On web, camera/location/notification permissions are managed '
            "by your browser — click the padlock icon in the address bar.",
          ),
        ),
      );
      return;
    }
    await openAppSettings();
  }

  Future<void> _showDataExportDialog(
    BuildContext context,
    UserModel user,
    bool isDark,
  ) async {
    final surface = isDark
        ? AppColors.surfaceVariantDark
        : AppColors.surfaceLight;
    final textStrong = isDark
        ? AppColors.onSurfaceDark
        : AppColors.onSurfaceLight;
    final textMuted = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;
    final messenger = ScaffoldMessenger.of(context);

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        ),
        title: Text(
          'Export My Data',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontWeight: FontWeight.w900,
            color: textStrong,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your export includes:',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: textStrong,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '• Display name and profile info\n'
              '• Total XP, level, and streak\n'
              '• Achievement list\n'
              '• Challenge completion count\n'
              '• Account creation date',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.6,
                color: textMuted,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w700,
                color: AppColors.forestGreenLight,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              final export =
                  'TouchGrass Data Export\n'
                  '======================\n'
                  'Name: ${user.displayName}\n'
                  'XP: ${user.xp}\n'
                  'Level: ${user.level}\n'
                  'Streak: ${user.streak} days\n'
                  'Completions: ${user.totalCompletions}\n'
                  'Achievements: ${user.achievements.length}\n'
                  'Member since: ${user.createdAt.toLocal().toString().split(' ').first}';
              Clipboard.setData(ClipboardData(text: export));
              Navigator.of(ctx).pop();
              messenger.showSnackBar(
                const SnackBar(content: Text('Data copied to clipboard')),
              );
            },
            child: const Text(
              'Copy to Clipboard',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w900,
                color: AppColors.grassGreen,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'TouchGrass',
      applicationVersion: '1.0.0',
      applicationIcon: const Text('🌿', style: TextStyle(fontSize: 36)),
      applicationLegalese: '© 2026 TouchGrass. All rights reserved.',
      children: [
        const SizedBox(height: 12),
        const Text(
          'TouchGrass helps you spend less time on screens and more time exploring the real world — one daily outdoor challenge at a time.',
          style: TextStyle(fontFamily: 'Nunito'),
        ),
      ],
    );
  }

  String _textSizeName(double scale) {
    if (scale <= 1.0) return 'Normal';
    if (scale <= 1.15) return 'Large';
    return 'Extra Large';
  }

  static String _formatDate(DateTime dt) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final local = dt.toLocal();
    return '${months[local.month - 1]} ${local.day}, ${local.year}';
  }

  Future<void> _showCommunityGuidelinesDialog(
    BuildContext context,
    bool isDark,
  ) async {
    final surface = isDark
        ? AppColors.surfaceVariantDark
        : AppColors.surfaceLight;
    final textStrong = isDark
        ? AppColors.onSurfaceDark
        : AppColors.onSurfaceLight;
    final textMuted = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        ),
        title: Text(
          'Community Guidelines',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontWeight: FontWeight.w900,
            color: textStrong,
          ),
        ),
        content: SingleChildScrollView(
          child: Text(
            'TouchGrass is a positive space for people who want to spend more time '
            'outdoors. To keep it that way, please follow these guidelines:\n\n'
            '1. Be genuine. Submit real photos of real outdoor activities. '
            'Manipulated or unrelated images undermine the community.\n\n'
            '2. Be respectful. Do not submit content that is offensive, '
            'discriminatory, or harmful to others.\n\n'
            '3. Stay safe. Do not trespass, endanger yourself, or perform '
            'illegal activities in pursuit of a challenge.\n\n'
            '4. Protect privacy. Do not photograph other people without their '
            'consent, especially minors.\n\n'
            '5. Keep it appropriate. All content must be suitable for a general '
            'audience. No graphic violence, nudity, or disturbing material.\n\n'
            '6. No spam. Do not submit duplicate completions or attempt to game '
            'the XP or streak systems.\n\n'
            'Violations may result in account suspension. We review reports '
            'promptly and take action to keep the community healthy.\n\n'
            'Last updated: June 2026',
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.55,
              color: textMuted,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Got it',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w700,
                color: AppColors.forestGreenLight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Help item ─────────────────────────────────────────────────────────────────

class _HelpItem extends StatelessWidget {
  const _HelpItem({
    required this.title,
    required this.body,
    required this.isDark,
  });
  final String title;
  final String body;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final textStrong = isDark
        ? AppColors.onSurfaceDark
        : AppColors.onSurfaceLight;
    final textMuted = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: textStrong,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          body,
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 12,
            fontWeight: FontWeight.w500,
            height: 1.4,
            color: textMuted,
          ),
        ),
      ],
    );
  }
}

// ── Freeze info row ───────────────────────────────────────────────────────────

class _FreezeInfoRow extends StatelessWidget {
  const _FreezeInfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textStrong = isDark
        ? AppColors.onSurfaceDark
        : AppColors.onSurfaceLight;
    final textMuted = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: textMuted,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: textStrong,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Profile summary ───────────────────────────────────────────────────────────

class _ProfileSummary extends StatelessWidget {
  const _ProfileSummary({required this.user, required this.isDark});
  final UserModel user;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final surface = isDark
        ? AppColors.surfaceVariantDark
        : AppColors.surfaceVariantLight;
    final strong = isDark ? AppColors.onSurfaceDark : AppColors.onSurfaceLight;
    final muted = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;

    final initials = user.displayName.isNotEmpty
        ? user.displayName[0].toUpperCase()
        : '?';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            SizedBox(
              width: 56,
              height: 56,
              child: ClipOval(
                child: user.photoUrl != null
                    ? CachedNetworkImage(
                        imageUrl: user.photoUrl!,
                        fit: BoxFit.cover,
                        placeholder: (ctx, url) => const ShimmerBox(),
                        errorWidget: (ctx, url, err) => InitialsAvatar(
                          initials: initials,
                          backgroundColor: AppColors.forestGreen,
                        ),
                      )
                    : InitialsAvatar(
                        initials: initials,
                        backgroundColor: AppColors.forestGreen,
                      ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.displayName,
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: strong,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        size: 13,
                        color: AppColors.achievementGold,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'Level ${user.level} · ${user.xp} XP',
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.isDark});
  final String text;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontFamily: 'Nunito',
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
        color: isDark
            ? AppColors.onSurfaceVariantDark
            : AppColors.onSurfaceVariantLight,
      ),
    );
  }
}

// ── Settings card ─────────────────────────────────────────────────────────────

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children, required this.isDark});
  final List<Widget> children;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final surface = isDark
        ? AppColors.surfaceVariantDark
        : AppColors.surfaceVariantLight;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Column(children: children),
    );
  }
}

// ── Divider ───────────────────────────────────────────────────────────────────

class _Divider extends StatelessWidget {
  const _Divider({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Divider(
        height: 1,
        thickness: 1,
        color: isDark ? AppColors.outlineDark : AppColors.outlineLight,
      ),
    );
  }
}

// ── Nav tile (navigates to sub-page or dialog) ────────────────────────────────

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.isDark,
    required this.onTap,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final bool isDark;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final strong = isDark ? AppColors.onSurfaceDark : AppColors.onSurfaceLight;
    final muted = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(7),
                  child: Icon(icon, size: 18, color: iconColor),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: strong,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: muted,
                        ),
                      ),
                  ],
                ),
              ),
              trailing ??
                  Icon(Icons.chevron_right_rounded, size: 20, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Toggle tile ───────────────────────────────────────────────────────────────

// ── Preferred-category selector ─────────────────────────────────────────────

/// Multi-select category chips backing [UserSettings.preferredCategories].
/// No categories selected means "no preference" — every category is
/// eligible for the daily challenge pool (see
/// ChallengeSeedLibrary.selectSeed's preferredCategories handling).
class _CategoryPreferenceChips extends ConsumerWidget {
  const _CategoryPreferenceChips({required this.user, required this.isDark});

  final UserModel? user;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = user?.settings.preferredCategories.toSet() ?? const {};

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final category in ChallengeCategory.values)
          _CategoryChip(
            category: category,
            isSelected: selected.contains(category.name),
            isDark: isDark,
            onTap: user == null
                ? null
                : () {
                    final next = selected.contains(category.name)
                        ? (selected..remove(category.name))
                        : (selected..add(category.name));
                    ref.read(userRepositoryProvider).updateUserFields(
                      user!.uid,
                      {'settings.preferredCategories': next.toList()},
                    );
                  },
          ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  final ChallengeCategory category;
  final bool isSelected;
  final bool isDark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = category.color;
    final unselectedBg = isDark
        ? AppColors.surfaceVariantDark
        : AppColors.surfaceVariantLight;
    final unselectedText = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;

    return Semantics(
      button: true,
      selected: isSelected,
      label:
          '${category.displayName} category, '
          '${isSelected ? "selected" : "not selected"}',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Material(
          color: isSelected ? color.withValues(alpha: 0.16) : unselectedBg,
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                border: Border.all(
                  color: isSelected ? color : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(category.emoji, style: const TextStyle(fontSize: 15)),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    category.displayName,
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? color : unselectedText,
                    ),
                  ),
                  if (isSelected) ...[
                    const SizedBox(width: AppSpacing.xs),
                    Icon(Icons.check_circle_rounded, size: 15, color: color),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A Settings row with a switch. The row is one accessibility node, so a
/// screen reader announces the switch with its title and subtitle (Phase 8:
/// the switch used to be announced with no name).
@visibleForTesting
class SettingsToggleTile extends StatelessWidget {
  const SettingsToggleTile({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.isDark,
    required this.onChanged,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final bool isDark;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final strong = isDark ? AppColors.onSurfaceDark : AppColors.onSurfaceLight;
    final muted = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;

    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Padding(
                padding: const EdgeInsets.all(7),
                child: Icon(icon, size: 18, color: iconColor),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: strong,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: muted,
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeThumbColor: AppColors.forestGreen,
              activeTrackColor: AppColors.forestGreen.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Photo crop screen ─────────────────────────────────────────────────────────

class _CropScreen extends StatefulWidget {
  const _CropScreen({required this.imageBytes});
  final Uint8List imageBytes;

  @override
  State<_CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<_CropScreen> {
  final _repaintKey = GlobalKey();
  final _transformCtrl = TransformationController();
  bool _saving = false;

  @override
  void dispose() {
    _transformCtrl.dispose();
    super.dispose();
  }

  Future<void> _usePhoto() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final boundary =
          _repaintKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (!mounted) return;
      Navigator.of(context).pop(byteData?.buffer.asUint8List());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const cropSize = 280.0;

    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text(
            'Cancel',
            style: TextStyle(
              fontFamily: 'Nunito',
              fontWeight: FontWeight.w700,
              color: Colors.white70,
            ),
          ),
        ),
        leadingWidth: 80,
        title: const Text(
          'Crop Photo',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _usePhoto,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.grassGreen,
                    ),
                  )
                : const Text(
                    'Use Photo',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontWeight: FontWeight.w900,
                      color: AppColors.grassGreen,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          const Spacer(),
          Center(
            child: SizedBox(
              width: cropSize,
              height: cropSize,
              child: Stack(
                children: [
                  RepaintBoundary(
                    key: _repaintKey,
                    child: ClipOval(
                      child: SizedBox(
                        width: cropSize,
                        height: cropSize,
                        child: InteractiveViewer(
                          transformationController: _transformCtrl,
                          minScale: 0.5,
                          maxScale: 5.0,
                          child: Image.memory(
                            widget.imageBytes,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                  IgnorePointer(
                    child: CustomPaint(
                      size: const Size(cropSize, cropSize),
                      painter: _CircleBorderPainter(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Pinch to zoom  ·  Drag to reposition',
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white38,
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _CircleBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width / 2 - 1,
      paint,
    );
  }

  @override
  bool shouldRepaint(_CircleBorderPainter oldDelegate) => false;
}

// ── Action tile (destructive or simple action, no chevron) ────────────────────

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.titleColor,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final Color titleColor;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(7),
                  child: Icon(icon, size: 18, color: iconColor),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: titleColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Theme selector (System / Light / Dark) ────────────────────────────────────

class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector({
    required this.current,
    required this.isDark,
    required this.onSelect,
  });

  final AppThemeMode current;
  final bool isDark;
  final ValueChanged<AppThemeMode> onSelect;

  static const _options = [
    (AppThemeMode.system, Icons.brightness_auto_rounded, 'System'),
    (AppThemeMode.light, Icons.light_mode_outlined, 'Light'),
    (AppThemeMode.dark, Icons.dark_mode_outlined, 'Dark'),
    (AppThemeMode.automatic, Icons.wb_twilight_rounded, 'Automatic'),
  ];

  static const _accent = Color(0xFF7B68EE);

  @override
  Widget build(BuildContext context) {
    final strong = isDark ? AppColors.onSurfaceDark : AppColors.onSurfaceLight;
    final muted = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(7),
                  child: Icon(Icons.palette_outlined, size: 18, color: _accent),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                'Theme',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: strong,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: _options.map((opt) {
              final isSelected = current == opt.$1;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Semantics(
                    button: true,
                    selected: isSelected,
                    label: '${opt.$3} theme${isSelected ? ', selected' : ''}',
                    excludeSemantics: true,
                    child: GestureDetector(
                      onTap: () => onSelect(opt.$1),
                      child: AnimatedContainer(
                        duration: AppMotion.fast,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? _accent.withValues(alpha: 0.13)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusMd,
                          ),
                          border: Border.all(
                            color: isSelected
                                ? _accent
                                : (isDark
                                      ? AppColors.outlineDark
                                      : AppColors.outlineLight),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              opt.$2,
                              size: 18,
                              color: isSelected ? _accent : muted,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              opt.$3,
                              style: TextStyle(
                                fontFamily: 'Nunito',
                                fontSize: 11,
                                fontWeight: isSelected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: isSelected ? _accent : muted,
                              ),
                            ),
                            // Non-color state cue (Part G) — border/accent
                            // alone isn't reliable for low-vision users.
                            const SizedBox(height: 2),
                            Icon(
                              isSelected
                                  ? Icons.check_circle_rounded
                                  : Icons.circle_outlined,
                              size: 12,
                              color: isSelected
                                  ? _accent
                                  : muted.withValues(alpha: 0.4),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ── Read-only info tile ───────────────────────────────────────────────────────

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final strong = isDark ? AppColors.onSurfaceDark : AppColors.onSurfaceLight;
    final muted = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.forestGreen.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: Icon(icon, size: 18, color: AppColors.forestGreen),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: strong,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
