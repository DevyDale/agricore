import 'package:shared_preferences/shared_preferences.dart';

/// Non-sensitive flags (onboarding seen, etc). Tokens use secure storage.
class PrefsService {
  static const _kOnboarding = 'onboarding_seen';

  static Future<bool> onboardingSeen() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kOnboarding) ?? false;
  }

  static Future<void> setOnboardingSeen() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kOnboarding, true);
  }
}
