import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_translations.dart';

/// Holds the user's language + currency choice, persists them locally (like the
/// web app's localStorage keys), and exposes translation + currency helpers.
class LocaleProvider extends ChangeNotifier {
  static const _langKey = 'preferred_language';
  static const _currencyKey = 'preferred_currency';

  String _language = 'en';
  String _currency = 'USD';

  String get language => _language;
  String get currency => _currency;
  bool get isRtl => isRtlLanguage(_language);
  Locale get locale => Locale(_language);
  AppCurrency get currencyInfo => currencyFor(_currency);

  /// Loads saved preferences. Call once at startup.
  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _language = p.getString(_langKey) ?? 'en';
      _currency = p.getString(_currencyKey) ?? 'USD';
    } catch (_) {
      // Defaults already set; ignore storage errors.
    }
    notifyListeners();
  }

  Future<void> setLanguage(String code) async {
    if (code == _language) return;
    _language = code;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_langKey, code);
    } catch (_) {/* best-effort persistence */}
  }

  Future<void> setCurrency(String code) async {
    if (code == _currency) return;
    _currency = code;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_currencyKey, code);
    } catch (_) {/* best-effort persistence */}
  }

  /// Translates [key] (English source text) into the active language, falling
  /// back to the key itself when no translation exists — same as web `i18n.t`.
  String tr(String key) {
    final dict = kTranslations[_language];
    final hit = dict?[key];
    if (hit != null && hit.isNotEmpty) return hit;
    return key;
  }

  /// Formats [amount] with the active currency's symbol and thousands
  /// separators, e.g. `KSh 12,500`.
  String formatCurrency(num? amount, {int decimals = 0}) {
    final c = currencyInfo;
    final v = amount ?? 0;
    final neg = v < 0;
    final fixed = v.abs().toStringAsFixed(decimals);
    final parts = fixed.split('.');
    final intPart = parts[0];
    final buf = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
      buf.write(intPart[i]);
    }
    final body = parts.length > 1 ? '$buf.${parts[1]}' : buf.toString();
    return '${c.symbol} ${neg ? '-' : ''}$body';
  }
}

/// Ergonomic translation/currency access from any widget. Listens by default so
/// widgets rebuild when the language changes.
extension LocaleX on BuildContext {
  String tr(String key) => watch<LocaleProvider>().tr(key);

  String money(num? amount, {int decimals = 0}) =>
      watch<LocaleProvider>().formatCurrency(amount, decimals: decimals);
}
