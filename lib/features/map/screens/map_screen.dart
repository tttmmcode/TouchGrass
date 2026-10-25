import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../../../core/services/error_service.dart';
import '../../../models/adventure_memory_model.dart';
import '../../../models/challenge_model.dart';
import '../../../providers/map_providers.dart';
import '../../../providers/memory_providers.dart';
import '../../../providers/settings_providers.dart';
import '../../../services/location_service.dart';
import '../../../services/perf_service.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_elevation.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_spacing.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/error_retry_view.dart';
import '../../../widgets/loading_widgets.dart';
import '../../../widgets/pressable_scale.dart';
import '../utils/photo_marker_generator.dart';

// ── Clustering ───────────────────────────────────────────────────────────────

/// Grid-cell size (in degrees) to group markers at the given zoom — coarser
/// cells when zoomed out (world view), finer when zoomed in (street view),
/// so nearby memories merge into one cluster only when they'd visually
/// overlap. Manual grid clustering (not a maps-clustering package) keeps
/// this dependency-free; see [PhotoMarkerGenerator] for the marker bitmaps.
@visibleForTesting
double cellSizeForZoom(double zoom) {
  final size = 60.0 / math.pow(2, zoom);
  // Lower bound (~3m at the equator) keeps clustering from fragmenting on
  // GPS jitter even at max zoom; upper bound (~40°) keeps a fully zoomed-out
  // world view from collapsing everything into one giant cluster.
  return size.clamp(0.00003, 40.0);
}

/// Groups [memories] (all assumed to have a location) into proximity
/// clusters for the given map [zoom]. Extracted as a pure function — no
/// `BuildContext`, no map controller — so clustering correctness (grouping
/// threshold, group membership) is directly unit-testable.
@visibleForTesting
List<List<AdventureMemoryModel>> clusterMemoriesByProximity(
  List<AdventureMemoryModel> memories, {
  required double zoom,
}) {
  final cellSize = cellSizeForZoom(zoom);
  final cells = <String, List<AdventureMemoryModel>>{};
  for (final m in memories) {
    final key =
        '${(m.latitude! / cellSize).floor()}_'
        '${(m.longitude! / cellSize).floor()}';
    cells.putIfAbsent(key, () => []).add(m);
  }
  return cells.values.toList();
}

// ── Map focus ────────────────────────────────────────────────────────────────

/// Resolves which memory (if any) a pending "View on Map" focus request
/// refers to. Extracted as a pure function so the lookup rule — must exist
/// in the currently-loaded list AND have a valid location, else gracefully
/// fall back to normal map behavior — is directly unit-testable without a
/// `GoogleMapController` or widget tree.
@visibleForTesting
AdventureMemoryModel? resolveFocusMemory(
  List<AdventureMemoryModel> memories,
  String? focusMemoryId,
) {
  if (focusMemoryId == null) return null;
  for (final m in memories) {
    if (m.memoryId == focusMemoryId && m.hasLocation) return m;
  }
  return null;
}

