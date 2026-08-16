import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/entitlement.dart';
import 'user_providers.dart';

/// The signed-in user's current AI-verification entitlement tier.
///
/// Defaults to [EntitlementTier.free] both when signed out and when the
/// user document simply has no `entitlementTier` field yet (every user
/// today) — never assume premium on missing data.
final entitlementTierProvider = Provider<EntitlementTier>((ref) {
  return ref.watch(currentUserProvider).valueOrNull?.entitlementTier ??
      EntitlementTier.free;
});

/// Whether the current user's tier allows AI verification at all. Does NOT
/// check remaining quota — pair with `users/{uid}/aiUsage/{periodKey}` (read
/// via Firestore directly where needed) for "X of N used this period" UI.
///
/// Not yet consumed by the live camera/verification flow — see
/// functions/README.md and the master implementation report for why gating
/// is built but intentionally not turned on yet (it would break AI
/// verification, currently unrestricted, for every existing user).
final canUseAiVerificationProvider = Provider<bool>((ref) {
  return ref.watch(entitlementTierProvider).canUseAiVerification;
});
