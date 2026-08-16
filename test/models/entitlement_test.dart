// Unit tests for EntitlementTier — the client-side mirror of the tier logic
// enforced authoritatively in functions/src/rewards.ts. entitlementTier
// itself is never client-writable (see entitlement.dart's doc comment), but
// once read from Firestore, its parsing/gating rules must be exactly right.

import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/models/entitlement.dart';

void main() {
  group('EntitlementTierX.fromString', () {
    test('recognizes all valid tier strings', () {
      expect(EntitlementTierX.fromString('free'), EntitlementTier.free);
      expect(EntitlementTierX.fromString('premium'), EntitlementTier.premium);
      expect(
        EntitlementTierX.fromString('admin_test'),
        EntitlementTier.adminTest,
      );
    });

    test('defaults to free for null, missing, or unrecognized values', () {
      expect(EntitlementTierX.fromString(null), EntitlementTier.free);
      expect(EntitlementTierX.fromString(''), EntitlementTier.free);
      expect(EntitlementTierX.fromString('gold'), EntitlementTier.free);
      expect(EntitlementTierX.fromString('Premium'), EntitlementTier.free);
    });
  });

  group('EntitlementTierX.canUseAiVerification', () {
    test('free cannot use AI verification', () {
      expect(EntitlementTier.free.canUseAiVerification, isFalse);
    });

    test('premium and adminTest can', () {
      expect(EntitlementTier.premium.canUseAiVerification, isTrue);
      expect(EntitlementTier.adminTest.canUseAiVerification, isTrue);
    });
  });

  group('EntitlementTierX.periodQuota', () {
    test('free has zero quota', () {
      expect(EntitlementTier.free.periodQuota, 0);
    });

    test('premium has a finite positive quota', () {
      expect(EntitlementTier.premium.periodQuota, 30);
    });

    test('adminTest is unlimited, represented as -1 not a large number', () {
      expect(EntitlementTier.adminTest.periodQuota, -1);
    });
  });

  group('EntitlementTierX.id', () {
    test('round-trips through fromString for every tier', () {
      for (final tier in EntitlementTier.values) {
        expect(EntitlementTierX.fromString(tier.id), tier);
      }
    });
  });
}
