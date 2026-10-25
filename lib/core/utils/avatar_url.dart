/// Whether another user's profile `photoUrl` may be loaded on this device
/// (audit N-6, Phase 5).
///
/// firestore.rules accept any string as a profile photo URL, and the
/// leaderboard shows other users' photos — so a crafted URL could make every
/// viewer's device fetch an image from a server the author controls
/// (revealing viewers' IP addresses) or show arbitrary content. Until the
/// rules are tightened (see REMEDIATION_CHECKLIST.md, Phase 5, N-6), other
/// users' photos are only loaded from the two places the app itself ever
/// sets them from:
/// - this app's own Firebase Storage bucket, `user_avatars/` (photos
///   uploaded in Settings); and
/// - Google's profile-photo host (`*.googleusercontent.com`), set at
///   Google sign-in.
/// Anything else shows the initials avatar instead.
bool isTrustedAvatarUrl(String? url, {required String? appStorageBucket}) {
  if (url == null || url.isEmpty) return false;
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && uri.port != 443)) {
    return false;
  }
  final host = uri.host.toLowerCase();
  if (host == 'googleusercontent.com' ||
      host.endsWith('.googleusercontent.com')) {
    return true;
  }
  if (host != 'firebasestorage.googleapis.com' ||
      appStorageBucket == null ||
      appStorageBucket.isEmpty) {
    return false;
  }
  // https://firebasestorage.googleapis.com/v0/b/{bucket}/o/user_avatars%2F…
  final s = uri.pathSegments;
  return s.length == 5 &&
      s[0] == 'v0' &&
      s[1] == 'b' &&
      s[2] == appStorageBucket &&
      s[3] == 'o' &&
      s[4].startsWith('user_avatars/') &&
      !s[4].substring('user_avatars/'.length).contains('/');
}
