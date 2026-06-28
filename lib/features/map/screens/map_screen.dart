import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';

import '../../../models/adventure_memory_model.dart';
import '../../../models/challenge_model.dart';
import '../../../providers/map_providers.dart';
import '../../../providers/memory_providers.dart';
import '../../../services/perf_service.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';

// ── Screen ────────────────────────────────────────────────────────────────────

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  GoogleMapController? _mapController;
  ChallengeCategory? _selectedCategory;
  Trace? _loadTrace;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadTrace = PerfService.startTrace(PerfService.traceMapLoad);
  }

  void _onTabChanged() {
    // Only rebuild when the tab has fully settled — not on every animation frame.
    if (!_tabController.indexIsChanging) setState(() {});
  }

  @override
  void dispose() {
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

  Set<Marker> _buildMarkers(List<AdventureMemoryModel> memories) {
    // Count how many markers share each position so we can spread them out.
    final stackCount = <String, int>{};
    return memories
        .where((m) => m.hasLocation)
        .map((m) {
          final key =
              '${m.latitude!.toStringAsFixed(5)},${m.longitude!.toStringAsFixed(5)}';
          final n = stackCount[key] ?? 0;
          stackCount[key] = n + 1;
          // Spiral-offset overlapping pins by ~5 m so each is individually tappable.
          final angle = n * 2.4; // golden-angle spread
          final dist = n == 0 ? 0.0 : 0.00005 * math.sqrt(n.toDouble());
          final lat = m.latitude! + dist * math.cos(angle);
          final lng = m.longitude! + dist * math.sin(angle);
          return Marker(
            markerId: MarkerId(m.memoryId),
            position: LatLng(lat, lng),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              _hueForCategory(m.challengeCategory),
            ),
            onTap: () => _showMemoryModal(m),
          );
        })
        .toSet();
  }

  void _showMemoryModal(AdventureMemoryModel memory) {
    _mapController?.animateCamera(
      CameraUpdate.newLatLng(LatLng(memory.latitude!, memory.longitude!)),
    );
    _openModal(memory);
  }

  void _openModal(AdventureMemoryModel memory) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MemoryDetailModal(memory: memory),
    );
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
    final memoriesAsync = ref.watch(memoriesProvider);
    final allMemories = memoriesAsync.valueOrNull ?? [];
    final filtered = _filter(allMemories);
    final markers = _buildMarkers(filtered);
    final locationAsync = ref.watch(currentLocationProvider);
    final myLocation = locationAsync.valueOrNull;

    ref.listen(currentLocationProvider, (_, next) {
      if (next.hasValue && next.valueOrNull != null) {
        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(next.value!, 13),
        );
      }
    });

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
                  target: myLocation ?? const LatLng(20.0, 0.0),
                  zoom: myLocation != null ? 13.0 : 2.0,
                ),
                markers: markers,
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapType: MapType.normal,
                onMapCreated: (c) {
                  _mapController = c;
                  _loadTrace?.stop();
                  _loadTrace = null;
                  if (myLocation != null) {
                    c.animateCamera(
                      CameraUpdate.newLatLngZoom(myLocation, 13),
                    );
                  }
                },
              ),
              // Journal tab
              _JournalTab(
                memories: filtered,
                isLoading: memoriesAsync.isLoading,
                onTap: _openModal,
                isDark: isDark,
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
                        const Spacer(),
                        if (_tabController.index == 0 && myLocation != null)
                          _MyLocationButton(
                            isDark: isDark,
                            onTap: () => _mapController?.animateCamera(
                              CameraUpdate.newLatLngZoom(myLocation, 14),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _CategoryFilterBar(
                      selected: _selectedCategory,
                      onSelect: (cat) => setState(() {
                        _selectedCategory =
                            _selectedCategory == cat ? null : cat;
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
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
        duration: const Duration(milliseconds: 200),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
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

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (_, i) {
          final cat = categories[i];
          final isSelected = selected == cat;
          return GestureDetector(
            onTap: () => onSelect(cat),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.forestGreen
                    : surface.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
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
          );
        },
      ),
    );
  }
}

// ── Journal tab ───────────────────────────────────────────────────────────────

class _JournalTab extends StatelessWidget {
  const _JournalTab({
    required this.memories,
    required this.isLoading,
    required this.onTap,
    required this.isDark,
  });

  final List<AdventureMemoryModel> memories;
  final bool isLoading;
  final ValueChanged<AdventureMemoryModel> onTap;
  final bool isDark;

  // Enough clearance for SafeArea + tab pill + filter bar.
  static const double _headerClearance = 160.0;

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final muted = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;

    if (isLoading) {
      return ColoredBox(
        color: surface,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (memories.isEmpty) {
      return ColoredBox(
        color: surface,
        child: Padding(
          padding: const EdgeInsets.only(top: _headerClearance),
          child: Center(child: _EmptyJournal(muted: muted)),
        ),
      );
    }

    final grouped = _groupByMonth(memories);

    return ColoredBox(
      color: surface,
      child: ListView.builder(
        padding: const EdgeInsets.only(
          top: _headerClearance,
          bottom: AppSpacing.xxl,
        ),
        itemCount: grouped.length,
        itemBuilder: (context, i) => _MonthSection(
          month: grouped[i].$1,
          memories: grouped[i].$2,
          onTap: onTap,
          isDark: isDark,
        ),
      ),
    );
  }

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
}

// ── Month section ─────────────────────────────────────────────────────────────

class _MonthSection extends StatelessWidget {
  const _MonthSection({
    required this.month,
    required this.memories,
    required this.onTap,
    required this.isDark,
  });

  final String month;
  final List<AdventureMemoryModel> memories;
  final ValueChanged<AdventureMemoryModel> onTap;
  final bool isDark;

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
  });

  final AdventureMemoryModel memory;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final surfaceVar = isDark
        ? AppColors.surfaceVariantDark
        : AppColors.surfaceVariantLight;
    final strong = isDark ? AppColors.onSurfaceDark : AppColors.onSurfaceLight;
    final muted = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenHorizontal,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              child: memory.photoUrl.isEmpty
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        color: surfaceVar,
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusMd),
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
                      placeholder: (ctx, url) => Shimmer.fromColors(
                        baseColor: Colors.grey.shade300,
                        highlightColor: Colors.grey.shade100,
                        child: const SizedBox(
                          width: 64,
                          height: 64,
                          child: ColoredBox(color: Colors.white),
                        ),
                      ),
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
                        DateFormat('MMM d').format(memory.completionDate),
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
    );
  }
}

