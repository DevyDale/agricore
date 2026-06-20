import 'package:dio/dio.dart';
import '../../core/network/api_endpoints.dart';
import 'dale_models.dart';

/// Talks to the Dale AI endpoint, sending the rich context the backend
/// understands (page, language, currency, recent history) and parsing the
/// `{reply, action}` response.
class DaleService {
  final Dio dio;
  DaleService(this.dio);

  Future<DaleReply> ask({
    required String prompt,
    String? page,
    String? language,
    String? currency,
    List<Map<String, String>> history = const [],
  }) async {
    final context = <String, dynamic>{};
    if (page != null && page.isNotEmpty) context['page'] = page;
    if (language != null && language.isNotEmpty) context['language'] = language;
    if (currency != null && currency.isNotEmpty) context['currency'] = currency;

    final res = await dio.post(Api.daleAsk, data: {
      'prompt': prompt,
      if (context.isNotEmpty) 'context': context,
      if (history.isNotEmpty) 'history': history,
    });

    final d = res.data;
    String reply = '';
    DaleAction? action;
    if (d is Map) {
      reply = (d['reply'] ??
              d['response'] ??
              (d['data'] is Map ? d['data']['reply'] : null) ??
              '')
          .toString();
      action = DaleAction.fromJson(d['action']);
    } else {
      reply = d?.toString() ?? '';
    }
    return DaleReply(reply, action);
  }
}
