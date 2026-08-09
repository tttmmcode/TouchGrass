import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/location_service.dart';

final locationServiceProvider = Provider<LocationService>((_) => LocationService());

final currentLocationProvider = FutureProvider<LatLng?>((ref) async {
  final geoPoint = await ref.watch(locationServiceProvider).getCurrentLocation();
  if (geoPoint == null) return null;
  return LatLng(geoPoint.latitude, geoPoint.longitude);
});

/// Non-invasive permission/service check for the map's "enable location"
/// affordance. Re-checked whenever the map screen calls
/// `ref.invalidate(locationAccessStatusProvider)` (e.g. after the user
/// returns from the OS Settings screen) — never triggers an OS prompt itself.
final locationAccessStatusProvider =
    FutureProvider.autoDispose<LocationAccessStatus>(
  (ref) => ref.watch(locationServiceProvider).checkAccessStatus(),
);

/// Set right before navigating to the map screen (from the completion
/// screen's "View on Map" action) so MapScreen can center on and emphasize
/// the just-created memory instead of the user's current location.
///
/// Consumed once in [MapScreen.initState] and immediately cleared, so
/// switching back to the map tab later doesn't keep re-focusing the same
/// old memory. Deliberately a plain value in a provider (not route `extra`)
/// because `/map` is a StatefulShellRoute branch kept alive in an
/// IndexedStack — `context.go` there doesn't reliably rebuild the screen
/// with fresh route params the way a pushed route would.
final pendingMapFocusProvider = StateProvider<String?>((ref) => null);
