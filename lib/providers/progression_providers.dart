import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/progression_model.dart';
import 'user_providers.dart';

// ── Derived progression data ──────────────────────────────────────────────────

/// Real-time [ProgressionModel] for the signed-in user.
///
/// Derives from [currentUserProvider] — no extra Firestore reads.
/// Widgets that need XP / level / streak / Rainy Days should watch this
/// instead of [currentUserProvider] directly.
final progressionProvider = Provider<AsyncValue<ProgressionModel?>>((ref) {
  return ref
      .watch(currentUserProvider)
      .whenData(
        (user) => user == null ? null : ProgressionModel.fromUser(user),
      );
});
