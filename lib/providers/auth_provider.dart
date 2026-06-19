import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../core/config/app_config.dart';
import '../core/network/dio_client.dart';
import '../core/network/api_endpoints.dart';
import '../core/storage/token_storage.dart';
import '../models/app_user.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  final DioClient _client;
  final TokenStorage _tokens;
  AuthProvider(this._client, this._tokens);

  AuthStatus status = AuthStatus.unknown;
  AppUser? user;
  String? error;
  bool busy = false;

  Future<void> bootstrap() async {
    if (await _tokens.hasToken) {
      final ok = await _loadMe();
      status = ok ? AuthStatus.authenticated : AuthStatus.unauthenticated;
      if (!ok) await _tokens.clear();
    } else {
      status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  Future<bool> login(String username, String password) async {
    _setBusy(true);
    try {
      final res = await _client.dio.post(Api.tokenObtain,
          data: {'username': username.trim(), 'password': password});
      await _tokens.saveTokens(
          access: res.data['access'], refresh: res.data['refresh']);
      final ok = await _loadMe();
      status = ok ? AuthStatus.authenticated : AuthStatus.unauthenticated;
      busy = false;
      notifyListeners();
      return ok;
    } on DioException catch (e) {
      error = _msg(e, 'Invalid username or password.');
      busy = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register({
    required String username,
    required String email,
    required String password,
    String? role,
  }) async {
    _setBusy(true);
    try {
      await _client.dio.post(Api.register, data: {
        'username': username.trim(),
        'email': email.trim(),
        'password': password,
        if (role != null) 'role': role,
      });
      return await login(username, password);
    } on DioException catch (e) {
      error = _msg(e, 'Could not create your account.');
      busy = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> loginWithGoogle() async {
    _setBusy(true);
    try {
      final gsi = GoogleSignIn(
        serverClientId: AppConfig.googleServerClientId.isEmpty
            ? null
            : AppConfig.googleServerClientId,
        clientId: AppConfig.googleIosClientId.isEmpty
            ? null
            : AppConfig.googleIosClientId,
        scopes: const ['email', 'profile'],
      );
      final account = await gsi.signIn();
      if (account == null) {
        busy = false;
        notifyListeners();
        return false;
      }
      final gAuth = await account.authentication;
      final idToken = gAuth.idToken;
      if (idToken == null) {
        error = 'Google did not return an ID token.';
        busy = false;
        notifyListeners();
        return false;
      }
      final res =
          await _client.dio.post('/auth/google/', data: {'id_token': idToken});
      await _tokens.saveTokens(
          access: res.data['access'], refresh: res.data['refresh']);
      final ok = await _loadMe();
      status = ok ? AuthStatus.authenticated : AuthStatus.unauthenticated;
      busy = false;
      notifyListeners();
      return ok;
    } on DioException catch (e) {
      error = _msg(e, 'Google sign-in failed on the server.');
      busy = false;
      notifyListeners();
      return false;
    } catch (e) {
      error = 'Google sign-in is unavailable. Check OAuth setup.';
      busy = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> _loadMe() async {
    try {
      final res = await _client.dio.get(Api.me);
      user = AppUser.fromJson((res.data as Map).cast<String, dynamic>());
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> logout() async {
    await _tokens.clear();
    user = null;
    error = null;
    status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  void _setBusy(bool b) {
    busy = b;
    if (b) error = null;
    notifyListeners();
  }

  String _msg(DioException e, String fallback) {
    final d = e.response?.data;
    if (d is Map) {
      final parts = <String>[];
      d.forEach((k, v) => parts.add(v is List ? v.join(', ') : v.toString()));
      if (parts.isNotEmpty) return parts.join('\n');
    }
    return fallback;
  }
}
