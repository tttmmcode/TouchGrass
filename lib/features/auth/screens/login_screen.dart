import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../providers/settings_providers.dart';
import '../../../providers/user_providers.dart';
import '../../../services/analytics_service.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_spacing.dart';
import '../../../widgets/pressable_scale.dart';
import '../widgets/social_sign_in_button.dart';

// ── Root screen ───────────────────────────────────────────────────────────────

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  bool _showEmail = false;
  bool _googleLoading = false;
  bool _appleLoading = false;

  late final AnimationController _entryController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnim = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    );
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entryController,
            curve: const Interval(0.0, 0.8, curve: Curves.easeOutCubic),
          ),
        );
    _entryController.forward();
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  bool get _anyLoading => _googleLoading || _appleLoading;

  // defaultTargetPlatform reflects the browser's host OS on web (e.g. Safari
  // on an iPhone/Mac reports iOS/macOS there too), so it alone can't tell
  // native iOS/macOS apart from a web session — exclude web explicitly.
  // sign_in_with_apple's web flow needs a registered Service ID + redirect
  // URI this repo doesn't have configured, so the button stays hidden there.
  bool get _showAppleButton =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  Future<void> _signInWithGoogle() async {
    if (_anyLoading) return;
    setState(() => _googleLoading = true);
    final result = await ref.read(userRepositoryProvider).signInWithGoogle();
    if (!mounted) return;
    setState(() => _googleLoading = false);
    result
      ..onOk((user) {
        final isNew = DateTime.now().difference(user.createdAt).inMinutes < 5;
        if (isNew) {
          AnalyticsService.logSignUp('google');
        } else {
          AnalyticsService.logSignIn('google');
        }
      })
      ..onErr(_showError);
  }

  Future<void> _signInWithApple() async {
    if (_anyLoading) return;
    setState(() => _appleLoading = true);
    final result = await ref.read(userRepositoryProvider).signInWithApple();
    if (!mounted) return;
    setState(() => _appleLoading = false);
    result
      ..onOk((user) {
        final isNew = DateTime.now().difference(user.createdAt).inMinutes < 5;
        if (isNew) {
          AnalyticsService.logSignUp('apple');
        } else {
          AnalyticsService.logSignIn('apple');
        }
      })
      ..onErr(_showError);
  }

  void _showError(Object error) {
    if (!mounted) return;
    // The user dismissing a native sign-in sheet is a normal action, not a
    // failure — don't alarm them with a red error for their own cancellation.
    if (error is AuthException && error.isCancellation) return;
    final message = error is AppException ? error.message : 'Sign-in failed.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            fontFamily: 'Nunito',
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        margin: const EdgeInsets.all(AppSpacing.md),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Gradient background ──────────────────────────────────────────
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.forestGreenDark,
                  AppColors.forestGreen,
                  AppColors.forestGreenLight,
                ],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
          ),

          // ── Leaf pattern overlay ──────────────────────────────────────────
          Positioned.fill(
            child: Opacity(
              opacity: 0.04,
              child: CustomPaint(painter: _LeafPatternPainter()),
            ),
          ),

          // ── Scrollable content ────────────────────────────────────────────
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenHorizontal,
              ),
              child: Column(
                children: [
                  const SizedBox(height: AppSpacing.xxl),
                  FadeTransition(
                    opacity: _fadeAnim,
                    child: SlideTransition(
                      position: _slideAnim,
                      child: const _HeroSection(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  FadeTransition(
                    opacity: _fadeAnim,
                    child: SlideTransition(
                      position: _slideAnim,
                      child: AnimatedSwitcher(
                        duration: AppMotion.standard,
                        switchInCurve: AppMotion.standardCurve,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.06),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        child: _showEmail
                            ? _EmailAuthForm(
                                key: const ValueKey('email'),
                                onBack: () =>
                                    setState(() => _showEmail = false),
                                onError: _showError,
                              )
                            : _SocialSection(
                                key: const ValueKey('social'),
                                googleLoading: _googleLoading,
                                appleLoading: _appleLoading,
                                anyLoading: _anyLoading,
                                showApple: _showAppleButton,
                                onGoogle: _signInWithGoogle,
                                onApple: _signInWithApple,
                                onEmailTap: () =>
                                    setState(() => _showEmail = true),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  FadeTransition(opacity: _fadeAnim, child: const _TermsText()),
                  const SizedBox(height: AppSpacing.xxl),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Hero section ──────────────────────────────────────────────────────────────

class _HeroSection extends ConsumerStatefulWidget {
  const _HeroSection();

  @override
  ConsumerState<_HeroSection> createState() => _HeroSectionState();
}

class _HeroSectionState extends ConsumerState<_HeroSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _float;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _float = Tween<Offset>(
      begin: const Offset(0, -0.035),
      end: const Offset(0, 0.035),
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    // Continuous ambient loop — never runs when Reduce Motion is on.
    if (!ref.read(reducedMotionProvider)) _ctrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SlideTransition(
          position: _float,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Text(
                '🌿',
                style: TextStyle(fontSize: AppSpacing.emojiLogo),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        const Text(
          'TouchGrass',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 42,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: -1,
            height: 1.1,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Go outside. Explore the world. Earn XP.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.75),
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        const Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _FeaturePill(emoji: '🎯', label: 'Daily challenges'),
            _FeaturePill(emoji: '🔥', label: 'Build streaks'),
            _FeaturePill(emoji: '⭐', label: 'Earn XP'),
          ],
        ),
      ],
    );
  }
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill({required this.emoji, required this.label});
  final String emoji;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Social sign-in section ────────────────────────────────────────────────────

class _SocialSection extends StatelessWidget {
  const _SocialSection({
    super.key,
    required this.googleLoading,
    required this.appleLoading,
    required this.anyLoading,
    required this.showApple,
    required this.onGoogle,
    required this.onApple,
    required this.onEmailTap,
  });

  final bool googleLoading;
  final bool appleLoading;
  final bool anyLoading;
  final bool showApple;
  final VoidCallback onGoogle;
  final VoidCallback onApple;
  final VoidCallback onEmailTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GoogleSignInButton(
          onPressed: anyLoading ? null : onGoogle,
          isLoading: googleLoading,
        ),
        if (showApple) ...[
          const SizedBox(height: AppSpacing.md),
          AppleSignInButton(
            onPressed: anyLoading ? null : onApple,
            isLoading: appleLoading,
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: Divider(
                color: Colors.white.withValues(alpha: 0.25),
                thickness: 1,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Text(
                'or',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ),
            Expanded(
              child: Divider(
                color: Colors.white.withValues(alpha: 0.25),
                thickness: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        PressableScale(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.25),
                width: AppSpacing.strokeRegular,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
              child: InkWell(
                onTap: onEmailTap,
                borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
                splashColor: Colors.white.withValues(alpha: 0.15),
                highlightColor: Colors.white.withValues(alpha: 0.08),
                child: const SizedBox(
                  height: AppSpacing.buttonHeight,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.email_outlined,
                        color: Colors.white,
                        size: AppSpacing.iconSm,
                      ),
                      SizedBox(width: AppSpacing.md),
                      Text(
                        'Continue with Email',
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Email auth form ───────────────────────────────────────────────────────────

enum _EmailMode { signIn, signUp }

class _EmailAuthForm extends ConsumerStatefulWidget {
  const _EmailAuthForm({
    super.key,
    required this.onBack,
    required this.onError,
  });

  final VoidCallback onBack;
  final void Function(Object) onError;

  @override
  ConsumerState<_EmailAuthForm> createState() => _EmailAuthFormState();
}

class _EmailAuthFormState extends ConsumerState<_EmailAuthForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  _EmailMode _mode = _EmailMode.signIn;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isLoading = true);

    final repo = ref.read(userRepositoryProvider);
    final result = _mode == _EmailMode.signUp
        ? await repo.signUpWithEmail(
            email: _emailCtrl.text,
            password: _passwordCtrl.text,
            displayName: _nameCtrl.text.trim().isNotEmpty
                ? _nameCtrl.text.trim()
                : null,
          )
        : await repo.signInWithEmail(
            email: _emailCtrl.text,
            password: _passwordCtrl.text,
          );

    if (!mounted) return;
    setState(() => _isLoading = false);
    final isSignUp = _mode == _EmailMode.signUp;
    result
      ..onOk(
        (_) => isSignUp
            ? AnalyticsService.logSignUp('email')
            : AnalyticsService.logSignIn('email'),
      )
      ..onErr(widget.onError);
  }

  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      widget.onError(
        const DataException(message: 'Enter your email address first.'),
      );
      return;
    }
    setState(() => _isLoading = true);
    final result = await ref
        .read(userRepositoryProvider)
        .sendPasswordResetEmail(email);
    if (!mounted) return;
    setState(() => _isLoading = false);
    result.when(
      ok: (_) => _showMessage('Password reset email sent to $email'),
      err: widget.onError,
    );
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(
            fontFamily: 'Nunito',
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: AppColors.forestGreenDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        margin: const EdgeInsets.all(AppSpacing.md),
      ),
    );
  }

  static final BorderRadius _kFieldRadius = BorderRadius.circular(
    AppSpacing.radiusTextField,
  );

  InputDecoration _fieldDeco(String hint, IconData icon, {Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        fontFamily: 'Nunito',
        fontSize: 14,
        color: Colors.white.withValues(alpha: 0.45),
      ),
      prefixIcon: Icon(
        icon,
        color: Colors.white.withValues(alpha: 0.6),
        size: AppSpacing.iconSm,
      ),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: _kFieldRadius,
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: _kFieldRadius,
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: _kFieldRadius,
        borderSide: const BorderSide(color: Colors.white, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: _kFieldRadius,
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: _kFieldRadius,
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
      errorStyle: const TextStyle(
        fontFamily: 'Nunito',
        fontSize: 12,
        color: AppColors.error,
      ),
    );
  }

  Widget _eyeToggle(bool obscure, VoidCallback onToggle) => IconButton(
    icon: Icon(
      obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
      color: Colors.white.withValues(alpha: 0.55),
      size: AppSpacing.iconSm,
    ),
    tooltip: obscure ? 'Show password' : 'Hide password',
    onPressed: onToggle,
  );

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header row: back button + mode label
          Row(
            children: [
              Semantics(
                button: true,
                label: 'Back to sign-in options',
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: _isLoading ? null : widget.onBack,
                  // Visual badge stays 36x36; the tap target itself is
                  // padded out to the 48x48 minimum around it.
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    child: Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(AppSpacing.sm),
                          child: Icon(
                            Icons.arrow_back_rounded,
                            color: Colors.white,
                            size: AppSpacing.iconSm,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              AnimatedSwitcher(
                duration: AppMotion.fast,
                child: Text(
                  _mode == _EmailMode.signIn ? 'Sign In' : 'Create Account',
                  key: ValueKey(_mode),
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // Name field — sign-up only
          AnimatedSize(
            duration: AppMotion.standard,
            curve: Curves.easeOut,
            child: _mode == _EmailMode.signUp
                ? Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: TextFormField(
                      controller: _nameCtrl,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'Nunito',
                      ),
                      decoration: _fieldDeco(
                        'Your name',
                        Icons.person_outline_rounded,
                      ),
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.name],
                      onFieldSubmitted: (_) =>
                          FocusScope.of(context).nextFocus(),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Name is required';
                        }
                        if (v.trim().length < 2) {
                          return 'Must be at least 2 characters';
                        }
                        return null;
                      },
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          // Email field
          TextFormField(
            controller: _emailCtrl,
            style: const TextStyle(color: Colors.white, fontFamily: 'Nunito'),
            decoration: _fieldDeco('Email address', Icons.email_outlined),
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Email is required';
              if (!v.contains('@') || !v.contains('.')) {
                return 'Enter a valid email address';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.sm),

          // Password field
          TextFormField(
            controller: _passwordCtrl,
            style: const TextStyle(color: Colors.white, fontFamily: 'Nunito'),
            obscureText: _obscurePassword,
            decoration: _fieldDeco(
              'Password',
              Icons.lock_outline_rounded,
              suffix: _eyeToggle(
                _obscurePassword,
                () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            textInputAction: _mode == _EmailMode.signUp
                ? TextInputAction.next
                : TextInputAction.done,
            autofillHints: [
              _mode == _EmailMode.signUp
                  ? AutofillHints.newPassword
                  : AutofillHints.password,
            ],
            onFieldSubmitted: (_) => _mode == _EmailMode.signUp
                ? FocusScope.of(context).nextFocus()
                : _submit(),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Password is required';
              if (v.length < 6) return 'Must be at least 6 characters';
              return null;
            },
          ),

          // Confirm password — sign-up only
          AnimatedSize(
            duration: AppMotion.standard,
            curve: Curves.easeOut,
            child: _mode == _EmailMode.signUp
                ? Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: TextFormField(
                      controller: _confirmCtrl,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'Nunito',
                      ),
                      obscureText: _obscureConfirm,
                      decoration: _fieldDeco(
                        'Confirm password',
                        Icons.lock_outline_rounded,
                        suffix: _eyeToggle(
                          _obscureConfirm,
                          () => setState(
                            () => _obscureConfirm = !_obscureConfirm,
                          ),
                        ),
                      ),
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.newPassword],
                      onFieldSubmitted: (_) => _submit(),
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return 'Please confirm your password';
                        }
                        if (v != _passwordCtrl.text) {
                          return 'Passwords do not match';
                        }
                        return null;
                      },
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          const SizedBox(height: AppSpacing.lg),

          // Submit button
          PressableScale(
            enabled: !_isLoading,
            child: SizedBox(
              height: AppSpacing.buttonHeight,
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
                elevation: 2,
                shadowColor: Colors.black26,
                child: InkWell(
                  onTap: _isLoading ? null : _submit,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
                  child: Center(
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: AppColors.forestGreen,
                              strokeWidth: 2.5,
                            ),
                          )
                        : AnimatedSwitcher(
                            duration: AppMotion.fast,
                            child: Text(
                              _mode == _EmailMode.signIn
                                  ? 'Sign In'
                                  : 'Create Account',
                              key: ValueKey(_mode),
                              style: const TextStyle(
                                fontFamily: 'Nunito',
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: AppColors.forestGreen,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Bottom action row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (_mode == _EmailMode.signIn)
                TextButton(
                  onPressed: _isLoading ? null : _forgotPassword,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white.withValues(alpha: 0.65),
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Forgot password?',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                const SizedBox.shrink(),
              TextButton(
                onPressed: _isLoading
                    ? null
                    : () => setState(() {
                        _mode = _mode == _EmailMode.signIn
                            ? _EmailMode.signUp
                            : _EmailMode.signIn;
                        _formKey.currentState?.reset();
                        _passwordCtrl.clear();
                        _confirmCtrl.clear();
                      }),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: AnimatedSwitcher(
                  duration: AppMotion.fast,
                  child: Text(
                    _mode == _EmailMode.signIn
                        ? 'Create account →'
                        : '← Sign in instead',
                    key: ValueKey(_mode),
                    style: const TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Terms text ────────────────────────────────────────────────────────────────

class _TermsText extends StatelessWidget {
  const _TermsText();

  @override
  Widget build(BuildContext context) {
    return Text(
      'By continuing, you agree to our Terms of Service\nand Privacy Policy.',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: 'Nunito',
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: Colors.white.withValues(alpha: 0.45),
        height: 1.5,
      ),
    );
  }
}

// ── Background painter ────────────────────────────────────────────────────────

class _LeafPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    const spacing = 80.0;
    final cols = (size.width / spacing).ceil() + 1;
    final rows = (size.height / spacing).ceil() + 1;

    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final x = col * spacing + (row.isOdd ? spacing / 2 : 0);
        final y = row * spacing;
        _drawLeaf(canvas, paint, Offset(x, y), 8);
      }
    }
  }

  void _drawLeaf(Canvas canvas, Paint paint, Offset center, double size) {
    final path = Path()
      ..moveTo(center.dx, center.dy - size)
      ..quadraticBezierTo(
        center.dx + size,
        center.dy,
        center.dx,
        center.dy + size,
      )
      ..quadraticBezierTo(
        center.dx - size,
        center.dy,
        center.dx,
        center.dy - size,
      );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
