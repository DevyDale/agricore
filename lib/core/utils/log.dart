import 'package:flutter/foundation.dart';

/// Logs an error that is intentionally not surfaced to the user.
///
/// Use at `catch` sites for best-effort / fire-and-forget operations instead of
/// an empty `catch (_) {}`, so failures are visible while debugging but stay
/// silent (and cheap) in release builds.
void logSwallowed(String where, Object error) {
  if (kDebugMode) {
    debugPrint('[swallowed] $where -> $error');
  }
}
