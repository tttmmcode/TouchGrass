import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/weather_model.dart';

/// Fetches current weather from Open-Meteo (free, no API key required).
class WeatherService {
  Future<WeatherModel?> fetchWeather({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': latitude.toStringAsFixed(4),
        'longitude': longitude.toStringAsFixed(4),
        'current': 'temperature_2m,weather_code',
        // Sunrise/sunset ride along on the same request/response as the
        // existing weather fetch (Automatic theme mode reuses this, not a
        // separate poll) — see AppThemeMode.automatic in app_theme_mode.dart.
        'daily': 'sunrise,sunset',
        'timezone': 'auto',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final current = body['current'] as Map<String, dynamic>;
      final daily = body['daily'] as Map<String, dynamic>?;
      return WeatherModel(
        temperatureCelsius: (current['temperature_2m'] as num).toDouble(),
        weatherCode: current['weather_code'] as int,
        sunrise: _firstDailyTime(daily, 'sunrise'),
        sunset: _firstDailyTime(daily, 'sunset'),
      );
    } catch (_) {
      return null;
    }
  }

  /// Parses the first entry of `daily.<key>` — Open-Meteo returns these as
  /// naive (no UTC offset) ISO8601 strings already resolved to local time at
  /// the given coordinates (because `timezone=auto` was requested), so
  /// [DateTime.parse] correctly yields a local [DateTime] with no further
  /// conversion — this is what makes the result stay correct across
  /// timezone changes: it's always local to wherever the coordinates are,
  /// not the device's previously-cached timezone.
  static DateTime? _firstDailyTime(Map<String, dynamic>? daily, String key) {
    final list = daily?[key] as List<dynamic>?;
    if (list == null || list.isEmpty) return null;
    return DateTime.tryParse(list.first as String);
  }
}
