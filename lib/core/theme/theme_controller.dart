import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the app's [ThemeMode] and persists it in shared_preferences so the
/// Appearance setting is remembered across launches.
class ThemeController extends ChangeNotifier {
  static const _key = 'theme_mode';

  ThemeMode _mode = ThemeMode.light;
  ThemeMode get mode => _mode;

  /// Loads the saved mode from disk. Safe to call once at startup.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _mode = _decode(prefs.getString(_key));
    notifyListeners();
  }

  /// Updates the active mode and persists it.
  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, _encode(mode));
  }

  static ThemeMode _decode(String? v) {
    switch (v) {
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      case 'light':
      default:
        return ThemeMode.light;
    }
  }

  static String _encode(ThemeMode m) {
    switch (m) {
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
      case ThemeMode.light:
        return 'light';
    }
  }

  /// Human-readable label for the current mode (used in the Settings subtitle).
  String get label {
    switch (_mode) {
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System';
      case ThemeMode.light:
        return 'Light';
    }
  }
}
