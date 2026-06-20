import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Blocks screenshots / screen recording and hides the app-switcher preview
/// while a sensitive (financial) screen is on top, so balances, account
/// numbers and delivery codes can't be captured.
///
/// Android-only (FLAG_SECURE); a no-op on other platforms. Calls are
/// reference-counted so overlapping secure screens behave correctly.
class SecureScreen {
  static const _ch = MethodChannel('agricore/secure');
  static int _count = 0;

  static Future<void> _apply(bool on) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _ch.invokeMethod('setSecure', {'on': on});
    } catch (_) {
      /* channel not available on this platform/build; ignore */
    }
  }

  static Future<void> enable() async {
    _count++;
    if (_count == 1) await _apply(true);
  }

  static Future<void> disable() async {
    if (_count > 0) _count--;
    if (_count == 0) await _apply(false);
  }
}

/// Mix into a screen's [State] to keep it screenshot-protected while mounted.
mixin SecureScreenMixin<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    SecureScreen.enable();
  }

  @override
  void dispose() {
    SecureScreen.disable();
    super.dispose();
  }
}
