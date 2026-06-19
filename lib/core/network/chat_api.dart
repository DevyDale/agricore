import 'package:dio/dio.dart';
import '../utils/json_utils.dart';

/// Thin data layer over Dio for the chat feature. Paths are inlined here so the
/// shared Api endpoint table stays untouched.
class ChatApi {
  final Dio dio;
  ChatApi(this.dio);

  List<Map<String, dynamic>> _list(dynamic d) => asList(d);

  Future<List<Map<String, dynamic>>> conversations({String? search}) async {
    final res = await dio.get('/conversations/', queryParameters: search != null && search.isNotEmpty ? {'search': search} : null);
    return _list(res.data);
  }

  Future<List<Map<String, dynamic>>> publicChannels({String? search}) async {
    final res = await dio.get('/conversations/public/', queryParameters: search != null && search.isNotEmpty ? {'search': search} : null);
    return _list(res.data);
  }

  Future<Map<String, dynamic>> conversation(int id) async {
    final res = await dio.get('/conversations/$id/');
    return (res.data as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> createConversation(String title, String type) async {
    final res = await dio.post('/conversations/', data: {'title': title, 'type': type, 'is_public': type == 'channel'});
    return (res.data as Map).cast<String, dynamic>();
  }

  Future<void> deleteConversation(int id) => dio.delete('/conversations/$id/');

  Future<Map<String, dynamic>> joinChannel(int id) async {
    final res = await dio.post('/conversations/$id/join/');
    return (res.data is Map) ? (res.data as Map).cast<String, dynamic>() : {'id': id};
  }

  Future<Map<String, dynamic>> startDirect(dynamic userId) async {
    final res = await dio.post('/conversations/start-direct-chat/', data: {'user': userId});
    return (res.data as Map).cast<String, dynamic>();
  }

  Future<List<Map<String, dynamic>>> members(int id) async {
    final res = await dio.get('/conversations/$id/members/');
    return _list(res.data);
  }

  Future<void> addMember(int id, dynamic userId) => dio.post('/conversations/$id/add-member/', data: {'user': userId});
  Future<void> removeMember(int id, dynamic userId) => dio.post('/conversations/$id/remove-member/', data: {'user': userId});

  Future<List<Map<String, dynamic>>> messages(int conversationId) async {
    final res = await dio.get('/messages/', queryParameters: {'conversation': conversationId});
    return _list(res.data);
  }

  Future<Map<String, dynamic>> sendMessage({
    required int conversation,
    String? content,
    int? replyTo,
    String? filePath,
    String? fileName,
  }) async {
    final map = <String, dynamic>{'conversation': conversation};
    if (content != null && content.isNotEmpty) map['content'] = content;
    if (replyTo != null) map['reply_to'] = replyTo;
    if (filePath != null) {
      map['attachment'] = await MultipartFile.fromFile(filePath, filename: fileName);
    }
    final res = await dio.post('/messages/', data: FormData.fromMap(map));
    return (res.data as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> react(int messageId, String reaction) async {
    final res = await dio.post('/messages/$messageId/react/', data: {'reaction': reaction});
    return (res.data as Map).cast<String, dynamic>();
  }

  Future<List<Map<String, dynamic>>> searchUsers(String q) async {
    final res = await dio.get('/users/search/', queryParameters: {'q': q});
    return _list(res.data);
  }
}
