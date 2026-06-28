import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

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

  /// Converts coordinates to a human-readable place name.
  ///
  /// Returns a string like "Zilker Park, Austin, TX" or null on failure.
  /// Never throws.
  Future<String?> getLocationName({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude)
          .timeout(const Duration(seconds: 8));
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
