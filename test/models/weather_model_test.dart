// Unit tests for WeatherModel's pure display/advice logic. These getters
// drive the tap-to-see-a-tip weather feature (condition -> outdoor advice)
// and had zero coverage before this pass despite being trivially pure and
// boundary-heavy (WMO weather-code range checks stacked in priority order).

import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/models/weather_model.dart';

void main() {
  group('WeatherModel.condition', () {
    test('maps each WMO code band to its label', () {
      expect(
        const WeatherModel(temperatureCelsius: 20, weatherCode: 0).condition,
        'Clear sky',
      );
      expect(
        const WeatherModel(temperatureCelsius: 20, weatherCode: 2).condition,
        'Partly cloudy',
      );
      expect(
        const WeatherModel(temperatureCelsius: 20, weatherCode: 3).condition,
        'Overcast',
      );
      expect(
        const WeatherModel(temperatureCelsius: 20, weatherCode: 48).condition,
        'Foggy',
      );
      expect(
        const WeatherModel(temperatureCelsius: 20, weatherCode: 57).condition,
        'Drizzle',
      );
      expect(
        const WeatherModel(temperatureCelsius: 20, weatherCode: 67).condition,
        'Rainy',
      );
      expect(
        const WeatherModel(temperatureCelsius: 20, weatherCode: 77).condition,
        'Snowy',
      );
      expect(
        const WeatherModel(temperatureCelsius: 20, weatherCode: 82).condition,
        'Showers',
      );
      expect(
        const WeatherModel(temperatureCelsius: 20, weatherCode: 86).condition,
        'Snow showers',
      );
      expect(
        const WeatherModel(temperatureCelsius: 20, weatherCode: 99).condition,
        'Thunderstorm',
      );
    });

    test(
      'unknown/out-of-range high codes safely fall back to Thunderstorm',
      () {
        expect(
          const WeatherModel(
            temperatureCelsius: 20,
            weatherCode: 500,
          ).condition,
          'Thunderstorm',
        );
      },
    );
  });

  group('WeatherModel.outdoorAdvice', () {
    test('severe storm codes take priority over everything else', () {
      expect(
        const WeatherModel(
          temperatureCelsius: 20,
          weatherCode: 95,
        ).outdoorAdvice,
        'Stay safe — storm nearby',
      );
    });

    test('rain shower codes advise a jacket', () {
      expect(
        const WeatherModel(
          temperatureCelsius: 20,
          weatherCode: 80,
        ).outdoorAdvice,
        'Rain showers — grab a jacket',
      );
      expect(
        const WeatherModel(
          temperatureCelsius: 20,
          weatherCode: 82,
        ).outdoorAdvice,
        'Rain showers — grab a jacket',
      );
    });

    test('snow shower codes (83-86) advise bundling up, not a rain jacket — '
        'regression test: these used to be caught by the rain-shower (>=80) '
        'check above, contradicting the "Snow showers" condition label shown '
        'right next to this advice', () {
      expect(
        const WeatherModel(
          temperatureCelsius: -2,
          weatherCode: 85,
        ).outdoorAdvice,
        'Snowy — bundle up!',
      );
      expect(
        const WeatherModel(
          temperatureCelsius: -2,
          weatherCode: 86,
        ).outdoorAdvice,
        'Snowy — bundle up!',
      );
    });

    test('snow codes advise bundling up', () {
      expect(
        const WeatherModel(
          temperatureCelsius: -5,
          weatherCode: 71,
        ).outdoorAdvice,
        'Snowy — bundle up!',
      );
    });

    test('rain codes advise a raincoat', () {
      expect(
        const WeatherModel(
          temperatureCelsius: 15,
          weatherCode: 61,
        ).outdoorAdvice,
        'Rainy — grab a raincoat!',
      );
    });

    test('drizzle codes give a lighter warning', () {
      expect(
        const WeatherModel(
          temperatureCelsius: 15,
          weatherCode: 51,
        ).outdoorAdvice,
        'Light drizzle expected today',
      );
    });

    test('fog codes advise care', () {
      expect(
        const WeatherModel(
          temperatureCelsius: 10,
          weatherCode: 45,
        ).outdoorAdvice,
        'Foggy out there — take care',
      );
    });

    test('extreme heat (no precipitation) advises hydration', () {
      expect(
        const WeatherModel(
          temperatureCelsius: 36,
          weatherCode: 0,
        ).outdoorAdvice,
        'Very hot — stay hydrated!',
      );
    });

    test('sub-zero cold (no precipitation) advises dressing warmly', () {
      expect(
        const WeatherModel(
          temperatureCelsius: -1,
          weatherCode: 0,
        ).outdoorAdvice,
        'Freezing — dress warmly!',
      );
    });

    test('clear/mild weather is called out as perfect for a challenge', () {
      expect(
        const WeatherModel(
          temperatureCelsius: 18,
          weatherCode: 1,
        ).outdoorAdvice,
        'Perfect weather for a challenge!',
      );
    });

    test(
      'clear but below the "perfect" temperature threshold gets a chilly warning',
      () {
        expect(
          const WeatherModel(
            temperatureCelsius: 5,
            weatherCode: 1,
          ).outdoorAdvice,
          'Chilly — bring a light jacket',
        );
      },
    );

    test('chilly (0-10°C, no precipitation) advises a light jacket', () {
      expect(
        const WeatherModel(temperatureCelsius: 3, weatherCode: 3).outdoorAdvice,
        'Chilly — bring a light jacket',
      );
    });

    test('overcast/mild weather falls back to the generic safe message', () {
      expect(
        const WeatherModel(
          temperatureCelsius: 20,
          weatherCode: 3,
        ).outdoorAdvice,
        'Good enough to go outside!',
      );
    });

    test(
      'precipitation-code priority overrides temperature-based advice — '
      'a freezing rainstorm reports the rain advice, not the cold advice',
      () {
        expect(
          const WeatherModel(
            temperatureCelsius: -10,
            weatherCode: 65,
          ).outdoorAdvice,
          'Rainy — grab a raincoat!',
        );
      },
    );
  });

  group('WeatherModel temperature conversions', () {
    test('Fahrenheit conversion is exact', () {
      const model = WeatherModel(temperatureCelsius: 0, weatherCode: 0);
      expect(model.temperatureFahrenheit, 32);
    });

    test('rounded getters round to the nearest whole degree', () {
      const model = WeatherModel(temperatureCelsius: 20.6, weatherCode: 0);
      expect(model.tempRounded, 21);
      expect(model.tempFahrenheitRounded, 69);
    });
  });
}
