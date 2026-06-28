import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/location_service.dart';

final currentLocationProvider = FutureProvider<LatLng?>((ref) async {
  final geoPoint = await LocationService().getCurrentLocation();
  if (geoPoint == null) return null;
  return LatLng(geoPoint.latitude, geoPoint.longitude);
});
