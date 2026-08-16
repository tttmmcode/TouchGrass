import 'dart:async';
import 'package:camera/camera.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../companions/companion.dart';
import '../../../companions/companion_widget.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/route_names.dart';
import '../../../core/utils/image_compression.dart';
import '../../../models/achievement_definition.dart';
import '../../../models/challenge_model.dart';
import '../../../models/league_definition.dart';
import '../../../providers/camera_providers.dart';
import '../../../providers/challenge_providers.dart';
import '../../../providers/map_providers.dart';
import '../../../providers/settings_providers.dart';
import '../../../services/perf_service.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_spacing.dart';
import '../../../widgets/permission_primer.dart';
import '../../../widgets/pressable_scale.dart';
import '../utils/celebration_utils.dart';

// ── Root ─────────────────────────────────────────────────────────────────────

class CameraScreen extends ConsumerWidget {
  const CameraScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flowState = ref.watch(cameraFlowProvider);
    final challenge = ref.watch(todaysChallengeProvider).valueOrNull;

    return switch (flowState) {
      CameraSuccess() => _SuccessView(state: flowState),
      CameraVerifying() => _VerifyingView(state: flowState),
      CameraCaptionStep() => _CaptionView(state: flowState),
      CameraImagePicked() => _PreviewView(state: flowState),
      CameraLive() => const _LiveCameraView(),
      CameraIdle() => _IdleView(challenge: challenge),
      CameraFailure() => _FailureView(state: flowState),
    };
  }
}

// ── Idle ─────────────────────────────────────────────────────────────────────

class _IdleView extends ConsumerWidget {
  const _IdleView({required this.challenge});
  final ChallengeModel? challenge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final notifier = ref.read(cameraFlowProvider.notifier);

