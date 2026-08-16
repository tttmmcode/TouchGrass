import 'package:flutter/material.dart';

// ── League background motif ───────────────────────────────────────────────────

/// The painted-artwork family a league's static background belongs to (see
/// `LeagueBackground` in the leaderboard feature). Leagues within the same
/// motif share one parameterized `CustomPainter` rather than each getting a
/// fully bespoke implementation — [LeagueDef.backgroundIntensity] is what
/// actually differentiates leagues inside a family (e.g. Forest → Mountain →
/// Summit all use [peaks], growing taller/sparser as intensity increases).
enum LeagueBackgroundMotif {
  /// Seedling, Sprout, Wildflower — soft rounded leaf/petal silhouettes plus
  /// a gentle radial glow, growing lusher with intensity.
  botanical,

  /// Forest, Mountain, Summit — layered triangular silhouettes; many small
  /// "trees" at low intensity, fewer/taller/sharper peaks at high intensity.
  peaks,

  /// Sky Trail, Aurora — soft drifting cloud blobs at low intensity,
  /// sweeping abstract aurora ribbons at high intensity.
  sky,
}

// ── League definition ─────────────────────────────────────────────────────────

@immutable
class LeagueDef {
  const LeagueDef({
    required this.id,
    required this.name,
    required this.emoji,
    required this.color,
    required this.minXp,
    required this.maxXp,
    required this.description,
    required this.promotionNote,
    required this.backgroundMotif,
    required this.backgroundIntensity,
  });

  final String id;
  final String name;
  final String emoji;
  final Color color;
  final int minXp;

  /// -1 means no upper cap (top league).
  final int maxXp;
  final String description;
  final String promotionNote;

  /// Which painted-artwork family this league's static background uses.
  final LeagueBackgroundMotif backgroundMotif;

  /// 0.0–1.0 — how "advanced" this league reads within its
  /// [backgroundMotif] family (e.g. Wildflower's botanical artwork is
  /// lusher/denser than Seedling's). Not related to gameplay difficulty,
  /// purely an art-direction parameter.
  final double backgroundIntensity;

  bool get isTop => maxXp == -1;

  String get xpRangeLabel => maxXp == -1 ? '$minXp+ XP' : '$minXp–$maxXp XP';

  // ── All 8 leagues ─────────────────────────────────────────────────────────

  static const List<LeagueDef> all = [
    LeagueDef(
      id: 'seedling',
      name: 'Seedling',
      emoji: '🌱',
      color: Color(0xFF8BC34A),
      minXp: 0,
      maxXp: 299,
      description: 'Your outdoor journey begins here',
      promotionNote: 'Reach 300 XP total to advance to Sprout',
      backgroundMotif: LeagueBackgroundMotif.botanical,
      backgroundIntensity: 0.15,
    ),
    LeagueDef(
      id: 'sprout',
      name: 'Sprout',
      emoji: '🌿',
      color: Color(0xFF43A047),
      minXp: 300,
      maxXp: 699,
      description: 'Growing roots in the great outdoors',
      promotionNote: 'Reach 700 XP total to advance to Wildflower',
      backgroundMotif: LeagueBackgroundMotif.botanical,
      backgroundIntensity: 0.55,
    ),
    LeagueDef(
      id: 'wildflower',
      name: 'Wildflower',
      emoji: '🌸',
      color: Color(0xFFE91E8C),
      minXp: 700,
      maxXp: 1499,
      description: 'Blooming with every adventure',
      promotionNote: 'Reach 1500 XP total to advance to Forest',
      backgroundMotif: LeagueBackgroundMotif.botanical,
      backgroundIntensity: 1.0,
    ),
    LeagueDef(
      id: 'forest',
      name: 'Forest',
      emoji: '🌲',
      color: Color(0xFF2E7D32),
      minXp: 1500,
      maxXp: 2999,
      description: 'Deep in the heart of nature',
      promotionNote: 'Reach 3000 XP total to advance to Mountain',
      backgroundMotif: LeagueBackgroundMotif.peaks,
      backgroundIntensity: 0.2,
    ),
    LeagueDef(
      id: 'mountain',
      name: 'Mountain',
      emoji: '🏔️',
      color: Color(0xFF5C6BC0),
      minXp: 3000,
      maxXp: 5999,
      description: 'Rising above and beyond',
      promotionNote: 'Reach 6000 XP total to advance to Summit',
      backgroundMotif: LeagueBackgroundMotif.peaks,
      backgroundIntensity: 0.6,
    ),
    LeagueDef(
      id: 'summit',
      name: 'Summit',
      emoji: '✨',
      color: Color(0xFFFFB800),
      minXp: 6000,
      maxXp: 9999,
      description: 'At the peak of outdoor excellence',
      promotionNote: 'Reach 10 000 XP total to advance to Sky Trail',
      backgroundMotif: LeagueBackgroundMotif.peaks,
      backgroundIntensity: 1.0,
    ),
    LeagueDef(
      id: 'sky_trail',
      name: 'Sky Trail',
      emoji: '🌤️',
      color: Color(0xFF00B4D8),
      minXp: 10000,
      maxXp: 19999,
      description: 'Among the clouds, beyond the peaks',
      promotionNote: 'Reach 20 000 XP total to advance to Aurora',
      backgroundMotif: LeagueBackgroundMotif.sky,
      backgroundIntensity: 0.3,
    ),
    LeagueDef(
      id: 'aurora',
      name: 'Aurora',
      emoji: '🌌',
      color: Color(0xFF7B2FBE),
      minXp: 20000,
      maxXp: -1,
      description: 'A legend of the outdoors',
      promotionNote: 'Maximum league — you have reached the top!',
      backgroundMotif: LeagueBackgroundMotif.sky,
      backgroundIntensity: 1.0,
    ),
  ];

  // ── Lookups ────────────────────────────────────────────────────────────────

  /// Returns the league the user belongs to based on total XP.
  static LeagueDef forXp(int xp) {
    for (int i = all.length - 1; i >= 0; i--) {
      if (xp >= all[i].minXp) return all[i];
    }
    return all.first;
  }

  /// String ID (e.g. `'forest'`) for the given total XP.
  static String idForXp(int xp) => forXp(xp).id;

  /// Returns the definition with [id], or `null` if not found.
  static LeagueDef? withId(String id) {
    try {
      return all.firstWhere((l) => l.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Index of this league within [all] (0 = Seedling, 7 = Aurora).
  int get index => all.indexWhere((l) => l.id == id);

  /// `true` if [other] is a higher league than this one.
  bool isLockedFor(LeagueDef current) => index > current.index;
}
