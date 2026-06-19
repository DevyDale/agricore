import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

class AppConfig {
  static const String _envBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (_envBaseUrl.isNotEmpty) return _envBaseUrl;
    if (kIsWeb) return 'http://127.0.0.1:8000';
    try {
      if (Platform.isAndroid) return 'http://10.0.2.2:8000';
    } catch (_) {}
    return 'http://127.0.0.1:8000';
  }

  static String get apiBaseUrl => '$baseUrl/api';
  static String get wsBaseUrl => baseUrl.replaceFirst('http', 'ws');

  static const String googleServerClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID', defaultValue: '971117362434-mhtjj726gf1r9cagcsvm65nqc95htj3s.apps.googleusercontent.com');
  static const String googleIosClientId =
      String.fromEnvironment('GOOGLE_IOS_CLIENT_ID', defaultValue: '971117362434-q14oghdmug5g3m7ra6efs622095lcfsn.apps.googleusercontent.com');
  static bool get googleConfigured => googleServerClientId.isNotEmpty;
}