    if (challenge != null && challenge!.isCompleted) {
      return _AlreadyCompletedView(challenge: challenge!);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete Challenge'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.go(RouteNames.home),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (challenge != null) _ChallengeInfoCard(challenge: challenge!),
              const Spacer(),
              _PickButton(
                icon: Icons.camera_alt_rounded,
                label: 'Use Camera',
                onTap: notifier.startLiveCamera,
                isDark: isDark,
                primary: true,
              ),
              const SizedBox(height: AppSpacing.md),
              _PickButton(
                icon: Icons.photo_library_rounded,
                label: 'Choose from Gallery',
                onTap: () => notifier.pickImage(ImageSource.gallery),
                isDark: isDark,
                primary: false,
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

/// Friendly recovery state for direct/deep-link camera entry after today's
/// challenge is already completed (the normal Home flow never shows the
/// camera pick buttons in this case, but a stale screen or manual route
/// could still land here — this avoids letting the user redo the flow only
/// to be rejected at final submission).
class _AlreadyCompletedView extends StatelessWidget {
  const _AlreadyCompletedView({required this.challenge});
  final ChallengeModel challenge;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete Challenge'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.go(RouteNames.home),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(challenge.emoji, style: const TextStyle(fontSize: 64)),
              const SizedBox(height: AppSpacing.lg),
              const Text(
                "You've already completed today's challenge!",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Nice work on "${challenge.title}". Come back tomorrow for a new adventure.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              PressableScale(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AppColors.gradientForest,
                    borderRadius: BorderRadius.circular(
                      AppSpacing.radiusButton,
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => context.go(RouteNames.home),
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusButton,
                      ),
                      child: const SizedBox(
                        height: AppSpacing.buttonHeight,
                        child: Center(
                          child: Text(
                            'Back to Home',
                            style: TextStyle(
                              fontFamily: 'Nunito',
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChallengeInfoCard extends StatelessWidget {
  const _ChallengeInfoCard({required this.challenge});
  final ChallengeModel challenge;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppColors.gradientForest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(challenge.emoji, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Day ${challenge.dayNumber}',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white.withValues(alpha: 0.65),
                    letterSpacing: 1.2,
                  ),
                ),
                const Spacer(),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: Text(
                      '${challenge.xpReward} XP',
                      style: const TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              challenge.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              challenge.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
            if (challenge.objective.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Icon(
                    Icons.flag_rounded,
                    size: 13,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      challenge.objective,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PickButton extends StatelessWidget {
  const _PickButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isDark,
    required this.primary,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDark;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    if (primary) {
      return PressableScale(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: AppColors.gradientForest,
            borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
            boxShadow: [
              BoxShadow(
                color: AppColors.forestGreen.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
              child: SizedBox(
                height: AppSpacing.buttonHeight,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: Colors.white, size: AppSpacing.iconSm),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      label,
                      style: const TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final borderColor = isDark ? AppColors.outlineDark : AppColors.outlineLight;
    final textColor = isDark
        ? AppColors.onSurfaceDark
        : AppColors.onSurfaceLight;

    return PressableScale(
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: borderColor,
            width: AppSpacing.strokeRegular,
          ),
          borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
            child: SizedBox(
              height: AppSpacing.buttonHeight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: textColor, size: AppSpacing.iconSm),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Live camera ───────────────────────────────────────────────────────────────

class _LiveCameraView extends ConsumerStatefulWidget {
  const _LiveCameraView();

  @override
  ConsumerState<_LiveCameraView> createState() => _LiveCameraViewState();
}

class _LiveCameraViewState extends ConsumerState<_LiveCameraView>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _initialized = false;
  bool _capturing = false;
  String? _error;
  bool _permDenied = false;
  bool _permPermanentlyDenied = false;
  bool _isRearCamera = true;
  FlashMode _flashMode = FlashMode.off;
  Offset? _focusPoint;
  final _launchTrace = PerfService.startTrace(PerfService.traceCameraLaunch);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requestAndInit();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // If the user backed out to system Settings to grant camera permission
    // (from the denied/permanently-denied screen) and returns, re-check
    // rather than leaving them stuck on the "Camera Access Required" screen.
    if (state == AppLifecycleState.resumed &&
        !_initialized &&
        (_permDenied || _permPermanentlyDenied)) {
      setState(() {
        _permDenied = false;
        _permPermanentlyDenied = false;
      });
      _requestAndInit();
    }
  }

  Future<void> _requestAndInit() async {
    // permission_handler has no web implementation — on web the browser's
    // own getUserMedia prompt (triggered by CameraController.initialize()
    // inside _initCamera) is the only permission gate, and _initCamera
    // already turns a user's browser-level denial into the same
    // "Could not open camera" error state.
    if (kIsWeb) {
      await _initCamera();
      return;
    }

    // No-ops after the very first call (see maybeShowPermissionPrimer) — safe
    // to call unconditionally here, including on the resume-after-Settings
    // retry path in didChangeAppLifecycleState.
    await maybeShowPermissionPrimer(context, PermissionPrimerKind.camera);
    if (!mounted) return;

    final status = await Permission.camera.request();
    if (!mounted) return;

    if (status.isPermanentlyDenied) {
      setState(() => _permPermanentlyDenied = true);
      return;
    }
    if (status.isDenied || status.isRestricted) {
      setState(() => _permDenied = true);
      return;
    }
    await _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (!mounted) return;
        setState(() => _error = 'No camera found on this device.');
        return;
      }
      final desired = _isRearCamera
          ? CameraLensDirection.back
          : CameraLensDirection.front;
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == desired,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        // Medium preset: manageable file size (~720p) while preserving quality
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      await _launchTrace?.stop();
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _initialized = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not open camera. Please try again.');
    }
  }

  Future<void> _switchCamera() async {
    if (!_initialized) return;
    setState(() {
      _initialized = false;
      _isRearCamera = !_isRearCamera;
    });
    await _controller?.dispose();
    _controller = null;
    await _initCamera();
  }

  static const _flashCycle = [FlashMode.off, FlashMode.auto, FlashMode.always];

  Future<void> _toggleFlash() async {
    final next =
        _flashCycle[(_flashCycle.indexOf(_flashMode) + 1) % _flashCycle.length];
    try {
      await _controller?.setFlashMode(next);
    } catch (_) {}
    setState(() => _flashMode = next);
  }

  Future<void> _onTapFocus(TapUpDetails details) async {
    final ctrl = _controller;
    if (ctrl == null || !_initialized) return;
    final screenSize = MediaQuery.sizeOf(context);
    final x = (details.localPosition.dx / screenSize.width).clamp(0.0, 1.0);
    final y = (details.localPosition.dy / screenSize.height).clamp(0.0, 1.0);
    setState(() => _focusPoint = details.localPosition);
    try {
      await ctrl.setFocusPoint(Offset(x, y));
      await ctrl.setExposurePoint(Offset(x, y));
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (mounted) setState(() => _focusPoint = null);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final ctrl = _controller;
    if (ctrl == null || !_initialized || _capturing) return;
    unawaited(HapticFeedback.mediumImpact());
    setState(() => _capturing = true);
    try {
      final file = await ctrl.takePicture();
      final rawBytes = await file.readAsBytes();
      final bytes = await compressJpeg(rawBytes);
      if (!mounted) return;
      ref.read(cameraFlowProvider.notifier).setBytes(bytes);
    } catch (_) {
      if (!mounted) return;
      setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(cameraFlowProvider.notifier);

    // ── Permission: permanently denied ──
    if (_permPermanentlyDenied) {
      return _PermissionDeniedView(permanent: true, onBack: notifier.reset);
    }

    // ── Permission: denied (can re-request) ──
    if (_permDenied) {
      return _PermissionDeniedView(
        permanent: false,
        onRetry: () {
          setState(() => _permDenied = false);
          _requestAndInit();
        },
        onBack: notifier.reset,
      );
    }

    // ── Camera error ──
    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.camera_alt_outlined,
                  color: Colors.white54,
                  size: 64,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  _error!,
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 15,
                    color: Colors.white70,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xl),
                TextButton(
                  onPressed: notifier.reset,
                  child: const Text(
                    'Go Back',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ── Camera initializing ──
    if (!_initialized || _controller == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 20),
              Text(
                'Opening camera…',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white60,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ── Live camera view ──
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Live preview + tap-to-focus
          GestureDetector(
            onTapUp: _onTapFocus,
            behavior: HitTestBehavior.opaque,
            child: CameraPreview(_controller!),
          ),

          // Focus square
          if (_focusPoint != null)
            Positioned(
              left: _focusPoint!.dx - 30,
              top: _focusPoint!.dy - 30,
              child: IgnorePointer(child: _FocusSquare()),
            ),

          // ── Top bar: close · flash ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Material(
                      color: Colors.black54,
                      shape: const CircleBorder(),
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: notifier.reset,
                        tooltip: 'Close',
                      ),
                    ),
                    Material(
                      color: Colors.black54,
                      shape: const CircleBorder(),
                      child: IconButton(
                        icon: Icon(
                          switch (_flashMode) {
                            FlashMode.auto => Icons.flash_auto_rounded,
                            FlashMode.off => Icons.flash_off_rounded,
                            _ => Icons.flash_on_rounded,
                          },
                          color: _flashMode == FlashMode.off
                              ? Colors.white
                              : Colors.amber,
                        ),
                        onPressed: _toggleFlash,
                        tooltip: switch (_flashMode) {
                          FlashMode.auto => 'Flash auto',
                          FlashMode.off => 'Flash off',
                          _ => 'Flash on',
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Bottom bar: gallery · shutter · flip ──
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 36),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Gallery
                    Material(
                      color: Colors.black54,
                      shape: const CircleBorder(),
                      child: InkWell(
                        onTap: () => ref
                            .read(cameraFlowProvider.notifier)
                            .pickImage(ImageSource.gallery),
                        customBorder: const CircleBorder(),
                        child: Semantics(
                          button: true,
                          label: 'Choose photo from gallery',
                          child: const SizedBox(
                            width: 48,
                            height: 48,
                            child: Icon(
                              Icons.photo_library_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Shutter
                    Semantics(
                      button: true,
                      label: _capturing ? 'Capturing photo' : 'Take photo',
                      child: GestureDetector(
                        onTap: _capturing ? null : _capture,
                        child: _ShutterButton(capturing: _capturing),
                      ),
                    ),

                    // Flip camera
                    Material(
                      color: Colors.black54,
                      shape: const CircleBorder(),
                      child: InkWell(
                        onTap: _switchCamera,
                        customBorder: const CircleBorder(),
                        child: Semantics(
                          button: true,
                          label: 'Switch camera',
                          child: const SizedBox(
                            width: 48,
                            height: 48,
                            child: Icon(
                              Icons.flip_camera_ios_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ),
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

// ── Shutter button ────────────────────────────────────────────────────────────

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.capturing});
  final bool capturing;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: capturing ? 0.88 : 1.0,
      duration: const Duration(milliseconds: 100),
      child: SizedBox(
        width: 76,
        height: 76,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: capturing
                ? const CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  )
                : const DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: SizedBox.expand(),
                  ),
          ),
        ),
      ),
    );
  }
}

// ── Animated focus square ─────────────────────────────────────────────────────

class _FocusSquare extends StatefulWidget {
  @override
  State<_FocusSquare> createState() => _FocusSquareState();
}

class _FocusSquareState extends State<_FocusSquare>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fade = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: const Interval(0.5, 1.0)));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: Colors.yellowAccent.withValues(alpha: 0.9),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(2),
        ),
        child: const SizedBox(width: 60, height: 60),
      ),
    );
  }
}

// ── Permission denied ─────────────────────────────────────────────────────────

class _PermissionDeniedView extends StatelessWidget {
  const _PermissionDeniedView({
    required this.permanent,
    this.onRetry,
    required this.onBack,
  });

  final bool permanent;
  final VoidCallback? onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.camera_alt_outlined,
                color: Colors.white54,
                size: 64,
              ),
              const SizedBox(height: AppSpacing.xl),
              const Text(
                'Camera Access Required',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                permanent
                    ? 'Camera access was permanently denied. Open Settings to allow TouchGrass to access your camera.'
                    : 'TouchGrass needs camera access to verify your outdoor adventures. Please allow camera access to continue.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white70,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: AppSpacing.xxxl),
              if (permanent)
                PressableScale(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppColors.gradientForest,
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusButton,
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: openAppSettings,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusButton,
                        ),
                        child: const SizedBox(
                          height: AppSpacing.buttonHeight,
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.settings_rounded,
                                  color: Colors.white,
                                  size: AppSpacing.iconSm,
                                ),
                                SizedBox(width: AppSpacing.sm),
                                Text(
                                  'Open Settings',
                                  style: TextStyle(
                                    fontFamily: 'Nunito',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
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
                )
              else
                PressableScale(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppColors.gradientForest,
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusButton,
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: onRetry,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusButton,
                        ),
                        child: const SizedBox(
                          height: AppSpacing.buttonHeight,
                          child: Center(
                            child: Text(
                              'Allow Camera Access',
                              style: TextStyle(
                                fontFamily: 'Nunito',
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              TextButton(
                onPressed: onBack,
                child: const Text(
                  'Go Back',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w700,
                    color: Colors.white54,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Preview ───────────────────────────────────────────────────────────────────

class _PreviewView extends ConsumerWidget {
  const _PreviewView({required this.state});
  final CameraImagePicked state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(cameraFlowProvider.notifier);
    final challenge = ref.watch(todaysChallengeProvider).valueOrNull;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Full-screen photo
          Image.memory(state.bytes, fit: BoxFit.cover, width: double.infinity),

          // Dark gradient at bottom for legibility
          const Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 280,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                ),
              ),
            ),
          ),

          // ── Top bar ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Material(
                      color: Colors.black54,
                      shape: const CircleBorder(),
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: notifier.reset,
                        tooltip: 'Discard',
                      ),
                    ),
                    const Spacer(),
                    Material(
                      color: Colors.black54,
                      shape: const CircleBorder(),
                      child: IconButton(
                        icon: const Icon(
                          Icons.replay_rounded,
                          color: Colors.white,
                        ),
                        onPressed: notifier.retake,
                        tooltip: 'Retake',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Bottom: challenge info + submit ──
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Challenge summary
                    if (challenge != null) ...[
                      Row(
                        children: [
                          Text(
                            challenge.emoji,
                            style: const TextStyle(fontSize: 20),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Day ${challenge.dayNumber}',
                                  style: TextStyle(
                                    fontFamily: 'Nunito',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white.withValues(alpha: 0.6),
                                  ),
                                ),
                                Text(
                                  challenge.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: 'Nunito',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    // Submit button
                    PressableScale(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: AppColors.gradientForest,
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusButton,
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () =>
                                ref.read(cameraFlowProvider.notifier).verify(),
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusButton,
                            ),
                            child: SizedBox(
                              height: AppSpacing.buttonHeight,
                              child: Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      AppConstants.geminiApiKey.isEmpty
                                          ? Icons.check_circle_outline_rounded
                                          : Icons.auto_awesome_rounded,
                                      color: Colors.white,
                                      size: AppSpacing.iconSm,
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Text(
                                      AppConstants.geminiApiKey.isEmpty
                                          ? 'Submit Photo'
                                          : 'Verify with AI',
                                      style: const TextStyle(
                                        fontFamily: 'Nunito',
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
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
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextButton(
                      onPressed: notifier.retake,
                      child: const Text(
                        'Retake Photo',
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontWeight: FontWeight.w700,
                          color: Colors.white70,
                        ),
                      ),
                    ),
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

// ── Verifying ─────────────────────────────────────────────────────────────────

class _VerifyingView extends ConsumerStatefulWidget {
  const _VerifyingView({required this.state});
  final CameraVerifying state;

  @override
  ConsumerState<_VerifyingView> createState() => _VerifyingViewState();
}

class _VerifyingViewState extends ConsumerState<_VerifyingView>
    with SingleTickerProviderStateMixin {
  static const _stageMessages = {
    VerifyingStage.analyzing: 'Checking your adventure…',
    VerifyingStage.uploading: 'Saving your adventure…',
    VerifyingStage.saving: 'Finalizing your adventure…',
  };

  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    // Continuous ambient loop — never runs when Reduce Motion is on.
    if (!ref.read(reducedMotionProvider)) _pulse.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(widget.state.bytes, fit: BoxFit.cover),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.65),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Material(
                  color: Colors.black45,
                  shape: const CircleBorder(),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    tooltip: 'Cancel',
                    onPressed: () => ref
                        .read(cameraFlowProvider.notifier)
                        .cancelVerification(),
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, child) => Stack(
                    alignment: Alignment.center,
                    children: [
                      Transform.scale(
                        scale: 1.0 + _pulse.value * 0.22,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.grassGreen.withValues(
                                alpha: 0.35 * (1 - _pulse.value),
                              ),
                              width: 2,
                            ),
                          ),
                          child: const SizedBox(width: 68, height: 68),
                        ),
                      ),
                      child!,
                    ],
                  ),
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: CircularProgressIndicator(
                      color: AppColors.grassGreen,
                      strokeWidth: 3,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                AnimatedSwitcher(
                  duration: AppMotion.long,
                  transitionBuilder: (child, anim) =>
                      FadeTransition(opacity: anim, child: child),
                  child: Text(
                    _stageMessages[widget.state.stage]!,
                    key: ValueKey(widget.state.stage),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                // Only claim AI is reviewing the photo when it actually is —
                // never shown for the honor-system path (free-tier gate or
                // no Gemini key configured) or once the analyzing stage has
                // passed (the stage message above already accurately
                // describes uploading/saving without needing this line).
                if (widget.state.usingAi &&
                    widget.state.stage == VerifyingStage.analyzing) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'AI is reviewing your adventure',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Caption ───────────────────────────────────────────────────────────────────

class _CaptionView extends ConsumerStatefulWidget {
  const _CaptionView({required this.state});
  final CameraCaptionStep state;

  @override
  ConsumerState<_CaptionView> createState() => _CaptionViewState();
}

class _CaptionViewState extends ConsumerState<_CaptionView> {
  final _ctrl = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // Restore a reflection the user had already typed before a submission
    // failure sent them back through retryVerification — otherwise a
    // transient upload/save error would force a full retype.
    final initial = widget.state.initialCaption;
    if (initial != null && initial.isNotEmpty) _ctrl.text = initial;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    await ref.read(cameraFlowProvider.notifier).submitCaption(_ctrl.text);
    if (mounted) setState(() => _submitting = false);
  }

  /// Closing this screen discards whatever the user has typed with no way
  /// back — confirm first if there's actually something to lose, but don't
  /// interrupt the common case of backing out with an empty field.
  Future<void> _handleClose() async {
    if (_ctrl.text.trim().isEmpty) {
      ref.read(cameraFlowProvider.notifier).reset();
      return;
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark
        ? AppColors.surfaceVariantDark
        : AppColors.surfaceLight;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        ),
        title: const Text(
          'Discard your reflection?',
          style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900),
        ),
        content: const Text(
          "What you've written so far will be lost.",
          style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w500),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Keep writing',
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
              'Discard',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      ref.read(cameraFlowProvider.notifier).reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(widget.state.bytes, fit: BoxFit.cover),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.70),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: _handleClose,
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _submitting ? null : _submit,
                        child: Text(
                          'Skip',
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Expanded + scrollable (not a bare Spacer + fixed content)
                // so opening the keyboard on a short phone shrinks/scrolls
                // this region instead of overflowing — the prompt card +
                // multi-line text field + button can easily exceed the
                // remaining height once the keyboard takes ~250-300px.
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      reverse: true,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(
                                AppSpacing.screenHorizontal,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Only claim AI verification when Gemini actually ran
                                  // (its result map carries 'confidence') — never shown
                                  // for the no-API-key auto-approve path.
                                  if (widget.state.pendingVerificationResult
                                      .containsKey('confidence')) ...[
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.check_circle_rounded,
                                          size: 15,
                                          color: AppColors.grassGreen
                                              .withValues(alpha: 0.9),
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          'Adventure verified!',
                                          style: TextStyle(
                                            fontFamily: 'Nunito',
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.grassGreen
                                                .withValues(alpha: 0.9),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: AppSpacing.sm),
                                  ],
                                  // Free-tier honor-system approval — AI verification is
                                  // a paid feature (see camera_providers.dart's `aiLocked`
                                  // branch). Still counts as a real completion (XP
                                  // awarded normally), just without an AI-verified badge.
                                  if (widget
                                          .state
                                          .pendingVerificationResult['aiLocked'] ==
                                      true) ...[
                                    Semantics(
                                      label:
                                          'AI verification is a premium feature, '
                                          'coming soon. Your adventure was accepted.',
                                      excludeSemantics: true,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.auto_awesome_rounded,
                                            size: 15,
                                            color: AppColors.achievementGold
                                                .withValues(alpha: 0.9),
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            'AI verification — Coming soon!',
                                            style: TextStyle(
                                              fontFamily: 'Nunito',
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                              color: AppColors.achievementGold
                                                  .withValues(alpha: 0.9),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.sm),
                                  ],
                                  // AI prompt
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        AppSpacing.radiusMd,
                                      ),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.20,
                                        ),
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(
                                        AppSpacing.md,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            '✨',
                                            style: TextStyle(fontSize: 16),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              widget.state.captionPrompt,
                                              style: TextStyle(
                                                fontFamily: 'Nunito',
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.white.withValues(
                                                  alpha: 0.90,
                                                ),
                                                height: 1.4,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.10,
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        AppSpacing.radiusTextField,
                                      ),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.25,
                                        ),
                                      ),
                                    ),
                                    child: TextField(
                                      controller: _ctrl,
                                      maxLines: 4,
                                      minLines: 3,
                                      maxLength: 280,
                                      style: const TextStyle(
                                        fontFamily: 'Nunito',
                                        fontSize: 14,
                                        color: Colors.white,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: 'Write your adventure story…',
                                        hintStyle: TextStyle(
                                          fontFamily: 'Nunito',
                                          fontSize: 14,
                                          color: Colors.white.withValues(
                                            alpha: 0.35,
                                          ),
                                        ),
                                        border: InputBorder.none,
                                        contentPadding: const EdgeInsets.all(
                                          AppSpacing.md,
                                        ),
                                        counterStyle: TextStyle(
                                          fontFamily: 'Nunito',
                                          fontSize: 11,
                                          color: Colors.white.withValues(
                                            alpha: 0.40,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  PressableScale(
                                    enabled: !_submitting,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: AppColors.gradientForest,
                                        borderRadius: BorderRadius.circular(
                                          AppSpacing.radiusButton,
                                        ),
                                      ),
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: _submitting ? null : _submit,
                                          borderRadius: BorderRadius.circular(
                                            AppSpacing.radiusButton,
                                          ),
                                          child: SizedBox(
                                            height: AppSpacing.buttonHeight,
                                            child: Center(
                                              child: _submitting
                                                  ? const SizedBox(
                                                      width: 22,
                                                      height: 22,
                                                      child:
                                                          CircularProgressIndicator(
                                                            color: Colors.white,
                                                            strokeWidth: 2.5,
                                                          ),
                                                    )
                                                  : const Text(
                                                      'Share Adventure',
                                                      style: TextStyle(
                                                        fontFamily: 'Nunito',
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.lg),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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

// ── Success ───────────────────────────────────────────────────────────────────

class _SuccessView extends ConsumerStatefulWidget {
  const _SuccessView({required this.state});
  final CameraSuccess state;

  @override
  ConsumerState<_SuccessView> createState() => _SuccessViewState();
}

class _SuccessViewState extends ConsumerState<_SuccessView>
    with SingleTickerProviderStateMixin {
  late final ConfettiController _confetti;
  late final AnimationController _anim;
  late final CompanionType _companionType;
  late final String _companionMessage;
  late final bool _reducedMotion;
  late final CelebrationTier _celebrationTier;

  @override
  void initState() {
    super.initState();
    _reducedMotion = ref.read(reducedMotionProvider);
    _celebrationTier = resolveCelebrationTier(
      leveledUp: widget.state.leveledUp,
      newAchievements: widget.state.newAchievements,
      leagueChanged: widget.state.leagueChanged,
    );
    _confetti = ConfettiController(
      duration: Duration(seconds: confettiDurationSecondsFor(_celebrationTier)),
    );
    // Fast, front-loaded reveal — the celebration and photo should appear
    // almost immediately, XP/streak follow quickly, achievement cards last.
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (_reducedMotion) {
      // Skip the confetti burst and the staggered reveal — show the final
      // completion state immediately. XP/level/achievement rewards are
      // already persisted server-side by this point, so this is purely a
      // display choice and never affects what was actually earned.
      _anim.value = 1.0;
    } else {
      _confetti.play();
      _anim.forward();
    }

    final hasAchievements = widget.state.newAchievements.isNotEmpty;
    final isStreakMilestone = const {
      3,
      7,
      14,
      30,
      100,
    }.contains(widget.state.newStreak);

    if (widget.state.leveledUp) {
      _companionType = CompanionType.sunny;
    } else if (hasAchievements) {
      _companionType = CompanionType.pebble;
    } else if (isStreakMilestone) {
      _companionType = CompanionType.sprout;
    } else {
      _companionType = CompanionType.leafy;
    }

    final List<String> msgs;
    if (widget.state.leveledUp) {
      msgs = _companionType.levelUpMessages;
    } else if (hasAchievements) {
      msgs = _companionType.achievementMessages;
    } else if (isStreakMilestone) {
      msgs = _companionType.streakMilestoneMessages;
    } else {
      msgs = _companionType.completionMessages;
    }
    _companionMessage = msgs[widget.state.xpAwarded % msgs.length];
  }

  @override
  void dispose() {
    _confetti.dispose();
    _anim.dispose();
    super.dispose();
  }

  Animation<double> _curve(
    double begin,
    double end, {
    Curve curve = Curves.easeOut,
  }) => CurvedAnimation(
    parent: _anim,
    curve: Interval(begin, end, curve: curve),
  );

  @override
  Widget build(BuildContext context) {
    // Fast, front-loaded stagger (Part 11): celebration + photo appear
    // almost immediately, title/XP/streak follow quickly, achievement
    // cards reveal last.
    final checkAnim = _curve(0.00, 0.30, curve: Curves.elasticOut);
    final photoFade = _curve(0.10, 0.40);
    final photoSlide = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(_curve(0.10, 0.40));
    final titleSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(_curve(0.25, 0.50));
    final titleFade = _curve(0.25, 0.50);
    final xpFade = _curve(0.35, 0.60);
    final streakAnim = _curve(0.50, 0.75, curve: Curves.elasticOut);
    final levelAnim = _curve(0.55, 0.80, curve: Curves.elasticOut);
    // Reveals after the achievement cards (0.65–1.00) so the level-up/league
    // banners read as the celebration's closing beat rather than competing
    // with them — these sit lower in the layout, so a later reveal matches.
    final postAchieveAnim = _curve(0.78, 1.00, curve: Curves.elasticOut);
    final detailFade = _curve(0.60, 0.85);
    final btnSlide = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(_curve(0.80, 1.00));
    final btnFade = _curve(0.80, 1.00);
    final achieveSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(_curve(0.65, 1.00));
    final achieveFade = _curve(0.65, 1.00);

    final completion = widget.state.completion;
    final hasCaption =
        completion.caption != null && completion.caption!.isNotEmpty;
    final hasLocation = completion.location != null;

    return Scaffold(
      body: Stack(
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(gradient: AppColors.gradientForest),
            child: SizedBox.expand(),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenHorizontal,
                  vertical: AppSpacing.xl,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── TOP: celebration heading ──
                    ScaleTransition(
                      scale: checkAnim,
                      child: const Text('✅', style: TextStyle(fontSize: 72)),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    FadeTransition(
                      opacity: titleFade,
                      child: const Text(
                        'Adventure Complete!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          height: 1.1,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    FadeTransition(
                      opacity: titleFade,
                      child: CompanionView(
                        type: _companionType,
                        mood: CompanionMood.cheer,
                        size: 88,
                        message: _companionMessage,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    // ── MIDDLE: large captured photo ──
                    FadeTransition(
                      opacity: photoFade,
                      child: SlideTransition(
                        position: photoSlide,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusLg,
                          ),
                          child: Image.network(
                            completion.photoUrl,
                            height: 220,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const SizedBox.shrink(),
                            loadingBuilder: (_, child, progress) =>
                                progress == null
                                ? child
                                : const SizedBox(
                                    height: 220,
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        color: Colors.white54,
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    // ── BELOW PHOTO: challenge title ──
                    FadeTransition(
                      opacity: titleFade,
                      child: SlideTransition(
                        position: titleSlide,
                        child: Column(
                          children: [
                            Text(
                              widget.state.emoji,
                              style: const TextStyle(fontSize: 40),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              widget.state.challengeTitle,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: 'Nunito',
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Challenge Complete!',
                              style: TextStyle(
                                fontFamily: 'Nunito',
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    // ── XP earned ──
                    FadeTransition(
                      opacity: xpFade,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.xpGold.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusFull,
                          ),
                          border: Border.all(
                            color: AppColors.xpGold.withValues(alpha: 0.5),
                            width: 1.5,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xl,
                            vertical: AppSpacing.md,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('⭐', style: TextStyle(fontSize: 22)),
                              const SizedBox(width: AppSpacing.sm),
                              TweenAnimationBuilder<int>(
                                tween: IntTween(
                                  begin: 0,
                                  end: widget.state.xpAwarded,
                                ),
                                duration: _reducedMotion
                                    ? Duration.zero
                                    : AppMotion.hero,
                                curve: Curves.easeOut,
                                builder: (_, xp, _) => Text(
                                  '+$xp XP',
                                  style: const TextStyle(
                                    fontFamily: 'Nunito',
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.xpGold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    // Streak
                    ScaleTransition(
                      scale: streakAnim,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusFull,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.sm,
                          ),
                          child: Text(
                            '🔥 ${streakCelebrationLabel(newStreak: widget.state.newStreak, streakIncreased: widget.state.streakIncreased, rainyDayConsumed: widget.state.rainyDayConsumed)}',
                            style: const TextStyle(
                              fontFamily: 'Nunito',
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Rainy Day consumed notification
                    if (widget.state.rainyDayConsumed) ...[
                      const SizedBox(height: AppSpacing.md),
                      ScaleTransition(
                        scale: levelAnim,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF4EA8DE,
                            ).withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusMd,
                            ),
                            border: Border.all(
                              color: const Color(
                                0xFF4EA8DE,
                              ).withValues(alpha: 0.5),
                              width: 1.5,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xl,
                              vertical: AppSpacing.sm,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  '🌧️',
                                  style: TextStyle(fontSize: 16),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Text(
                                  'Rainy Day used · ${widget.state.rainyDaysAvailable} left',
                                  style: const TextStyle(
                                    fontFamily: 'Nunito',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF4EA8DE),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                    // Rainy Day earned notification
                    if (widget.state.rainyDayEarned > 0) ...[
                      const SizedBox(height: AppSpacing.md),
                      ScaleTransition(
                        scale: levelAnim,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF4EA8DE,
                            ).withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusMd,
                            ),
                            border: Border.all(
                              color: const Color(
                                0xFF4EA8DE,
                              ).withValues(alpha: 0.5),
                              width: 1.5,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xl,
                              vertical: AppSpacing.sm,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  '🌧️',
                                  style: TextStyle(fontSize: 16),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Text(
                                  '+${widget.state.rainyDayEarned} Rainy Day${widget.state.rainyDayEarned > 1 ? 's' : ''} earned!',
                                  style: const TextStyle(
                                    fontFamily: 'Nunito',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF4EA8DE),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],

                    // ── Caption (user's reflection) ──
                    if (hasCaption) ...[
                      const SizedBox(height: AppSpacing.lg),
                      FadeTransition(
                        opacity: detailFade,
                        child: Text(
                          '"${completion.caption}"',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            fontStyle: FontStyle.italic,
                            color: Colors.white70,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                    // ── Location recorded ──
                    if (hasLocation) ...[
                      const SizedBox(height: AppSpacing.xs),
                      FadeTransition(
                        opacity: detailFade,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.location_on_rounded,
                              size: 13,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Location recorded',
                              style: TextStyle(
                                fontFamily: 'Nunito',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Achievement unlock cards
                    if (widget.state.newAchievements.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.lg),
                      SlideTransition(
                        position: achieveSlide,
                        child: FadeTransition(
                          opacity: achieveFade,
                          child: _AchievementUnlockSection(
                            ids: widget.state.newAchievements,
                          ),
                        ),
                      ),
                    ],

                    // Level-up banner
                    if (widget.state.leveledUp) ...[
                      const SizedBox(height: AppSpacing.lg),
                      ScaleTransition(
                        scale: postAchieveAnim,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusMd,
                            ),
                            border: Border.all(
                              color: Colors.amber.withValues(alpha: 0.7),
                              width: 1.5,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xl,
                              vertical: AppSpacing.sm,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  '🏆',
                                  style: TextStyle(fontSize: 18),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Text(
                                  'LEVEL UP! · Level ${widget.state.newLevel}',
                                  style: const TextStyle(
                                    fontFamily: 'Nunito',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.amber,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],

                    // League change banner — only when the canonical
                    // XP-tier league actually changed this completion; never
                    // a separate weekly promotion/demotion mechanic.
                    if (widget.state.leagueChanged) ...[
                      const SizedBox(height: AppSpacing.md),
                      ScaleTransition(
                        scale: postAchieveAnim,
                        child: Builder(
                          builder: (context) {
                            final league = LeagueDef.withId(
                              widget.state.newLeague,
                            );
                            if (league == null) return const SizedBox.shrink();
                            return DecoratedBox(
                              decoration: BoxDecoration(
                                color: league.color.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(
                                  AppSpacing.radiusMd,
                                ),
                                border: Border.all(
                                  color: league.color.withValues(alpha: 0.7),
                                  width: 1.5,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.xl,
                                  vertical: AppSpacing.sm,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      league.emoji,
                                      style: const TextStyle(fontSize: 18),
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Text(
                                      'New League · ${league.name}',
                                      style: TextStyle(
                                        fontFamily: 'Nunito',
                                        fontSize: 15,
                                        fontWeight: FontWeight.w900,
                                        color: league.color,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xxxl),

                    // ── BOTTOM ACTIONS ──
                    // Primary: View Adventure / View on Map (56px, 16px radius)
                    // Secondary: Continue (48px)
                    //
                    // "View on Map" only makes sense when this completion
                    // actually has a location — otherwise tapping it would
                    // silently drop the user on the map with nothing to
                    // focus on (no crash, but no explanation either). When
                    // there's no location, "Continue" becomes the sole,
                    // primary action instead of leaving a dead-feeling button.
                    FadeTransition(
                      opacity: btnFade,
                      child: SlideTransition(
                        position: btnSlide,
                        child: Column(
                          children: [
                            if (hasLocation) ...[
                              PressableScale(
                                child: SizedBox(
                                  width: double.infinity,
                                  height: AppSpacing.buttonHeight,
                                  child: Material(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(
                                      AppSpacing.radiusButton,
                                    ),
                                    elevation: 6,
                                    shadowColor: Colors.black26,
                                    child: InkWell(
                                      onTap: () {
                                        ref
                                            .read(
                                              pendingMapFocusProvider.notifier,
                                            )
                                            .state = completion
                                            .id;
                                        context.go(RouteNames.map);
                                      },
                                      borderRadius: BorderRadius.circular(
                                        AppSpacing.radiusButton,
                                      ),
                                      child: const Center(
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.map_rounded,
                                              color: AppColors.forestGreen,
                                              size: AppSpacing.iconSm,
                                            ),
                                            SizedBox(width: AppSpacing.sm),
                                            Text(
                                              'View on Map',
                                              style: TextStyle(
                                                fontFamily: 'Nunito',
                                                fontSize: 16,
                                                fontWeight: FontWeight.w900,
                                                color: AppColors.forestGreen,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                            ] else
                              PressableScale(
                                child: SizedBox(
                                  width: double.infinity,
                                  height: AppSpacing.buttonHeight,
                                  child: Material(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(
                                      AppSpacing.radiusButton,
                                    ),
                                    elevation: 6,
                                    shadowColor: Colors.black26,
                                    child: InkWell(
                                      onTap: () => context.go(RouteNames.home),
                                      borderRadius: BorderRadius.circular(
                                        AppSpacing.radiusButton,
                                      ),
                                      child: const Center(
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.check_circle_rounded,
                                              color: AppColors.forestGreen,
                                              size: AppSpacing.iconSm,
                                            ),
                                            SizedBox(width: AppSpacing.sm),
                                            Text(
                                              'Continue',
                                              style: TextStyle(
                                                fontFamily: 'Nunito',
                                                fontSize: 16,
                                                fontWeight: FontWeight.w900,
                                                color: AppColors.forestGreen,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (hasLocation)
                              PressableScale(
                                child: SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: Material(
                                    color: Colors.transparent,
                                    borderRadius: BorderRadius.circular(
                                      AppSpacing.radiusButton,
                                    ),
                                    child: InkWell(
                                      onTap: () => context.go(RouteNames.home),
                                      borderRadius: BorderRadius.circular(
                                        AppSpacing.radiusButton,
                                      ),
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: Colors.white.withValues(
                                              alpha: 0.4,
                                            ),
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            AppSpacing.radiusButton,
                                          ),
                                        ),
                                        child: const Center(
                                          child: Text(
                                            'Continue',
                                            style: TextStyle(
                                              fontFamily: 'Nunito',
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Confetti
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confetti,
              blastDirectionality: BlastDirectionality.explosive,
              numberOfParticles: confettiParticleCountFor(_celebrationTier),
              gravity: 0.18,
              emissionFrequency: 0.06,
              maxBlastForce: 28,
              minBlastForce: 10,
              colors: const [
                Color(0xFFFFB703),
                Color(0xFF52B788),
                Colors.white,
                Color(0xFF4EA8DE),
                Color(0xFFFF9E3D),
                Color(0xFFFC4E6F),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Failure ───────────────────────────────────────────────────────────────────

class _FailureView extends ConsumerWidget {
  const _FailureView({required this.state});
  final CameraFailure state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(cameraFlowProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confidence = state.confidence;
    final explanation = state.explanation;
    // After a couple of retries, gently point toward Submit Anyway instead
    // of leaving the user to loop the same failure indefinitely.
    final retryCount = ref.watch(verificationRetryCountProvider);
    final showOverrideNudge = retryCount >= 2 && state.bytes != null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Photo background (if we have bytes)
          if (state.bytes != null)
            Image.memory(state.bytes!, fit: BoxFit.cover),
          if (state.bytes != null)
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
              ),
            ),

          // No-photo fallback background
          if (state.bytes == null)
            DecoratedBox(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0D1117) : Colors.black,
              ),
            ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top close button
                  Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      color: Colors.black45,
                      shape: const CircleBorder(),
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: notifier.reset,
                      ),
                    ),
                  ),
                  const Spacer(),

                  // Result card
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.70),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                      border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header
                          Row(
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                color: AppColors.error,
                                size: 22,
                              ),
                              const SizedBox(width: 8),
                              // "Failed" implies AI reached a verdict (a
                              // genuine content rejection, which carries a
                              // confidence score); anything without one is a
                              // service problem, not a verdict on the photo.
                              Text(
                                confidence != null
                                    ? 'Verification Failed'
                                    : 'Verification Unavailable',
                                style: const TextStyle(
                                  fontFamily: 'Nunito',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                              if (confidence != null) ...[
                                const Spacer(),
                                _ConfidenceBadge(confidence: confidence),
                              ],
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          // Error message
                          Text(
                            state.message,
                            style: TextStyle(
                              fontFamily: 'Nunito',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.75),
                              height: 1.4,
                            ),
                          ),
                          // Explanation from Gemini
                          if (explanation != null &&
                              explanation.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.sm),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.07),
                                borderRadius: BorderRadius.circular(
                                  AppSpacing.radiusSm,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '🤖',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                    const SizedBox(width: 7),
                                    Expanded(
                                      child: Text(
                                        explanation,
                                        style: TextStyle(
                                          fontFamily: 'Nunito',
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white.withValues(
                                            alpha: 0.65,
                                          ),
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Try again
                  PressableScale(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: AppColors.gradientForest,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusButton,
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: Semantics(
                          button: true,
                          label: 'Retake photo',
                          excludeSemantics: true,
                          child: InkWell(
                            onTap: notifier.retake,
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusButton,
                            ),
                            child: const SizedBox(
                              height: AppSpacing.buttonHeight,
                              child: Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.camera_alt_rounded,
                                      color: Colors.white,
                                      size: AppSpacing.iconSm,
                                    ),
                                    SizedBox(width: AppSpacing.sm),
                                    Text(
                                      'Retake Photo',
                                      style: TextStyle(
                                        fontFamily: 'Nunito',
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
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
                    ),
                  ),

                  if (showOverrideNudge) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      "Still not matching? You can submit it manually below.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                  ],

                  if (state.bytes != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    // Retry verification on the same photo (no retake needed)
                    PressableScale(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusButton,
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => notifier.retryVerification(),
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusButton,
                            ),
                            child: const SizedBox(
                              height: AppSpacing.buttonHeight,
                              child: Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.refresh_rounded,
                                      color: Colors.white,
                                      size: AppSpacing.iconSm,
                                    ),
                                    SizedBox(width: AppSpacing.sm),
                                    Text(
                                      'Retry Verification',
                                      style: TextStyle(
                                        fontFamily: 'Nunito',
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
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
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    // Manual override
                    PressableScale(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusButton,
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => notifier.override(),
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusButton,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.md,
                              ),
                              child: Column(
                                children: [
                                  const Text(
                                    'Submit Anyway',
                                    style: TextStyle(
                                      fontFamily: 'Nunito',
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    "We couldn't confirm this with AI — you can still submit it manually",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontFamily: 'Nunito',
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white.withValues(
                                        alpha: 0.50,
                                      ),
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
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: () => context.go(RouteNames.home),
                    child: Text(
                      'Skip for now',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Achievement unlock section (shown in _SuccessView) ───────────────────────

class _AchievementUnlockSection extends StatelessWidget {
  const _AchievementUnlockSection({required this.ids});
  final List<String> ids;

  @override
  Widget build(BuildContext context) {
    final defs = AchievementDefinition.catalog
        .where((d) => ids.contains(d.id))
        .toList();
    if (defs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('🏅', style: TextStyle(fontSize: 14)),
            SizedBox(width: 6),
            Text(
              'Achievement Unlocked!',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: Colors.white70,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ...defs.map(
          (def) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _UnlockCard(def: def),
          ),
        ),
      ],
    );
  }
}

class _UnlockCard extends StatelessWidget {
  const _UnlockCard({required this.def});
  final AchievementDefinition def;

  @override
  Widget build(BuildContext context) {
    final rarityColor = def.rarity.color;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        border: Border.all(
          color: rarityColor.withValues(alpha: 0.65),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Text(def.emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    def.title,
                    style: const TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: rarityColor.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusFull,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      child: Text(
                        def.rarity.label,
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: rarityColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 4,
                ),
                child: Text(
                  '+${def.xpReward} XP',
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Colors.amber,
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

// ── Confidence badge ──────────────────────────────────────────────────────────

class _ConfidenceBadge extends StatelessWidget {
  const _ConfidenceBadge({required this.confidence});
  final double confidence;

  Color get _color {
    if (confidence >= 0.6) return AppColors.grassGreen;
    if (confidence >= 0.4) return Colors.orange;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    final pct = (confidence * 100).round();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: Border.all(color: _color.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          '$pct% match',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: _color,
          ),
        ),
      ),
    );
  }
}
