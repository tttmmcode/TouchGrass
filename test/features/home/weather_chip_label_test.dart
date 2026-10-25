// D-22 / Phase 6 accessibility: the weather chip's screen-reader label
// always states the unit and explains a missing reading.

import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/features/home/screens/home_screen.dart';
import 'package:touchgrass/models/weather_model.dart';

void main() {
  test('a reading includes the condition and the unit', () {
    final label = weatherChipSemanticsLabel(
      locationOff: false,
      weather: const WeatherModel(temperatureCelsius: 20, weatherCode: 0),
    );
    expect(label, contains('68 degrees Fahrenheit'));
    expect(label, startsWith('Weather: '));
  });

  test('location off says why there is no weather', () {
    expect(
      weatherChipSemanticsLabel(
        locationOff: true,
        weather: const WeatherModel(temperatureCelsius: 20, weatherCode: 0),
      ),
      contains('saving location is turned off'),
    );
  });

  test('no reading is announced as unavailable, with the tap hint', () {
    expect(
      weatherChipSemanticsLabel(locationOff: false, weather: null),
      'Weather unavailable. Tap for details.',
    );
  });
}
