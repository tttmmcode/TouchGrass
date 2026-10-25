import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// Coarse location-permission state for UI purposes — distinct from
/// [LocationService.getCurrentLocation]'s null-on-any-failure return, so
/// callers can show the right explanation instead of a silent blank map.
enum LocationAccessStatus {
  granted,

  /// Not yet granted, but the OS may still show its permission dialog again.
  denied,

  /// Permanently denied — the OS will no longer show its own prompt, so the
  /// only way forward is the app's own Settings deep link.
  deniedForever,

  /// Device-level location services are off entirely (not an app permission).
  serviceDisabled,
}

/// Pure mapping from the raw platform signals (service-enabled flag +
/// [LocationPermission]) to [LocationAccessStatus]. Extracted from
/// [LocationService.checkAccessStatus] so this decision — which of the four
/// UI states applies — is directly unit-testable without a Geolocator
/// platform channel.
@visibleForTesting
LocationAccessStatus mapLocationAccessStatus({
  required bool serviceEnabled,
  required LocationPermission permission,
}) {
  if (!serviceEnabled) return LocationAccessStatus.serviceDisabled;
  return switch (permission) {
    LocationPermission.deniedForever => LocationAccessStatus.deniedForever,
    LocationPermission.denied => LocationAccessStatus.denied,
    LocationPermission.whileInUse ||
    LocationPermission.always => LocationAccessStatus.granted,
    LocationPermission.unableToDetermine => LocationAccessStatus.denied,
  };
}

class LocationService {
  /// Returns the device's current position as a [GeoPoint], or null if
  /// location is unavailable or the user denies permission.
  /// Never throws — location is optional and failures are silent.
  Future<GeoPoint?> getCurrentLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      return GeoPoint(position.latitude, position.longitude);
    } catch (_) {
      return null;
    }
  }

  /// Non-invasive check of the current permission/service state — never
  /// triggers an OS prompt, so it's safe to call on every rebuild without
  /// risking repeatedly nagging the user for a permission they've denied.
  Future<LocationAccessStatus> checkAccessStatus() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    final permission = await Geolocator.checkPermission();
    return mapLocationAccessStatus(
      serviceEnabled: serviceEnabled,
      permission: permission,
    );
  }

  /// Opens the OS app-settings screen so the user can grant location access
  /// after a permanent denial — the only way to recover from
  /// [LocationAccessStatus.deniedForever] since the OS won't prompt again.
  Future<void> openAppSettings() => Geolocator.openAppSettings();

  /// Opens the OS location-services settings screen (device-level toggle,
  /// distinct from per-app permission).
  Future<void> openLocationServiceSettings() =>
      Geolocator.openLocationSettings();

  /// Converts coordinates to a human-readable place name.
  ///
  /// Returns a string like "Zilker Park, Austin, TX" or null on failure.
  /// Never throws.
  Future<String?> getLocationName({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        latitude,
        longitude,
      ).timeout(const Duration(seconds: 8));
      if (placemarks.isEmpty) return null;
      final p = placemarks.first;

      // Build a readable string: subLocality (if any), locality, adminArea.
      final parts = <String>[];
      if (p.subLocality != null && p.subLocality!.isNotEmpty) {
        parts.add(p.subLocality!);
      } else if (p.name != null && p.name!.isNotEmpty && p.name != p.locality) {
        parts.add(p.name!);
      }
      if (p.locality != null && p.locality!.isNotEmpty) {
        parts.add(p.locality!);
      }
      if (p.administrativeArea != null &&
          p.administrativeArea!.isNotEmpty &&
          p.administrativeArea != p.locality) {
        parts.add(p.administrativeArea!);
      }
      if (parts.isEmpty && p.country != null) parts.add(p.country!);
      return parts.isEmpty ? null : parts.join(', ');
    } catch (_) {
      return null;
    }
  }
}
