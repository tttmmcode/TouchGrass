// Firebase options for the ISOLATED DEVELOPMENT project (touchgrass-dev-n7j3f).
// Never production: selected only with --dart-define=TG_FIREBASE_ENV=development
// (lib/core/config/firebase_environment.dart). Like firebase_options.dart,
// these are public client identifiers, not secrets; the dev project has no
// billing, no Analytics and no production data.
// Only a web app is registered in the dev project (Phase 8); Android and iOS
// need their own dev registrations before they can use it.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb;

class DevFirebaseOptions {
  static const String projectId = 'touchgrass-dev-n7j3f';

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    throw UnsupportedError(
      'The development Firebase project has no Android/iOS app registered yet. '
      'Use TG_FIREBASE_ENV=emulator on mobile, or register dev apps first.',
    );
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyD4O-h7j8kkUSLGjmu1-W3MocR_1Ilj4UU',
    appId: '1:712058370294:web:00c7e3e06a5a4d791494d7',
    messagingSenderId: '712058370294',
    projectId: 'touchgrass-dev-n7j3f',
    authDomain: 'touchgrass-dev-n7j3f.firebaseapp.com',
    storageBucket: 'touchgrass-dev-n7j3f.firebasestorage.app',
  );
}
