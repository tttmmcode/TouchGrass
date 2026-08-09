import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Real-time online/offline signal used app-wide to explain why a screen
/// might be stuck loading, rather than leaving the user with an unexplained
/// spinner or a raw stream error.
///
/// Emits the current state immediately, then updates on every change.
final isOnlineProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  yield _hasConnection(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(_hasConnection);
});

bool _hasConnection(List<ConnectivityResult> results) =>
    results.any((r) => r != ConnectivityResult.none);