// ── Empty journal ─────────────────────────────────────────────────────────────

class _EmptyJournal extends StatelessWidget {
  const _EmptyJournal({required this.muted});
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('📖', style: TextStyle(fontSize: 48)),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Your adventure journal\nstarts with your first challenge!',
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
    _captionController =
        TextEditingController(text: widget.memory.caption ?? '');
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _saveCaption() async {
    final text = _captionController.text.trim();
    setState(() => _saving = true);

    final result = await ref.read(memoryRepositoryProvider).updateCaption(
          userId: widget.memory.userId,
          memoryId: widget.memory.memoryId,
          newCaption: text,
        );

    if (!mounted) return;
    result.when(
      ok: (_) => Navigator.of(context).pop(),
      err: (e) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: AppColors.error,
          ),
        );
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
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 16,
              offset: const Offset(0, -2),
            ),
          ],
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
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusFull),
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
                        placeholder: (ctx, url) => Shimmer.fromColors(
                          baseColor: Colors.grey.shade300,
                          highlightColor: Colors.grey.shade100,
                          child: const SizedBox(
                            height: 220,
                            child: ColoredBox(color: Colors.white),
                          ),
                        ),
                        errorWidget: (ctx, url, err) => DecoratedBox(
                          decoration: BoxDecoration(color: surfaceVar),
                          child: const SizedBox(
                            height: 220,
                            child: Center(
                              child: Icon(
                                Icons.broken_image_rounded,
                                size: 48,
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
                                    DateFormat('EEE, MMM d y · h:mm a')
                                        .format(m.completionDate),
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
                                bgColor: AppColors.grassGreen
                                    .withValues(alpha: 0.14),
                                textColor: AppColors.forestGreenLight,
                              ),
                              _Badge(
                                label: m.verificationMethod == 'ai_verified'
                                    ? '🤖 AI Verified'
                                    : '✋ Manual Submit',
                                bgColor: (m.verificationMethod == 'ai_verified'
                                        ? AppColors.skyBlue
                                        : AppColors.warmYellow)
                                    .withValues(alpha: 0.14),
                                textColor:
                                    m.verificationMethod == 'ai_verified'
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
                                color: AppColors.skyBlue
                                    .withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(
                                    AppSpacing.radiusMd),
                                border: Border.all(
                                  color: AppColors.skyBlue
                                      .withValues(alpha: 0.2),
                                ),
                              ),
                              child: Padding(
                                padding:
                                    const EdgeInsets.all(AppSpacing.md),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
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
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 14,
              color: strong,
            ),
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
              GestureDetector(
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
