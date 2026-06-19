import 'package:dio/dio.dart';
import 'api_endpoints.dart';
import '../utils/json_utils.dart';

/// Thin data layer over Dio for the Phase-1 screens.
class ApiService {
  final Dio dio;
  ApiService(this.dio);

  Future<List<Map<String, dynamic>>> list(String path,
      {Map<String, dynamic>? query}) async {
    final res = await dio.get(path, queryParameters: query);
    return asList(res.data);
  }

  Future<String> askDale(String message) async {
    final res = await dio.post(Api.daleAsk, data: {
      'message': message,
      'question': message,
      'prompt': message,
    });
    final d = res.data;
    if (d is Map) {
      if (d['reply'] != null) return d['reply'].toString();
      if (d['data'] is Map && d['data']['reply'] != null) {
        return d['data']['reply'].toString();
      }
      if (d['response'] != null) return d['response'].toString();
    }
    return d?.toString() ?? '';
  }
}
