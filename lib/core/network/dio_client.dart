import 'package:dio/dio.dart';
import '../config/app_config.dart';
import '../storage/token_storage.dart';

/// Dio wrapper with:
///  * automatic Bearer token injection
///  * automatic access-token refresh on 401, then a one-shot retry
class DioClient {
  final TokenStorage _tokens;
  late final Dio dio;

  /// Single in-flight refresh shared by all concurrent 401s, so parallel
  /// requests await one refresh instead of each skipping or refreshing alone.
  Future<bool>? _refreshFuture;

  /// Marks a request we've already retried once, to avoid an infinite
  /// refresh/retry loop if the retried call also returns 401.
  static const _retriedFlag = '__dioclient_retried__';

  DioClient(this._tokens) {
    dio = Dio(BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'Accept': 'application/json'},
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _tokens.accessToken;
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (e, handler) async {
        final isAuthCall = e.requestOptions.path.contains('/auth/token');
        final is401 = e.response?.statusCode == 401;
        final alreadyRetried = e.requestOptions.extra[_retriedFlag] == true;
        if (is401 && !isAuthCall && !alreadyRetried) {
          final ok = await _refreshAccess();
          if (ok) {
            try {
              final retried = await _retry(e.requestOptions);
              return handler.resolve(retried);
            } on DioException catch (err) {
              return handler.next(err);
            }
          }
        }
        handler.next(e);
      },
    ));
  }

  /// Returns the shared refresh result, starting one if none is in flight.
  Future<bool> _refreshAccess() {
    return _refreshFuture ??=
        _doRefresh().whenComplete(() => _refreshFuture = null);
  }

  Future<bool> _doRefresh() async {
    final refresh = await _tokens.refreshToken;
    if (refresh == null || refresh.isEmpty) return false;
    try {
      final plain = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl));
      final res = await plain.post(Api2.tokenRefresh, data: {'refresh': refresh});
      final newAccess = (res.data is Map) ? res.data['access'] as String? : null;
      if (newAccess != null) {
        await _tokens.saveAccess(newAccess);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<Response<dynamic>> _retry(RequestOptions ro) async {
    final token = await _tokens.accessToken;
    final options = Options(
      method: ro.method,
      headers: {...ro.headers, 'Authorization': 'Bearer $token'},
      extra: {...ro.extra, _retriedFlag: true},
    );
    return dio.request(
      ro.path,
      data: ro.data,
      queryParameters: ro.queryParameters,
      options: options,
    );
  }
}

/// Local alias to avoid an import cycle in the refresh path.
class Api2 {
  static const tokenRefresh = '/auth/token/refresh/';
}