// ── Screen ────────────────────────────────────────────────────────────────────

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabController;
  GoogleMapController? _mapController;
  ChallengeCategory? _selectedCategory;
  Trace? _loadTrace;

  /// Memory ID to center on and emphasize, sourced from
  /// [pendingMapFocusProvider]. Re-applied via `ref.listen` (not just a
  /// one-time initState read) so it works both the first time this screen is
  /// ever built AND on every later "View on Map" while the screen instance
  /// stays alive in its IndexedStack branch.
  String? _focusMemoryId;

  /// The focus memory ID we've already animated the camera to / opened the
  /// detail sheet for — prevents re-triggering that side effect on every
  /// rebuild once it's been applied.
  String? _appliedFocusId;

  String? _selectedMemoryId;
  bool _modalOpen = false;

  double _zoom = 2.0;
  bool _autoLoadTriggered = false;
  bool _autoLoadInFlight = false;

  /// True once the user has manually panned/zoomed the map — after that, the
  /// ambient "follow my location" listener below must stop recentering the
  /// camera on its own (it would otherwise fight the user's own movement
  /// every time `currentLocationProvider` re-resolves, e.g. after an app
  /// resume). Distinguished from programmatic moves via [_isProgrammaticMove].
  bool _userInteractedWithMap = false;
  bool _isProgrammaticMove = false;

  final Map<String, BitmapDescriptor> _markerCache = {};
  final Map<int, BitmapDescriptor> _clusterCache = {};
  final Set<String> _generatingMarkers = {};

  /// Decoded images keyed by photo URL, shared between a memory's selected
  /// and unselected marker variants so toggling selection only re-runs the
  /// cheap canvas rasterization step, never a repeat network fetch.
  final Map<String, ui.Image> _decodedImages = {};

  /// Marker/cluster cache keys that failed to generate (network error, decode
  /// error). Checked before re-requesting so a permanently-broken photo URL
  /// doesn't get re-fetched on every rebuild — the hue-based fallback marker
  /// stays in place instead.
  final Set<String> _failedMarkers = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final initialTab = ref.read(pendingMapTabProvider);
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: initialTab ?? 0,
    );
    if (initialTab != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(pendingMapTabProvider.notifier).state = null;
      });
    }
    _tabController.addListener(_onTabChanged);
    _loadTrace = PerfService.startTrace(PerfService.traceMapLoad);

    _focusMemoryId = ref.read(pendingMapFocusProvider);
    if (_focusMemoryId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(pendingMapFocusProvider.notifier).state = null;
      });
    }
  }

  void _onTabChanged() {
    // Only rebuild when the tab has fully settled — not on every animation frame.
    if (!_tabController.indexIsChanging) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The user may be returning from the OS Settings screen after granting
    // location access from the "enable location" banner below — re-check so
    // the map doesn't stay stuck on a denied-access state until a restart.
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(locationAccessStatusProvider);
      ref.invalidate(currentLocationProvider);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  List<AdventureMemoryModel> _filter(List<AdventureMemoryModel> memories) {
    if (_selectedCategory == null) return memories;
    return memories
        .where((m) => m.challengeCategory == _selectedCategory)
        .toList();
  }

  /// Keeps loading pages until the full history is available for markers —
  /// the map (unlike the scroll-paginated journal) needs the whole picture
  /// to cluster correctly. Still goes through the same bounded, cursor-based
  /// pages (never one unbounded query) and stops as soon as `hasMore` is
  /// false. The 20-page ceiling (~1000 memories) is far beyond any realistic
  /// history for a once-a-day habit app and exists only as a safety bound.
  Future<void> _autoLoadAllForMap() async {
    if (_autoLoadInFlight) return;
    _autoLoadInFlight = true;
    final notifier = ref.read(memoriesControllerProvider.notifier);
    for (var i = 0; i < 20; i++) {
      final state = ref.read(memoriesControllerProvider);
      if (!state.hasMore || state.loadingMore) break;
      await notifier.loadMore();
      if (!mounted) return;
    }
    _autoLoadInFlight = false;
  }

  // ── Clustering ────────────────────────────────────────────────────────────

  Set<Marker> _buildMarkers(List<AdventureMemoryModel> memories) {
    final withLocation = memories.where((m) => m.hasLocation).toList();
    final groups = clusterMemoriesByProximity(withLocation, zoom: _zoom);
    final markers = <Marker>{};
    for (final group in groups) {
      markers.add(
        group.length == 1 ? _singleMarker(group.first) : _clusterMarker(group),
      );
    }
    return markers;
  }

  Marker _singleMarker(AdventureMemoryModel m) {
    final selected = m.memoryId == _selectedMemoryId;
    final cacheKey = '${m.memoryId}:$selected';
    final icon = _markerCache[cacheKey];
    if (icon == null && !_failedMarkers.contains(m.memoryId)) {
      _requestPhotoMarker(m, selected, cacheKey);
    }
    return Marker(
      markerId: MarkerId(m.memoryId),
      position: LatLng(m.latitude!, m.longitude!),
      icon:
          icon ??
          BitmapDescriptor.defaultMarkerWithHue(
            _hueForCategory(m.challengeCategory),
          ),
      anchor: const Offset(0.5, 0.5),
      zIndexInt: selected ? 1 : 0,
      // Gives the marker an accessible title (surfaced by the platform's
      // screen reader) in addition to the tap target below.
      infoWindow: InfoWindow(
        title:
            'Adventure photo from ${m.displayLocation}, '
            '${DateFormat('MMMM d').format(m.completionDate)}',
      ),
      onTap: () => _showMemoryModal(m),
    );
  }

  Marker _clusterMarker(List<AdventureMemoryModel> group) {
    final lat =
        group.map((m) => m.latitude!).reduce((a, b) => a + b) / group.length;
    final lng =
        group.map((m) => m.longitude!).reduce((a, b) => a + b) / group.length;
    final count = group.length;
    final icon = _clusterCache[count];
    if (icon == null) _requestClusterMarker(count);
    return Marker(
      markerId: MarkerId('cluster_${group.map((m) => m.memoryId).join('_')}'),
      position: LatLng(lat, lng),
      icon:
          icon ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      anchor: const Offset(0.5, 0.5),
      infoWindow: InfoWindow(title: '$count adventures here'),
      onTap: () => _zoomToCluster(group),
    );
  }

  /// Zooms to fit every memory in [group] within view (with padding) rather
  /// than guessing a fixed zoom increment — reliably separates the cluster
  /// into individual markers in one tap regardless of how tightly grouped
  /// the underlying memories are.
  void _zoomToCluster(List<AdventureMemoryModel> group) {
    if (group.length == 1) {
      final m = group.first;
      _moveCamera(
        CameraUpdate.newLatLngZoom(LatLng(m.latitude!, m.longitude!), 17),
      );
      return;
    }
    var minLat = group.first.latitude!;
    var maxLat = minLat;
    var minLng = group.first.longitude!;
    var maxLng = minLng;
    for (final m in group.skip(1)) {
      minLat = math.min(minLat, m.latitude!);
      maxLat = math.max(maxLat, m.latitude!);
      minLng = math.min(minLng, m.longitude!);
      maxLng = math.max(maxLng, m.longitude!);
    }
    // A cluster whose members are all at (near-)identical coordinates would
    // otherwise produce a degenerate/zero-area bounds that newLatLngBounds
    // can reject — pad it out to a small but real box.
    const minSpan = 0.0006;
    if ((maxLat - minLat) < minSpan) {
      minLat -= minSpan / 2;
      maxLat += minSpan / 2;
    }
    if ((maxLng - minLng) < minSpan) {
      minLng -= minSpan / 2;
      maxLng += minSpan / 2;
    }
    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
    _moveCamera(CameraUpdate.newLatLngBounds(bounds, 64));
  }

  Future<void> _requestPhotoMarker(
    AdventureMemoryModel m,
    bool selected,
    String cacheKey,
  ) async {
    if (!m.photoUrl.startsWith('http')) return;
    if (!_generatingMarkers.add(cacheKey)) return;
    try {
      var image = _decodedImages[m.photoUrl];
      if (image == null) {
        image = await PhotoMarkerGenerator.loadImage(m.photoUrl);
        if (!mounted) return;
        _decodedImages[m.photoUrl] = image;
      }
      final icon = await PhotoMarkerGenerator.rasterizePhotoMarker(
        image: image,
        selected: selected,
        accentColor: AppColors.forestGreen,
      );
      if (!mounted) return;
      _markerCache[cacheKey] = icon;
      setState(() {});
    } catch (_) {
      // Network/decode failure — the hue-based fallback marker (already
      // rendered) stays in place. Marked failed so a permanently-broken
      // photo URL isn't re-fetched on every subsequent rebuild.
      _failedMarkers.add(m.memoryId);
    } finally {
      _generatingMarkers.remove(cacheKey);
    }
  }

  Future<void> _requestClusterMarker(int count) async {
    final key = 'cluster_$count';
    if (!_generatingMarkers.add(key)) return;
    try {
      final icon = await PhotoMarkerGenerator.buildClusterMarker(
        count: count,
        color: AppColors.forestGreen,
      );
      if (!mounted) return;
      _clusterCache[count] = icon;
      setState(() {});
    } catch (_) {
      // Keep the fallback default marker.
    } finally {
      _generatingMarkers.remove(key);
    }
  }

  /// Single entry point for every programmatic camera movement — respects
  /// Reduce Motion (jumps instantly via `moveCamera` instead of animating)
  /// and flags the move as programmatic so [onCameraMoveStarted] doesn't
  /// mistake it for a user gesture (which would otherwise permanently
  /// suppress the "follow my location" listener below).
  void _moveCamera(CameraUpdate update) {
    final controller = _mapController;
    if (controller == null) return;
    _isProgrammaticMove = true;
    final reduceMotion = ref.read(reducedMotionProvider);
    final future = reduceMotion
        ? controller.moveCamera(update)
        : controller.animateCamera(update);
    future.whenComplete(() => _isProgrammaticMove = false);
  }

  void _showMemoryModal(AdventureMemoryModel memory) {
    _moveCamera(
      CameraUpdate.newLatLng(LatLng(memory.latitude!, memory.longitude!)),
    );
    _openModal(memory);
  }

  void _openModal(AdventureMemoryModel memory) {
    // Guards against a rapid double-tap on a marker/journal card pushing two
    // overlapping detail sheets before the first one's route has settled.
    if (_modalOpen) return;
    _modalOpen = true;
    setState(() => _selectedMemoryId = memory.memoryId);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MemoryDetailModal(memory: memory),
    ).then((_) {
      _modalOpen = false;
      if (mounted) setState(() => _selectedMemoryId = null);
    });
  }

  double _hueForCategory(ChallengeCategory cat) => switch (cat) {
    ChallengeCategory.nature => BitmapDescriptor.hueGreen,
    ChallengeCategory.observation => BitmapDescriptor.hueAzure,
    ChallengeCategory.exercise => BitmapDescriptor.hueOrange,
    ChallengeCategory.exploration => BitmapDescriptor.hueYellow,
    ChallengeCategory.photography => BitmapDescriptor.hueCyan,
    ChallengeCategory.mindfulness => BitmapDescriptor.hueViolet,
    ChallengeCategory.environmental => BitmapDescriptor.hueGreen,
    ChallengeCategory.microAdventure => BitmapDescriptor.hueRose,
  };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final memoriesState = ref.watch(memoriesControllerProvider);
    // Restores Journal entries missing for recent completions (audit D-13),
    // once per session; a failure shows a retry banner in the Journal.
    final journalSync = ref.watch(journalSyncProvider);
    final allMemories = memoriesState.memories;
    final filtered = _filter(allMemories);
    final markers = _buildMarkers(filtered);
    final locationAsync = ref.watch(currentLocationProvider);
    final myLocation = locationAsync.valueOrNull;
    final locationStatus = ref.watch(locationAccessStatusProvider).valueOrNull;

    ref.listen<MemoriesState>(memoriesControllerProvider, (previous, next) {
      if (previous?.initialLoading == true &&
          !next.initialLoading &&
          !_autoLoadTriggered) {
        _autoLoadTriggered = true;
        _autoLoadAllForMap();
      }
    });

    ref.listen<String?>(pendingMapFocusProvider, (previous, next) {
      if (next != null) {
        setState(() => _focusMemoryId = next);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) ref.read(pendingMapFocusProvider.notifier).state = null;
        });
      }
    });

    // Resolve the memory to focus on (from "View on Map"), if any. Falls
    // back to normal myLocation-centered behavior when there's no pending
    // focus, the memory isn't found yet, or it has no location — never
    // breaks ordinary map navigation.
    final focusMemory = resolveFocusMemory(allMemories, _focusMemoryId);
    final focusTarget = focusMemory != null
        ? LatLng(focusMemory.latitude!, focusMemory.longitude!)
        : null;

    if (focusMemory != null &&
        _mapController != null &&
        _appliedFocusId != focusMemory.memoryId) {
      final memory = focusMemory;
      _appliedFocusId = memory.memoryId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_tabController.index != 0) _tabController.animateTo(0);
        _moveCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(memory.latitude!, memory.longitude!),
            15,
          ),
        );
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _showMemoryModal(memory);
        });
      });
    }

    ref.listen(currentLocationProvider, (_, next) {
      // Don't let "my location" resolving late steal the camera away from a
      // memory the user explicitly navigated here to see, and once the user
      // has manually panned/zoomed, stop fighting their own movement (e.g.
      // this listener firing again after an app-resume location refresh).
      if (focusTarget != null) return;
      if (_userInteractedWithMap) return;
      if (next.hasValue && next.valueOrNull != null) {
        _moveCamera(CameraUpdate.newLatLngZoom(next.value!, 13));
      }
    });

    // Initial camera position: focus target > user location > most recent
    // memory > safe world default. Never over-zoomed when we don't actually
    // know where the user is.
    final LatLng initialTarget;
    final double initialZoom;
    if (focusTarget != null) {
      initialTarget = focusTarget;
      initialZoom = 15.0;
    } else if (myLocation != null) {
      initialTarget = myLocation;
      initialZoom = 13.0;
    } else {
      AdventureMemoryModel? mostRecentWithLocation;
      for (final m in allMemories) {
        if (m.hasLocation) {
          mostRecentWithLocation = m;
          break;
        }
      }
      if (mostRecentWithLocation != null) {
        initialTarget = LatLng(
          mostRecentWithLocation.latitude!,
          mostRecentWithLocation.longitude!,
        );
        initialZoom = 11.0;
      } else {
        initialTarget = const LatLng(20.0, 0.0);
        initialZoom = 2.0;
      }
    }

    return Scaffold(
      body: Stack(
        children: [
          // ── Content (Map | Journal) — IndexedStack keeps map alive ─────────
          IndexedStack(
            index: _tabController.index,
            children: [
              // Map tab
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: initialTarget,
                  zoom: initialZoom,
                ),
                markers: markers,
                myLocationEnabled:
                    locationStatus == LocationAccessStatus.granted,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapType: MapType.normal,
                onCameraMove: (pos) => _zoom = pos.zoom,
                onCameraMoveStarted: () {
                  // A programmatic move (our own _moveCamera calls) also
                  // triggers this, so only treat it as real user interaction
                  // when nothing we initiated is currently in flight —
                  // otherwise the ambient "follow my location" listener
                  // above would be permanently (and incorrectly) suppressed
                  // the first time we ourselves recenter the map.
                  if (!_isProgrammaticMove) _userInteractedWithMap = true;
                },
                onCameraIdle: () {
                  // Recompute clusters for the new zoom once the camera
                  // settles — not on every drag frame.
                  if (mounted) setState(() {});
                },
                onMapCreated: (c) {
                  _mapController = c;
                  _loadTrace?.stop();
                  _loadTrace = null;
                  if (focusTarget == null && myLocation != null) {
                    _moveCamera(CameraUpdate.newLatLngZoom(myLocation, 13));
                  }
                  // Re-evaluate the focus-flow effect above now that the
                  // controller exists.
                  setState(() {});
                },
              ),
              // Journal tab
              _JournalTab(
                state: memoriesState,
                filtered: filtered,
                onTap: _openModal,
                isDark: isDark,
                reducedMotion: ref.watch(reducedMotionProvider),
                onLoadMore: () =>
                    ref.read(memoriesControllerProvider.notifier).loadMore(),
                onRetry: () =>
                    ref.read(memoriesControllerProvider.notifier).retry(),
                syncFailed: journalSync.hasError && !journalSync.isLoading,
                onRetrySync: () => ref.invalidate(journalSyncProvider),
              ),
            ],
          ),

          // ── Floating header ─────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenHorizontal,
                  AppSpacing.sm,
                  AppSpacing.screenHorizontal,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _TabSwitcherPill(
                          controller: _tabController,
                          count: allMemories.length,
                          isDark: isDark,
                        ),
                        // A small, non-blocking indicator that memories are
                        // still loading — the map itself stays fully
                        // interactive/pannable in the meantime, it just
                        // doesn't have markers to show yet.
                        if (_tabController.index == 0 &&
                            memoriesState.initialLoading) ...[
                          const SizedBox(width: AppSpacing.sm),
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.forestGreen,
                            ),
                          ),
                        ],
                        const Spacer(),
                        if (_tabController.index == 0)
                          if (myLocation != null)
                            _MyLocationButton(
                              isDark: isDark,
                              onTap: () => _moveCamera(
                                CameraUpdate.newLatLngZoom(myLocation, 14),
                              ),
                            )
                          else if (locationStatus != null &&
                              locationStatus != LocationAccessStatus.granted)
                            _EnableLocationButton(
                              isDark: isDark,
                              semanticLabel: switch (locationStatus) {
                                LocationAccessStatus.serviceDisabled =>
                                  'Location services are off. Tap to open settings.',
                                LocationAccessStatus.deniedForever =>
                                  'Location access denied. Tap to enable in Settings.',
                                _ =>
                                  'Location access needed to show your position on the map. Tap to allow.',
                              },
                              onTap: () {
                                final service = ref.read(
                                  locationServiceProvider,
                                );
                                switch (locationStatus) {
                                  case LocationAccessStatus.serviceDisabled:
                                    service.openLocationServiceSettings();
                                  case LocationAccessStatus.deniedForever:
                                    service.openAppSettings();
                                  default:
                                    // Not yet permanently denied — the OS
                                    // may still show its own prompt, so
                                    // simply retry the request instead of
                                    // sending the user to Settings.
                                    ref.invalidate(currentLocationProvider);
                                    ref.invalidate(
                                      locationAccessStatusProvider,
                                    );
                                }
                              },
                            ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _CategoryFilterBar(
                      selected: _selectedCategory,
                      onSelect: (cat) => setState(() {
                        _selectedCategory = _selectedCategory == cat
                            ? null
                            : cat;
                      }),
                      isDark: isDark,
                    ),
                    const SizedBox(height: AppSpacing.sm),
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

// ── Tab switcher pill ─────────────────────────────────────────────────────────

class _TabSwitcherPill extends StatelessWidget {
  const _TabSwitcherPill({
    required this.controller,
    required this.count,
    required this.isDark,
  });

  final TabController controller;
  final int count;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        boxShadow: AppElevation.medium,
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PillTab(
              label: '🗺️ Map',
              selected: controller.index == 0,
              isDark: isDark,
              onTap: () => controller.animateTo(0),
            ),
            _PillTab(
              label: '📖 Journal',
              selected: controller.index == 1,
              badge: count > 0 ? '$count' : null,
              isDark: isDark,
              onTap: () => controller.animateTo(1),
            ),
          ],
        ),
      ),
    );
  }
}

