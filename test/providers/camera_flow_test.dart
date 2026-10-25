// End-to-end CameraNotifier flow against fake_cloud_firestore (audit D-13
// and D-09): photo upload → completion + reward + Journal entry, with
// failures, retries, duplicate retries, offline, and the optional-location
// setting. Security-rule enforcement (atomicity, create-only, location gate)
// is covered by the emulator suite in firestore-tests/; fake_cloud_firestore
// doesn't evaluate rules.

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touchgrass/core/data/challenge_seed_library.dart';
import 'package:touchgrass/core/result.dart';
import 'package:touchgrass/models/challenge_model.dart';
import 'package:touchgrass/models/user_model.dart';
import 'package:touchgrass/models/weather_model.dart';
import 'package:touchgrass/providers/auth_providers.dart';
import 'package:touchgrass/providers/camera_providers.dart';
import 'package:touchgrass/providers/challenge_providers.dart';
import 'package:touchgrass/providers/connectivity_providers.dart';
import 'package:touchgrass/providers/entitlement_providers.dart';
import 'package:touchgrass/providers/location_privacy_providers.dart';
import 'package:touchgrass/providers/map_providers.dart';
import 'package:touchgrass/providers/user_providers.dart';
import 'package:touchgrass/providers/weather_providers.dart';
import 'package:touchgrass/repositories/challenge_repository.dart';
import 'package:touchgrass/repositories/completion_repository.dart';
import 'package:touchgrass/repositories/user_repository.dart';
import 'package:touchgrass/services/auth_service.dart';
import 'package:touchgrass/services/challenge_generation_service.dart';
import 'package:touchgrass/services/firestore_service.dart';
import 'package:touchgrass/services/location_service.dart';
import 'package:touchgrass/services/storage_service.dart';
import 'package:touchgrass/services/weather_service.dart';

const uid = 'alice';

