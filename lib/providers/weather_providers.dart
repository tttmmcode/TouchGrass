import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/weather_model.dart';
import '../services/weather_service.dart';
import 'location_privacy_providers.dart';
import 'map_providers.dart';

final weatherServiceProvider = Provider<WeatherService>(
  (_) => WeatherService(),
);

// Ticks every 30 minutes to trigger a weather re-fetch.
final _weatherRefreshProvider = StreamProvider<int>((ref) async* {
  yield 0;
  var tick = 1;
  await for (final _ in Stream<void>.periodic(const Duration(minutes: 30))) {
    yield tick++;
  }
});

/// Coordinates sent to the weather service are rounded to 2 decimal places
/// (about 1 km) — enough for local weather and sunrise/sunset, without
/// sharing a precise position (audit D-09, data minimisation).
double coarseCoordinate(double value) => (value * 100).roundToDouble() / 100;

/// Fetches weather for the user's current location via Open-Meteo.
/// Refreshes every 30 minutes with a fresh GPS fix each time.
///
/// Optional (audit D-09): returns null without reading the location or
/// calling the weather service unless [optionalLocationAllowedProvider] is
/// true. Also null if location is unavailable or the network call fails.
///
/// Also waits for [locationPrimerDoneProvider] (audit D-14): reading the
/// location can show the OS permission prompt, which must never appear
/// before the app's own explanation.
final weatherProvider = FutureProvider<WeatherModel?>((ref) async {
  if (!ref.watch(optionalLocationAllowedProvider)) return null;
  if (!ref.watch(locationPrimerDoneProvider)) return null;
  ref.watch(_weatherRefreshProvider); // re-runs every 30 minutes
  // Re-fetch location directly on each refresh (not the cached provider value)
  // so that if the user moved or permission was initially unavailable, we pick
  // up the correct position on the next tick.
  final geoPoint = await ref.read(locationServiceProvider).getCurrentLocation();
  if (geoPoint == null) return null;
  return ref
      .read(weatherServiceProvider)
      .fetchWeather(
        latitude: coarseCoordinate(geoPoint.latitude),
        longitude: coarseCoordinate(geoPoint.longitude),
      );
});
