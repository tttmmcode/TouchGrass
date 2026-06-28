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
      final uri = Uri.https(
        'api.open-meteo.com',
        '/v1/forecast',
        {
          'latitude': latitude.toStringAsFixed(4),
          'longitude': longitude.toStringAsFixed(4),
          'current': 'temperature_2m,weather_code',
          'timezone': 'auto',
        },
      );
      final response =
          await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final current = body['current'] as Map<String, dynamic>;
      return WeatherModel(
        temperatureCelsius: (current['temperature_2m'] as num).toDouble(),
        weatherCode: current['weather_code'] as int,
      );
    } catch (_) {
      return null;
    }
  }
}