class _PillTab extends StatelessWidget {
  const _PillTab({
    required this.label,
    required this.selected,
    required this.isDark,
    required this.onTap,
    this.badge,
  });

  final String label;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final muted = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.standard,
        curve: AppMotion.transitionCurve,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.forestGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : muted,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 5),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.25)
                      : AppColors.grassGreen.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  child: Text(
                    badge!,
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : AppColors.grassGreen,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── My location button ────────────────────────────────────────────────────────

class _MyLocationButton extends StatelessWidget {
  const _MyLocationButton({required this.isDark, required this.onTap});

  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface.withValues(alpha: 0.95),
        shape: BoxShape.circle,
        boxShadow: AppElevation.medium,
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Semantics(
            button: true,
            label: 'Center map on my location',
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Icon(
                Icons.my_location_rounded,
                color: AppColors.forestGreen,
                size: 22,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Enable location button ────────────────────────────────────────────────────

/// Shown in place of [_MyLocationButton] when location access has been
/// permanently denied or the device's location service is off — the OS
/// won't prompt again in either case, so this is the only way back in.
class _EnableLocationButton extends StatelessWidget {
  const _EnableLocationButton({
    required this.isDark,
    required this.semanticLabel,
    required this.onTap,
  });

  final bool isDark;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final onSurface = isDark
        ? AppColors.onSurfaceDark
        : AppColors.onSurfaceLight;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        boxShadow: AppElevation.medium,
      ),
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          onTap: onTap,
          child: Semantics(
            button: true,
            label: semanticLabel,
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.location_off_rounded,
                    color: AppColors.warmYellow,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Enable Location',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: onSurface,
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

// ── Category filter bar ───────────────────────────────────────────────────────

class _CategoryFilterBar extends StatelessWidget {
  const _CategoryFilterBar({
    required this.selected,
    required this.onSelect,
    required this.isDark,
  });

  final ChallengeCategory? selected;
  final ValueChanged<ChallengeCategory> onSelect;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final muted = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;
    const categories = ChallengeCategory.values;

    // The visible chip stays compact (matches the rest of the filter row's
    // density), but each item's actual hit-test area is padded out to the
    // 48x48 minimum interactive target — an invisible tap area around a
    // small chip, not an enlarged chip.
    return SizedBox(
      height: AppSpacing.xxxl,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (_, i) {
          final cat = categories[i];
          final isSelected = selected == cat;
          return Semantics(
            button: true,
            selected: isSelected,
            label: '${cat.displayName} category filter',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect(cat),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: AppSpacing.xxxl,
                  minHeight: AppSpacing.xxxl,
                ),
                child: Center(
                  child: AnimatedContainer(
                    duration: AppMotion.fast,
                    curve: AppMotion.standardCurve,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.forestGreen
                          : surface.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusFull,
                      ),
                      boxShadow: AppElevation.low,
                    ),
                    child: Text(
                      '${cat.emoji} ${cat.displayName}',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? Colors.white : muted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Journal tab ───────────────────────────────────────────────────────────────

class _JournalTab extends StatefulWidget {
  const _JournalTab({
    required this.state,
    required this.filtered,
    required this.onTap,
    required this.isDark,
    required this.reducedMotion,
    required this.onLoadMore,
    required this.onRetry,
    this.syncFailed = false,
    this.onRetrySync,
  });

  /// Full pagination state (loading/error/hasMore) from the controller.
  final MemoriesState state;

  /// Category-filtered subset of [MemoriesState.memories] to actually display.
  final List<AdventureMemoryModel> filtered;
  final ValueChanged<AdventureMemoryModel> onTap;
  final bool isDark;
  final bool reducedMotion;
  final VoidCallback onLoadMore;
  final VoidCallback onRetry;

  /// The Journal repair (journalSyncProvider) didn't finish: some entries
  /// may be missing until it's retried.
  final bool syncFailed;
  final VoidCallback? onRetrySync;

  @override
  State<_JournalTab> createState() => _JournalTabState();
}

class _JournalTabState extends State<_JournalTab> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!widget.state.hasMore || widget.state.loadingMore) return;
    const threshold = 400.0;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - threshold) {
      widget.onLoadMore();
    }
  }

  // Enough clearance for SafeArea + tab pill + filter bar.
  static const double _headerClearance = 160.0;

  List<(String, List<AdventureMemoryModel>)> _groupByMonth(
    List<AdventureMemoryModel> items,
  ) {
    final map = <String, List<AdventureMemoryModel>>{};
    for (final m in items) {
      final key = DateFormat('MMMM yyyy').format(m.completionDate);
      map.putIfAbsent(key, () => []).add(m);
    }
    return map.entries.map((e) => (e.key, e.value)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final surface = widget.isDark
        ? AppColors.surfaceDark
        : AppColors.surfaceLight;
    final muted = widget.isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;
    final state = widget.state;

    // Initial load failed with nothing on screen yet.
    if (state.error != null &&
        state.memories.isEmpty &&
        !state.initialLoading) {
      return ColoredBox(
        color: surface,
        child: Padding(
          padding: const EdgeInsets.only(top: _headerClearance),
          child: ErrorRetryView(
            message: ErrorService.friendlyMessage(state.error!),
            onRetry: widget.onRetry,
          ),
        ),
      );
    }

    if (state.initialLoading) {
      return ColoredBox(
        color: surface,
        child: const SingleChildScrollView(
          padding: EdgeInsets.only(
            top: _headerClearance,
            left: AppSpacing.screenHorizontal,
            right: AppSpacing.screenHorizontal,
          ),
          child: _JournalSkeleton(),
        ),
      );
    }

    final syncBanner = widget.syncFailed
        ? _JournalSyncBanner(onRetry: widget.onRetrySync, isDark: widget.isDark)
        : null;

    if (widget.filtered.isEmpty) {
      return ColoredBox(
        color: surface,
        child: Padding(
          padding: const EdgeInsets.only(top: _headerClearance),
          child: Column(
            children: [
              ?syncBanner,
              Expanded(
                child: Center(
                  child: state.memories.isEmpty
                      ? const _EmptyJournal()
                      : _NoMatchesEmptyState(muted: muted),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final grouped = _groupByMonth(widget.filtered);
    final lead = syncBanner == null ? 0 : 1;

    return ColoredBox(
      color: surface,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(
          top: _headerClearance,
          bottom: AppSpacing.xxl,
        ),
        // +1 for the trailing load-more/end-of-history footer, +1 for the
        // repair banner when it's showing.
        itemCount: lead + grouped.length + 1,
        itemBuilder: (context, index) {
          if (index < lead) return syncBanner!;
          final i = index - lead;
          if (i == grouped.length) {
            return _JournalFooter(
              loadingMore: state.loadingMore,
              hasMore: state.hasMore,
              hasError: state.error != null,
              onRetry: widget.onRetry,
              isDark: widget.isDark,
            );
          }
          return _MonthSection(
            month: grouped[i].$1,
            memories: grouped[i].$2,
            onTap: widget.onTap,
            isDark: widget.isDark,
            reducedMotion: widget.reducedMotion,
          );
        },
      ),
    );
  }
}

// ── Journal repair banner ────────────────────────────────────────────────────

/// Shown when restoring missing Journal entries failed. Completions and XP
/// are never affected by the repair, so the message says exactly that.
class _JournalSyncBanner extends StatelessWidget {
  const _JournalSyncBanner({required this.onRetry, required this.isDark});
  final VoidCallback? onRetry;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        0,
        AppSpacing.screenHorizontal,
        AppSpacing.md,
      ),
      child: Semantics(
        liveRegion: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: isDark ? 0.18 : 0.08),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.xs,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    "Some Journal entries couldn't be restored yet. Your "
                    'adventures and XP are safe.',
                  ),
                ),
                TextButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Journal skeleton (loading state) ────────────────────────────────────────

class _JournalSkeleton extends StatelessWidget {
  const _JournalSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        3,
        (_) => const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShimmerBox(
                width: 64,
                height: 64,
                borderRadius: BorderRadius.all(
                  Radius.circular(AppSpacing.radiusMd),
                ),
              ),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerBox(width: 90, height: 12),
                    SizedBox(height: 8),
                    ShimmerBox(width: 160, height: 14),
                    SizedBox(height: 8),
                    ShimmerBox(width: 120, height: 11),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Journal pagination footer ───────────────────────────────────────────────

class _JournalFooter extends StatelessWidget {
  const _JournalFooter({
    required this.loadingMore,
    required this.hasMore,
    required this.hasError,
    required this.onRetry,
    required this.isDark,
  });

  final bool loadingMore;
  final bool hasMore;
  final bool hasError;
  final VoidCallback onRetry;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final muted = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;

    if (loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.forestGreen,
            ),
          ),
        ),
      );
    }

    if (hasError) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Couldn\'t load more adventures.',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: muted,
              ),
            ),
            Semantics(
              button: true,
              label: 'Retry loading more adventures',
              excludeSemantics: true,
              child: TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  minimumSize: const Size(AppSpacing.xxxl, AppSpacing.xxxl),
                ),
                child: const Text('Retry'),
              ),
            ),
          ],
        ),
      );
    }

    if (!hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(
          child: Text(
            'That\'s your whole adventure history.',
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: muted,
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

// ── Month section ─────────────────────────────────────────────────────────────

class _MonthSection extends StatelessWidget {
  const _MonthSection({
    required this.month,
    required this.memories,
    required this.onTap,
    required this.isDark,
    required this.reducedMotion,
  });

  final String month;
  final List<AdventureMemoryModel> memories;
  final ValueChanged<AdventureMemoryModel> onTap;
  final bool isDark;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final muted = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenHorizontal,
            AppSpacing.lg,
            AppSpacing.screenHorizontal,
            AppSpacing.sm,
          ),
          child: Text(
            month.toUpperCase(),
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: muted,
              letterSpacing: 1.0,
            ),
          ),
        ),
        ...memories.map(
          (m) => _JournalTile(
            memory: m,
            onTap: () => onTap(m),
            isDark: isDark,
            reducedMotion: reducedMotion,
          ),
        ),
      ],
    );
  }
}

