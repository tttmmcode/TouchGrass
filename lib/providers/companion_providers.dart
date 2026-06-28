import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../companions/companion.dart';
import 'user_providers.dart';

/// The companion type the current user has selected.
/// Falls back to [CompanionType.sprout] when no preference is stored.
final activeCompanionProvider = Provider<CompanionType>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  final typeName = user?.settings.companionType ?? 'sprout';
  return CompanionType.values.firstWhere(
    (t) => t.name == typeName,
    orElse: () => CompanionType.sprout,
  );
});
