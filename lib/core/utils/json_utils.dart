import '../config/app_config.dart';

/// Tolerant list parser: handles a raw JSON list OR a DRF paginated
/// {"results": [...]} envelope.
List<Map<String, dynamic>> asList(dynamic data) {
  if (data is List) {
    return data.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }
  if (data is Map && data['results'] is List) {
    return (data['results'] as List)
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }
  return <Map<String, dynamic>>[];
}

String? pickString(Map j, List<String> keys) {
  for (final k in keys) {
    final v = j[k];
    if (v is String && v.trim().isNotEmpty) return v;
    if (v is num) return v.toString();
  }
  return null;
}

num? pickNum(Map j, List<String> keys) {
  for (final k in keys) {
    final v = j[k];
    if (v is num) return v;
    if (v is String) {
      final n = num.tryParse(v);
      if (n != null) return n;
    }
  }
  return null;
}

String? absoluteUrl(String? u) {
  if (u == null || u.isEmpty) return null;
  if (u.startsWith('http')) return u;
  if (u.startsWith('/')) return AppConfig.baseUrl + u;
  return u;
}

String friendlyError(Object? e) {
  final s = e?.toString() ?? '';
  if (s.contains('SocketException') ||
      s.contains('connectionError') ||
      s.contains('Connection refused') ||
      s.contains('Failed host lookup')) {
    return 'Can\'t reach the server.\nMake sure the backend is running and the API URL is correct for this device.';
  }
  if (s.contains('401')) return 'Your session expired. Please log in again.';
  if (s.contains('timeout')) return 'The server took too long to respond.';
  return 'Could not load data. Pull down to retry.';
}
