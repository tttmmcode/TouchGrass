// D-09: the optional-location setting gates every optional location use.
// Weather (Open-Meteo) is the always-on path outside the camera flow; the
// camera flow is covered in camera_flow_test.dart.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/models/user_model.dart';
import 'package:touchgrass/models/weather_model.dart';
import 'package:touchgrass/providers/location_privacy_providers.dart';
import 'package:touchgrass/providers/map_providers.dart';
import 'package:touchgrass/providers/user_providers.dart';
import 'package:touchgrass/providers/weather_providers.dart';
import 'package:touchgrass/services/location_service.dart';
import 'package:touchgrass/services/weather_service.dart';

class _Location implements LocationService {
  int reads = 0;
  @override
  Future<GeoPoint?> getCurrentLocation() async {
    reads++;
    return const GeoPoint(51.507351, -0.127758);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Weather implements WeatherService {
  final sent = <(double, double)>[];
  @override
  Future<WeatherModel?> fetchWeather({
    required double latitude,
    required double longitude,
  }) async {
    sent.add((latitude, longitude));
    return const WeatherModel(temperatureCelsius: 12, weatherCode: 3);
  }
}

UserModel _user({bool? locationEnabled}) {
  final u = UserModel.initial(uid: 'u1', displayName: 'A', email: 'a@b.test');
  return locationEnabled == null
      ? u
      : u.copyWith(
          settings: u.settings.copyWith(locationEnabled: locationEnabled),
        );
}

void main() {
  ProviderContainer container(
    Stream<UserModel?> user,
    _Location loc,
    _Weather w, {
    bool primerDone = true,
  }) {
    final c = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith((ref) => user),
        locationServiceProvider.overrideWithValue(loc),
        weatherServiceProvider.overrideWithValue(w),
      ],
    );
    c.read(locationPrimerDoneProvider.notifier).state = primerDone;
    return c;
  }

  group('optionalLocationAllowedProvider', () {
    test('false while the profile is loading (fails closed)', () {
      final c = container(const Stream.empty(), _Location(), _Weather());
      expect(c.read(optionalLocationAllowedProvider), isFalse);
      c.dispose();
    });
    test(
      'true when the setting is on (the default for new accounts)',
      () async {
        final c = container(Stream.value(_user()), _Location(), _Weather());
        await c.read(currentUserProvider.future);
        expect(c.read(optionalLocationAllowedProvider), isTrue);
        c.dispose();
      },
    );
    test('false when the user turned it off', () async {
      final c = container(
        Stream.value(_user(locationEnabled: false)),
        _Location(),
        _Weather(),
      );
      await c.read(currentUserProvider.future);
      expect(c.read(optionalLocationAllowedProvider), isFalse);
      c.dispose();
    });
  });

  group('weatherProvider', () {
    test(
      'setting OFF: no location read and nothing sent to the weather service',
      () async {
        final loc = _Location();
        final w = _Weather();
        final c = container(
          Stream.value(_user(locationEnabled: false)),
          loc,
          w,
        );
        await c.read(currentUserProvider.future);
        expect(await c.read(weatherProvider.future), isNull);
        expect(loc.reads, 0);
        expect(w.sent, isEmpty);
        c.dispose();
      },
    );

    test(
      'setting ON: fetches weather with coarse (~1 km) coordinates only',
      () async {
        final loc = _Location();
        final w = _Weather();
        final c = container(Stream.value(_user()), loc, w);
        c.listen(weatherProvider, (_, _) {});
        await c.read(currentUserProvider.future);
        await Future<void>.delayed(Duration.zero);
        expect(await c.read(weatherProvider.future), isNotNull);
        expect(loc.reads, greaterThan(0));
        expect(w.sent.last, (51.51, -0.13));
        c.dispose();
      },
    );
  });

  group('D-14 — weather never prompts before the location primer', () {
    test(
      'primer not shown yet: no location read and no weather request',
      () async {
        final loc = _Location();
        final w = _Weather();
        final c = container(Stream.value(_user()), loc, w, primerDone: false);
        await c.read(currentUserProvider.future);
        expect(await c.read(weatherProvider.future), isNull);
        expect(loc.reads, 0);
        expect(w.sent, isEmpty);
        c.dispose();
      },
    );

    test('once the primer is done, weather loads', () async {
      final loc = _Location();
      final w = _Weather();
      final c = container(Stream.value(_user()), loc, w, primerDone: false);
      c.listen(weatherProvider, (_, _) {});
      await c.read(currentUserProvider.future);
      expect(loc.reads, 0);
      c.read(locationPrimerDoneProvider.notifier).state = true;
      await Future<void>.delayed(Duration.zero);
      expect(await c.read(weatherProvider.future), isNotNull);
      expect(loc.reads, greaterThan(0));
      c.dispose();
    });
  });

  test('coarseCoordinate rounds to 2 decimal places', () {
    expect(coarseCoordinate(30.26715), 30.27);
    expect(coarseCoordinate(-97.74306), -97.74);
    expect(coarseCoordinate(0.004), 0.0);
  });
}
