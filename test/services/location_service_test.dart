// Unit tests for mapLocationAccessStatus — the pure mapping from raw
// Geolocator signals (service-enabled flag + LocationPermission) to the
// app's four UI-facing LocationAccessStatus states. Extracted from
// LocationService.checkAccessStatus so this decision is testable without a
// Geolocator platform channel/mock.

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:touchgrass/services/location_service.dart';

void main() {
  group('mapLocationAccessStatus', () {
    test('service disabled takes priority over any permission state', () {
      expect(
        mapLocationAccessStatus(
          serviceEnabled: false,
          permission: LocationPermission.always,
        ),
        LocationAccessStatus.serviceDisabled,
      );
    });

    test('deniedForever maps to deniedForever', () {
      expect(
        mapLocationAccessStatus(
          serviceEnabled: true,
          permission: LocationPermission.deniedForever,
        ),
        LocationAccessStatus.deniedForever,
      );
    });

    test('denied maps to denied', () {
      expect(
        mapLocationAccessStatus(
          serviceEnabled: true,
          permission: LocationPermission.denied,
        ),
        LocationAccessStatus.denied,
      );
    });

    test('whileInUse maps to granted', () {
      expect(
        mapLocationAccessStatus(
          serviceEnabled: true,
          permission: LocationPermission.whileInUse,
        ),
        LocationAccessStatus.granted,
      );
    });

    test('always maps to granted', () {
      expect(
        mapLocationAccessStatus(
          serviceEnabled: true,
          permission: LocationPermission.always,
        ),
        LocationAccessStatus.granted,
      );
    });

    test('unableToDetermine falls back to denied rather than crashing or '
        'claiming granted', () {
      expect(
        mapLocationAccessStatus(
          serviceEnabled: true,
          permission: LocationPermission.unableToDetermine,
        ),
        LocationAccessStatus.denied,
      );
    });
  });
}
