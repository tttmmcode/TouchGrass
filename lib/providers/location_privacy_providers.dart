import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/location_history_repository.dart';
import 'user_providers.dart';

/// Whether the user allows *optional* location use (audit D-09) — the
/// "Save location with adventures" setting (`settings.locationEnabled`).
///
/// When false, the app does not:
/// - save coordinates, place names or weather with completions or Journal
///   entries (firestore.rules enforce this too);
/// - send coordinates to Open-Meteo (weather) or the platform geocoder
///   (place names).
///
/// Essential, user-requested location use is not gated by this: showing the
/// user's own position on the map they opened happens on the device and is
/// never saved or sent anywhere by the app.
///
/// Fails closed: false until the profile has loaded, so nothing optional
/// happens before the user's choice is known.
final optionalLocationAllowedProvider = Provider<bool>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  return user?.settings.locationEnabled ?? false;
});

/// True once AppShell has given the location permission primer its chance
/// to show (audit D-14). Anything that may trigger the OS location prompt
/// outside a user action waits for this, so the primer always comes first.
/// The primer shows once ever, so on later launches this flips almost
/// immediately.
final locationPrimerDoneProvider = StateProvider<bool>((_) => false);

/// Removes the location saved with past adventures ("Remove saved
/// locations" in Settings). Separate from [optionalLocationAllowedProvider]:
/// that setting controls future saving; this clears what is already stored.
final locationHistoryRepositoryProvider = Provider<LocationHistoryRepository>(
  (_) => LocationHistoryRepository(),
);
