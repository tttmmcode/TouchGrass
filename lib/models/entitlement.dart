/// A user's AI-verification entitlement tier.
///
/// Server-trustworthy by construction, not by convention: `entitlementTier`
/// is deliberately absent from firestore.rules' `isValidUserWrite()` allowed
/// field list (see that file), so the client can never set or change it via
/// a normal document write — only the Admin SDK (a Cloud Function, or a
/// manual Firebase Console edit) can grant [premium] or [adminTest]. A user
/// document with no `entitlementTier` field at all (every user today, since
/// nothing currently writes it) defaults to [free] — see
/// [EntitlementTierX.fromString].
enum EntitlementTier { free, premium, adminTest }

extension EntitlementTierX on EntitlementTier {
  String get id => switch (this) {
    EntitlementTier.free => 'free',
    EntitlementTier.premium => 'premium',
    EntitlementTier.adminTest => 'admin_test',
  };

  /// True for any tier that's actually allowed to use AI verification.
  /// [free] is the only tier gated off — this is what "Coming Soon" /
  /// locked messaging should check.
  bool get canUseAiVerification => this != EntitlementTier.free;

  /// Verifications allowed per period. [adminTest] is unlimited (used only
  /// for controlled internal testing, never granted to a normal user by any
  /// client-writable path) — represented as -1, meaning "no cap", rather
  /// than a very large number, so callers can't accidentally hit a real
  /// ceiling.
  int get periodQuota => switch (this) {
    EntitlementTier.free => 0,
    EntitlementTier.premium => 30,
    EntitlementTier.adminTest => -1,
  };

  static EntitlementTier fromString(String? value) => switch (value) {
    'premium' => EntitlementTier.premium,
    'admin_test' => EntitlementTier.adminTest,
    _ => EntitlementTier.free,
  };
}
