import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/weather_model.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';

final _weatherServiceProvider =
    Provider<WeatherService>((_) => WeatherService());

// Ticks every 30 minutes to trigger a weather re-fetch.
final _weatherRefreshProvider = StreamProvider<int>((ref) async* {
  yield 0;
  var tick = 1;
  await for (final _ in Stream<void>.periodic(const Duration(minutes: 30))) {
    yield tick++;
  }
});

/// Fetches weather for the user's current location via Open-Meteo.
/// Refreshes every 30 minutes with a fresh GPS fix each time.
/// Returns null silently if location is unavailable or the network call fails.
final weatherProvider = FutureProvider<WeatherModel?>((ref) async {
  ref.watch(_weatherRefreshProvider); // re-runs every 30 minutes
  // Re-fetch location directly on each refresh (not the cached provider value)
  // so that if the user moved or permission was initially unavailable, we pick
  // up the correct position on the next tick.
  final geoPoint = await LocationService().getCurrentLocation();
  if (geoPoint == null) return null;
  return ref.read(_weatherServiceProvider).fetchWeather(
        latitude: geoPoint.latitude,
        longitude: geoPoint.longitude,
      );
});
