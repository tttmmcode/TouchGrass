// Phase 8: the Firebase backend is selected explicitly and fails closed, so
// development and test activity can't reach production by accident.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/core/config/firebase_environment.dart';
import 'package:touchgrass/firebase_options.dart';
import 'package:touchgrass/firebase_options_dev.dart';

void main() {
  group('resolve', () {
    test(
      'release builds default to production; debug/profile to the emulators',
      () {
        expect(
          FirebaseEnvironment.resolve(raw: '', releaseMode: true),
          FirebaseEnv.production,
        );
        expect(
          FirebaseEnvironment.resolve(raw: '', releaseMode: false),
          FirebaseEnv.emulator,
        );
      },
    );
    test('explicit values are honoured', () {
      for (final release in [true, false]) {
        expect(
          FirebaseEnvironment.resolve(raw: 'production', releaseMode: release),
          FirebaseEnv.production,
        );
        expect(
          FirebaseEnvironment.resolve(raw: 'development', releaseMode: release),
          FirebaseEnv.development,
        );
      }
      expect(
        FirebaseEnvironment.resolve(raw: 'emulator', releaseMode: false),
        FirebaseEnv.emulator,
      );
    });
    test('a release build can never use the emulators', () {
      expect(
        () => FirebaseEnvironment.resolve(raw: 'emulator', releaseMode: true),
        throwsA(isA<FirebaseEnvironmentError>()),
      );
    });
    test('unknown or misspelled values fail closed', () {
      for (final raw in ['prod', 'Production', 'staging', 'dev', ' ']) {
        expect(
          () => FirebaseEnvironment.resolve(raw: raw, releaseMode: false),
          throwsA(isA<FirebaseEnvironmentError>()),
          reason: raw,
        );
      }
    });
  });

  group('project isolation', () {
    test('each environment names its own, distinct project', () {
      expect(DefaultFirebaseOptions.web.projectId, 'touchgrass-today');
      expect(DevFirebaseOptions.web.projectId, 'touchgrass-dev-n7j3f');
      expect(
        FirebaseEnvironment.emulatorOptions.projectId,
        startsWith('demo-'),
      );
      expect(
        FirebaseEnvironment.optionsFor(FirebaseEnv.emulator).projectId,
        'demo-touchgrass-dev',
      );
      final ids = {
        DefaultFirebaseOptions.web.projectId,
        DevFirebaseOptions.web.projectId,
        FirebaseEnvironment.emulatorOptions.projectId,
      };
      expect(ids.length, 3);
    });
    test('dev options share nothing with production', () {
      const dev = DevFirebaseOptions.web;
      const prod = DefaultFirebaseOptions.web;
      expect(dev.apiKey, isNot(prod.apiKey));
      expect(dev.appId, isNot(prod.appId));
      expect(dev.storageBucket, isNot(prod.storageBucket));
      expect(dev.authDomain, isNot(prod.authDomain));
      expect(
        dev.measurementId,
        isNull,
        reason: 'no Analytics in the dev project',
      );
    });
    test(
      'the dev project has no mobile registration: refused, not production',
      () {
        // Tests run on the VM, i.e. not web.
        expect(
          () => FirebaseEnvironment.optionsFor(FirebaseEnv.development),
          throwsUnsupportedError,
        );
      },
    );
  });

  test(
    'telemetry and the banner follow the environment (tests run as emulator)',
    () {
      expect(FirebaseEnvironment.current, FirebaseEnv.emulator);
      expect(FirebaseEnvironment.telemetryEnabled, isFalse);
      expect(FirebaseEnvironment.label, 'EMULATOR');
    },
  );

  test('startup goes through the checked selection only', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('FirebaseEnvironment.optionsFor(env)'));
    expect(main, isNot(contains('DefaultFirebaseOptions.currentPlatform')));
    expect(main, contains('_ConfigurationErrorApp'));
    for (final f in [
      'lib/services/analytics_service.dart',
      'lib/services/perf_service.dart',
    ]) {
      expect(
        File(f).readAsStringSync(),
        contains('FirebaseEnvironment.telemetryEnabled'),
        reason: f,
      );
    }
  });

  group('Auth emulator connection (found in the browser run)', () {
    test('fails closed when the SDK says Auth is on the real service', () {
      expect(
        () =>
            FirebaseEnvironment.checkAuthEmulatorConnected(usesEmulator: false),
        throwsA(isA<FirebaseEnvironmentError>()),
      );
    });

    test('passes when connected, or when the SDK cannot be asked', () {
      FirebaseEnvironment.checkAuthEmulatorConnected(usesEmulator: true);
      FirebaseEnvironment.checkAuthEmulatorConnected(usesEmulator: null);
    });

    test('startup checks the connection, stops on failure and never '
        'persists an emulator session on web', () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains('checkAuthEmulatorConnected'));
      expect(main, contains('authUsesEmulator()'));
      expect(main, contains('setPersistence(Persistence.NONE)'));
      // Environment errors reach the configuration screen instead of being
      // swallowed by the generic Firebase-init catch.
      expect(main, contains('on FirebaseEnvironmentError {\n    rethrow;'));
    });
  });
}
