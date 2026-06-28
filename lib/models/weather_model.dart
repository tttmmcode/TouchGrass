class WeatherModel {
  const WeatherModel({
    required this.temperatureCelsius,
    required this.weatherCode,
  });

  final double temperatureCelsius;
  final int weatherCode;

  String get emoji {
    if (weatherCode == 0) return '☀️';
    if (weatherCode <= 2) return '⛅';
    if (weatherCode == 3) return '☁️';
    if (weatherCode <= 48) return '🌫️';
    if (weatherCode <= 57) return '🌦️';
    if (weatherCode <= 67) return '🌧️';
    if (weatherCode <= 77) return '❄️';
    if (weatherCode <= 82) return '🌦️';
    if (weatherCode <= 86) return '🌨️';
    return '⛈️';
  }

  String get condition {
    if (weatherCode == 0) return 'Clear sky';
    if (weatherCode <= 2) return 'Partly cloudy';
    if (weatherCode == 3) return 'Overcast';
    if (weatherCode <= 48) return 'Foggy';
    if (weatherCode <= 57) return 'Drizzle';
    if (weatherCode <= 67) return 'Rainy';
    if (weatherCode <= 77) return 'Snowy';
    if (weatherCode <= 82) return 'Showers';
    if (weatherCode <= 86) return 'Snow showers';
    return 'Thunderstorm';
  }

  String get outdoorAdvice {
    if (weatherCode >= 95) return 'Stay safe — storm nearby';
    if (weatherCode >= 80) return 'Rain showers — grab a jacket';
    if (weatherCode >= 71) return 'Snowy — bundle up!';
    if (weatherCode >= 61) return 'Rainy — grab a raincoat!';
    if (weatherCode >= 51) return 'Light drizzle expected today';
    if (weatherCode >= 45) return 'Foggy out there — take care';
    if (temperatureCelsius > 35) return 'Very hot — stay hydrated!';
    if (temperatureCelsius < 0) return 'Freezing — dress warmly!';
    if (weatherCode <= 2 && temperatureCelsius >= 10) {
      return 'Perfect weather for a challenge!';
    }
    return 'Good enough to go outside!';
  }

  double get temperatureFahrenheit => temperatureCelsius * 9 / 5 + 32;

  int get tempRounded => temperatureCelsius.round();
  int get tempFahrenheitRounded => temperatureFahrenheit.round();
}