// ── Journal tile ──────────────────────────────────────────────────────────────

class _JournalTile extends StatelessWidget {
  const _JournalTile({
    required this.memory,
    required this.onTap,
    required this.isDark,
    required this.reducedMotion,
  });

  final AdventureMemoryModel memory;
  final VoidCallback onTap;
  final bool isDark;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final surfaceVar = isDark
        ? AppColors.surfaceVariantDark
        : AppColors.surfaceVariantLight;
    final strong = isDark ? AppColors.onSurfaceDark : AppColors.onSurfaceLight;
    final muted = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;

    final locationPart = memory.hasLocation
        ? ', ${memory.displayLocation}'
        : '';
    final semanticLabel =
        '${memory.challengeTitle}, '
        '${memory.challengeCategory.displayName}, '
        'completed ${DateFormat('MMMM d').format(memory.completionDate)}'
        '$locationPart, +${memory.xpEarned} XP';

    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = isDark ? AppColors.outlineDark : AppColors.outlineLight;

    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: PressableScale(
        enabled: !reducedMotion,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenHorizontal,
            vertical: AppSpacing.xs,
          ),
          // A journal entry should read as something collectible — a plain
          // list row (the previous look) doesn't communicate that the same
          // way an achievement card's card-shell treatment already does
          // elsewhere in the app.
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              border: Border.all(color: border, width: 1),
              boxShadow: AppElevation.low,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Thumbnail
                      ClipRRect(
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMd,
                        ),
                        child: memory.photoUrl.isEmpty
                            ? DecoratedBox(
                                decoration: BoxDecoration(
                                  color: surfaceVar,
                                  borderRadius: BorderRadius.circular(
                                    AppSpacing.radiusMd,
                                  ),
                                ),
                                child: SizedBox(
                                  width: 64,
                                  height: 64,
                                  child: Center(
                                    child: Text(
                                      memory.challengeEmoji,
                                      style: const TextStyle(fontSize: 28),
                                    ),
                                  ),
                                ),
                              )
                            : CachedNetworkImage(
                                imageUrl: memory.photoUrl,
                                width: 64,
                                height: 64,
                                fit: BoxFit.cover,
                                placeholder: (ctx, url) =>
                                    const ShimmerBox(width: 64, height: 64),
                                errorWidget: (ctx, url, err) => DecoratedBox(
                                  decoration: BoxDecoration(color: surfaceVar),
                                  child: SizedBox(
                                    width: 64,
                                    height: 64,
                                    child: Center(
                                      child: Text(
                                        memory.challengeEmoji,
                                        style: const TextStyle(fontSize: 28),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      // Content
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _DayBadge(day: memory.challengeDay),
                                const SizedBox(width: AppSpacing.sm),
                                Text(
                                  DateFormat(
                                    'MMM d',
                                  ).format(memory.completionDate),
                                  style: TextStyle(
                                    fontFamily: 'Nunito',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: muted,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              memory.challengeTitle,
                              style: TextStyle(
                                fontFamily: 'Nunito',
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: strong,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Text(
                                  '${memory.challengeCategory.emoji} '
                                  '${memory.challengeCategory.displayName}',
                                  style: TextStyle(
                                    fontFamily: 'Nunito',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: muted,
                                  ),
                                ),
                                if (memory.hasLocation) ...[
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.location_on_rounded,
                                    size: 10,
                                    color: AppColors.forestGreenLight,
                                  ),
                                  const SizedBox(width: 2),
                                  Expanded(
                                    child: Text(
                                      memory.displayLocation,
                                      style: TextStyle(
                                        fontFamily: 'Nunito',
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: muted,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (memory.hasCaption) ...[
                              const SizedBox(height: 4),
                              Text(
                                memory.caption!,
                                style: TextStyle(
                                  fontFamily: 'Nunito',
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                  color: muted,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      // XP
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        '+${memory.xpEarned} XP',
                        style: const TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.forestGreenLight,
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
    );
  }
}

// ── Empty journal ─────────────────────────────────────────────────────────────

class _EmptyJournal extends StatelessWidget {
  const _EmptyJournal();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxl,
        vertical: AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('📖', style: TextStyle(fontSize: 48)),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Your adventure journal is waiting.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: muted,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Complete your first challenge to start building\n'
            'your map of memories.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: muted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: 'Start Today\'s Challenge',
            onPressed: () => context.pushNamed('camera'),
            expand: false,
          ),
        ],
      ),
    );
  }
}

class _NoMatchesEmptyState extends StatelessWidget {
  const _NoMatchesEmptyState({required this.muted});
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('🔍', style: TextStyle(fontSize: 40)),
        const SizedBox(height: AppSpacing.md),
        Text(
          'No adventures in this category yet.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: muted,
          ),
        ),
      ],
    );
  }
}

// ── Memory detail modal ───────────────────────────────────────────────────────

class _MemoryDetailModal extends ConsumerStatefulWidget {
  const _MemoryDetailModal({required this.memory});
  final AdventureMemoryModel memory;

  @override
  ConsumerState<_MemoryDetailModal> createState() => _MemoryDetailModalState();
}

class _MemoryDetailModalState extends ConsumerState<_MemoryDetailModal> {
  bool _editingCaption = false;
  bool _saving = false;
  late final TextEditingController _captionController;

  @override
  void initState() {
    super.initState();
    _captionController = TextEditingController(
      text: widget.memory.caption ?? '',
    );
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _saveCaption() async {
    final text = _captionController.text.trim();
    setState(() => _saving = true);

    final result = await ref
        .read(memoryRepositoryProvider)
        .updateCaption(
          userId: widget.memory.userId,
          memoryId: widget.memory.memoryId,
          newCaption: text,
        );

    if (!mounted) return;
    result.when(
      ok: (_) => Navigator.of(context).pop(),
      err: (e) {
        setState(() => _saving = false);
        ErrorService.showError(context, e);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final surfaceVar = isDark
        ? AppColors.surfaceVariantDark
        : AppColors.surfaceVariantLight;
    final strong = isDark ? AppColors.onSurfaceDark : AppColors.onSurfaceLight;
    final muted = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;
    final m = widget.memory;

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => DecoratedBox(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radiusBottomSheet),
          ),
          boxShadow: AppElevation.high,
        ),
        child: Column(
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.outlineDark
                        : AppColors.outlineLight,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  ),
                  child: const SizedBox(width: 36, height: 4),
                ),
              ),
            ),

            // Scrollable body
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: AppSpacing.sm),

                    // Hero photo — full width, no border radius for edge-to-edge feel
                    if (m.photoUrl.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: m.photoUrl,
                        width: double.infinity,
                        height: 220,
                        fit: BoxFit.cover,
                        placeholder: (ctx, url) => const ShimmerBox(
                          width: double.infinity,
                          height: 220,
                        ),
                        errorWidget: (ctx, url, err) => DecoratedBox(
                          decoration: BoxDecoration(color: surfaceVar),
                          child: SizedBox(
                            height: 220,
                            child: Center(
                              child: Text(
                                m.challengeEmoji,
                                style: const TextStyle(fontSize: 48),
                              ),
                            ),
                          ),
                        ),
                      ),

                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.screenHorizontal,
                        AppSpacing.md,
                        AppSpacing.screenHorizontal,
                        AppSpacing.xxl,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Day badge + title
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _DayBadge(day: m.challengeDay),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  m.challengeTitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Nunito',
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: strong,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),

