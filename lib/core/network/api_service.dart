import 'package:dio/dio.dart';
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
}