class _User implements User {
  @override
  String get uid => 'alice';
  @override
  String? get email => 'alice@example.test';
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Auth implements AuthService {
  @override
  User? get currentUser => _User();
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Records uploads; the URL carries the fixed per-completion path.
class FakeStorage implements StorageService {
  final paths = <String>[];
  int failNext = 0;

  @override
  Future<String> uploadCompletionPhoto({
    required String userId,
    required String challengeId,
    required Uint8List bytes,
  }) async {
    if (failNext > 0) {
      failNext--;
      throw Exception('network down');
    }
    final path = completionPhotoPath(userId, challengeId);
    paths.add(path);
    return 'https://firebasestorage.googleapis.com/v0/b/b/o/'
        '${Uri.encodeComponent(path)}?alt=media&token=t${paths.length}';
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Records every location read and place-name lookup.
class FakeLocation implements LocationService {
  final calls = <String>[];
  @override
  Future<GeoPoint?> getCurrentLocation() async {
    calls.add('position');
    return const GeoPoint(30.26715, -97.74306);
  }

  @override
  Future<String?> getLocationName({
    required double latitude,
    required double longitude,
  }) async {
    calls.add('geocode');
    return 'Zilker Park';
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Records every coordinate sent to the weather service.
class FakeWeather implements WeatherService {
  final sent = <(double, double)>[];
  @override
  Future<WeatherModel?> fetchWeather({
    required double latitude,
    required double longitude,
  }) async {
    sent.add((latitude, longitude));
    return const WeatherModel(temperatureCelsius: 20, weatherCode: 0);
  }
}

class FakeChallenges implements ChallengeRepository {
  @override
  Future<Result<void>> markChallengeCompleted(String uid, String docId) async =>
      const Ok(null);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late FakeFirebaseFirestore db;
  late FakeStorage storage;
  late FakeLocation location;
  late FakeWeather weather;
  late ProviderContainer container;
  final allowLocation = StateProvider<bool>((_) => true);
  final online = StateProvider<bool>((_) => true);
  final photo = Uint8List.fromList([1, 2, 3]);

  final challenge = const ChallengeGenerationService().generate(
    seed: ChallengeSeedLibrary.selectSeed(
      dayNumber: 4,
      userId: uid,
      difficulty: ChallengeDifficulty.medium,
    ),
    userId: uid,
    dayNumber: 4,
  );
  final completionId = '${uid}_${challenge.challengeId}';

  Future<void> seedUser() => db
      .collection('users')
      .doc(uid)
      .set(
        UserModel.initial(
          uid: uid,
          displayName: 'Alice',
          email: 'alice@example.test',
        ).toFirestore(),
      );

  setUp(() async {
    db = FakeFirebaseFirestore();
    storage = FakeStorage();
    location = FakeLocation();
    weather = FakeWeather();
    await seedUser();
    container = ProviderContainer(
      overrides: [
        todaysChallengeProvider.overrideWith((ref) => Stream.value(challenge)),
        authStateProvider.overrideWith((ref) => Stream.value(_User())),
        isOnlineProvider.overrideWith((ref) => Stream.value(ref.watch(online))),
        canUseAiVerificationProvider.overrideWithValue(false),
        optionalLocationAllowedProvider.overrideWith(
          (ref) => ref.watch(allowLocation),
        ),
        storageServiceProvider.overrideWithValue(storage),
        completionRepositoryProvider.overrideWithValue(
          CompletionRepository(db: db),
        ),
        userRepositoryProvider.overrideWithValue(
          UserRepository(
            authService: _Auth(),
            firestoreService: FirestoreService(db: db),
            storageService: storage,
            db: db,
          ),
        ),
        challengeRepositoryProvider.overrideWithValue(FakeChallenges()),
        locationServiceProvider.overrideWithValue(location),
        weatherServiceProvider.overrideWithValue(weather),
      ],
    );
    container.listen(isOnlineProvider, (_, _) {});
    await container.read(todaysChallengeProvider.future);
    await container.read(authStateProvider.future);
    await container.read(isOnlineProvider.future);
    container.listen(cameraFlowProvider, (_, _) {});
  });

  tearDown(() => container.dispose());

  CameraNotifier notifier() => container.read(cameraFlowProvider.notifier);
  CameraFlowState state() => container.read(cameraFlowProvider);
  Future<int> count(String path) async =>
      (await db.collection(path).get()).size;
  Future<Map<String, dynamic>?> completion() async =>
      (await db.collection('completions').doc(completionId).get()).data();
  Future<Map<String, dynamic>?> journal() async =>
      (await db.collection('users/$uid/memories').doc(completionId).get())
          .data();

  Future<void> submit({String caption = 'Found it'}) async {
    notifier().setBytes(photo);
    await notifier().verify();
    expect(state(), isA<CameraCaptionStep>(), reason: '$state');
    await notifier().submitCaption(caption);
  }

  group('success', () {
    test(
      'saves completion, XP and the Journal entry with the photo together',
      () async {
        await submit();
        final s = state();
        expect(s, isA<CameraSuccess>());
        expect((s as CameraSuccess).savedToJournal, isTrue);

        final c = (await completion())!;
        final m = (await journal())!;
        expect(storage.paths, [
          'completion_photos/$uid/${challenge.challengeId}.jpg',
        ]);
        expect(
          m['photoUrl'],
          c['photoUrl'],
          reason: 'photo saved to the right entry',
        );
        expect(m['xpEarned'], c['xpAwarded']);
        expect(c['xpAwarded'], challenge.xpReward);
        expect(m['caption'], 'Found it');
        expect(m['challengeDay'], 4);
        final user = (await db.collection('users').doc(uid).get()).data()!;
        expect(user['lastCompletionId'], completionId);
      },
    );

    test(
      'with location allowed: location, place name and weather are saved',
      () async {
        await submit();
        expect((await completion())!['location'], isA<GeoPoint>());
        final m = (await journal())!;
        expect(m['latitude'], closeTo(30.26715, 1e-9));
        expect(m['locationName'], 'Zilker Park');
        expect(m['weatherCondition'], isNotNull);
        // Weather only ever receives coarse (~1 km) coordinates.
        expect(weather.sent.single, (30.27, -97.74));
      },
    );
  });

  group('D-09 — location setting off', () {
    setUp(() => container.read(allowLocation.notifier).state = false);

    test(
      'reads no location and sends nothing to weather or the geocoder',
      () async {
        await submit();
        expect(state(), isA<CameraSuccess>());
        expect(location.calls, isEmpty);
        expect(weather.sent, isEmpty);
      },
    );

    test(
      'saves the completion and Journal entry without any location data',
      () async {
        await submit();
        expect((await completion())!.containsKey('location'), isFalse);
        final m = (await journal())!;
        for (final k in [
          'latitude',
          'longitude',
          'locationName',
          'weatherCondition',
          'weatherEmoji',
        ]) {
          expect(m.containsKey(k), isFalse, reason: k);
        }
      },
    );
  });

  test(
    'D-09 — switching the setting off after the photo saves no location',
    () async {
      notifier().setBytes(photo);
      await notifier().verify();
      expect(location.calls, contains('position'));
      container.read(allowLocation.notifier).state = false;
      await notifier().submitCaption('');
      expect(state(), isA<CameraSuccess>());
      expect((await completion())!.containsKey('location'), isFalse);
      expect((await journal())!.containsKey('latitude'), isFalse);
    },
  );

  group('failures and retries', () {
    test(
      'upload failure: nothing saved, retry required, retry succeeds',
      () async {
        storage.failNext = 1;
        notifier().setBytes(photo);
        await notifier().verify();
        final f = state() as CameraFailure;
        expect(f.kind, CameraFailureKind.uploadFailed);
        expect(f.canRetry, isTrue);
        expect(f.message, contains('nothing was saved'));
        expect(await count('completions'), 0);

        await notifier().retryVerification();
        expect(state(), isA<CameraCaptionStep>());
        await notifier().submitCaption('');
        expect(state(), isA<CameraSuccess>());
        expect(await count('completions'), 1);
        expect(await count('users/$uid/memories'), 1);
      },
    );

    test(
      'save failure: photo uploaded, nothing saved, retry saves once to the same photo',
      () async {
        await db.collection('users').doc(uid).delete(); // makes the save fail
        await submit(caption: 'keep me');
        final f = state() as CameraFailure;
        expect(f.kind, CameraFailureKind.saveFailed);
        expect(f.canRetry, isTrue);
        expect(f.message, contains("isn't saved"));
        expect(await count('completions'), 0);
        expect(await count('users/$uid/memories'), 0);

        await seedUser();
        await notifier().retryVerification();
        final step = state() as CameraCaptionStep;
        expect(
          step.initialCaption,
          'keep me',
          reason: 'caption survives the retry',
        );
        await notifier().submitCaption('keep me');
        expect(state(), isA<CameraSuccess>());
        expect(await count('completions'), 1);
        expect(await count('users/$uid/memories'), 1);
        expect(
          storage.paths.toSet().length,
          1,
          reason: 'retries reuse one photo object (no orphans)',
        );
      },
    );

    test(
      'duplicate retry after a successful save: refused, no upload, nothing doubled',
      () async {
        await submit();
        final xp = (await db.collection('users').doc(uid).get()).data()!['xp'];
        final uploads = storage.paths.length;

        notifier().setBytes(photo); // e.g. the confirmation was lost
        await notifier().verify();
        final f = state() as CameraFailure;
        expect(f.kind, CameraFailureKind.alreadyCompleted);
        expect(f.canRetry, isFalse);
        expect(
          storage.paths.length,
          uploads,
          reason: 'must not overwrite the saved photo',
        );
        expect((await db.collection('users').doc(uid).get()).data()!['xp'], xp);
        expect(await count('completions'), 1);
        expect(await count('users/$uid/memories'), 1);
      },
    );

    test('a double-tap on Submit saves once', () async {
      notifier().setBytes(photo);
      await notifier().verify();
      await Future.wait([
        notifier().submitCaption('a'),
        notifier().submitCaption('b'),
      ]);
      expect(await count('completions'), 1);
      expect(await count('users/$uid/memories'), 1);
    });

    test(
      'offline: nothing uploaded or saved; retry after reconnecting succeeds',
      () async {
        container.read(online.notifier).state = false;
        await container.read(isOnlineProvider.future);
        await Future<void>.delayed(Duration.zero);
        notifier().setBytes(photo);
        await notifier().verify();
        final f = state() as CameraFailure;
        expect(f.kind, CameraFailureKind.uploadFailed);
        expect(storage.paths, isEmpty);

        container.read(online.notifier).state = true;
        await container.read(isOnlineProvider.future);
        await Future<void>.delayed(Duration.zero);
        await notifier().retryVerification();
        await notifier().submitCaption('');
        expect(state(), isA<CameraSuccess>());
        expect(await count('completions'), 1);
      },
    );
  });
}