                          // Category + date
                          Wrap(
                            spacing: AppSpacing.md,
                            runSpacing: 4,
                            children: [
                              Text(
                                '${m.challengeCategory.emoji} '
                                '${m.challengeCategory.displayName}',
                                style: TextStyle(
                                  fontFamily: 'Nunito',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: muted,
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.calendar_today_rounded,
                                    size: 12,
                                    color: muted,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    DateFormat(
                                      'EEE, MMM d y · h:mm a',
                                    ).format(m.completionDate),
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
                          const SizedBox(height: AppSpacing.sm),

                          // XP + verification badges
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: [
                              _Badge(
                                label: '+${m.xpEarned} XP',
                                bgColor: AppColors.grassGreen.withValues(
                                  alpha: 0.14,
                                ),
                                textColor: AppColors.forestGreenLight,
                              ),
                              _Badge(
                                label: m.verificationLabel,
                                bgColor:
                                    (m.isAiVerified
                                            ? AppColors.skyBlue
                                            : AppColors.warmYellow)
                                        .withValues(alpha: 0.14),
                                textColor: m.isAiVerified
                                    ? AppColors.skyBlue
                                    : AppColors.warmYellow,
                              ),
                            ],
                          ),

                          const SizedBox(height: AppSpacing.md),
                          Divider(
                            color: isDark
                                ? AppColors.dividerDark
                                : AppColors.dividerLight,
                          ),
                          const SizedBox(height: AppSpacing.sm),

                          // Location + weather chips
                          if (m.hasLocation || m.hasWeather) ...[
                            Wrap(
                              spacing: AppSpacing.sm,
                              runSpacing: AppSpacing.sm,
                              children: [
                                if (m.hasLocation)
                                  _InfoChip(
                                    icon: Icons.location_on_rounded,
                                    iconColor: AppColors.forestGreenLight,
                                    label: m.displayLocation,
                                    isDark: isDark,
                                  ),
                                if (m.hasWeather)
                                  _InfoChip(
                                    emoji: m.weatherEmoji,
                                    label: m.weatherDisplay,
                                    isDark: isDark,
                                  ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.md),
                          ],

                          // Reflection prompt (Gemini question)
                          if (m.captionPrompt != null) ...[
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: AppColors.skyBlue.withValues(
                                  alpha: 0.08,
                                ),
                                borderRadius: BorderRadius.circular(
                                  AppSpacing.radiusMd,
                                ),
                                border: Border.all(
                                  color: AppColors.skyBlue.withValues(
                                    alpha: 0.2,
                                  ),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '💭',
                                      style: TextStyle(fontSize: 16),
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Expanded(
                                      child: Text(
                                        m.captionPrompt!,
                                        style: TextStyle(
                                          fontFamily: 'Nunito',
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          fontStyle: FontStyle.italic,
                                          color: muted,
                                          height: 1.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                          ],

                          // User reflection (caption)
                          _CaptionSection(
                            memory: m,
                            editingCaption: _editingCaption,
                            saving: _saving,
                            controller: _captionController,
                            isDark: isDark,
                            onEdit: () =>
                                setState(() => _editingCaption = true),
                            onCancel: () => setState(() {
                              _editingCaption = false;
                              _captionController.text = m.caption ?? '';
                            }),
                            onSave: _saveCaption,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Caption section ───────────────────────────────────────────────────────────

class _CaptionSection extends StatelessWidget {
  const _CaptionSection({
    required this.memory,
    required this.editingCaption,
    required this.saving,
    required this.controller,
    required this.isDark,
    required this.onEdit,
    required this.onCancel,
    required this.onSave,
  });

  final AdventureMemoryModel memory;
  final bool editingCaption;
  final bool saving;
  final TextEditingController controller;
  final bool isDark;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final surfaceVar = isDark
        ? AppColors.surfaceVariantDark
        : AppColors.surfaceVariantLight;
    final strong = isDark ? AppColors.onSurfaceDark : AppColors.onSurfaceLight;
    final muted = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;

    // Editing mode — text field + save/cancel
    if (editingCaption) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            maxLines: 4,
            autofocus: true,
            style: TextStyle(fontFamily: 'Nunito', fontSize: 14, color: strong),
            decoration: InputDecoration(
              hintText: 'Write your reflection…',
              hintStyle: TextStyle(color: muted),
              filled: true,
              fillColor: surfaceVar,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: saving ? null : onCancel,
                child: Text(
                  'Cancel',
                  style: TextStyle(fontFamily: 'Nunito', color: muted),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton(
                onPressed: saving ? null : onSave,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.forestGreen,
                ),
                child: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Save',
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ],
          ),
        ],
      );
    }

    // Has caption — display with Edit button
    if (memory.hasCaption) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Your Reflection',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: muted,
                ),
              ),
              const Spacer(),
              Semantics(
                button: true,
                label: 'Edit reflection',
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: onEdit,
                  child: const Text(
                    'Edit',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.forestGreenLight,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          DecoratedBox(
            decoration: BoxDecoration(
              color: surfaceVar,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('✍️', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      memory.caption!,
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontStyle: FontStyle.italic,
                        color: strong,
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // No caption yet — prompt to add one
    return GestureDetector(
      onTap: onEdit,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: surfaceVar.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(
            color: AppColors.forestGreenLight.withValues(alpha: 0.3),
          ),
        ),
        child: const Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.edit_note_rounded,
                color: AppColors.forestGreenLight,
                size: 20,
              ),
              SizedBox(width: AppSpacing.sm),
              Text(
                'Add your reflection…',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.forestGreenLight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared small widgets ──────────────────────────────────────────────────────

class _DayBadge extends StatelessWidget {
  const _DayBadge({required this.day});
  final int day;

  @override
  Widget build(BuildContext context) {
    // 0 = unknown (an entry restored after its challenge was gone).
    if (day <= 0) return const SizedBox.shrink();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.forestGreen.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          'Day $day',
          style: const TextStyle(
            fontFamily: 'Nunito',
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: AppColors.forestGreen,
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.bgColor,
    required this.textColor,
  });

  final String label;
  final Color bgColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: textColor,
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    this.icon,
    this.emoji,
    this.iconColor,
    required this.label,
    required this.isDark,
  });

  final IconData? icon;
  final String? emoji;
  final Color? iconColor;
  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final surfaceVar = isDark
        ? AppColors.surfaceVariantDark
        : AppColors.surfaceVariantLight;
    final muted = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surfaceVar,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (emoji != null)
              Text(emoji!, style: const TextStyle(fontSize: 13))
            else if (icon != null)
              Icon(icon!, size: 13, color: iconColor ?? muted),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
