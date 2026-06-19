class ReplyPreview {
  final String senderName;
  final String snippet;
  const ReplyPreview(this.senderName, this.snippet);
  static ReplyPreview? from(dynamic j) {
    if (j is Map) {
      return ReplyPreview((j['sender_name'] ?? '').toString(), (j['snippet'] ?? '').toString());
    }
    return null;
  }
}

class ChatMessage {
  final int id;
  final String content;
  final int? senderId;
  final String? sender; // username
  final String senderName;
  final String messageType; // text | image | video | audio | file
  final String? attachmentUrl;
  final DateTime createdAt;
  final ReplyPreview? replyPreview;
  final int like;
  final int dislike;
  final String? myReaction; // 'like' | 'dislike' | null

  ChatMessage({
    required this.id,
    required this.content,
    required this.senderId,
    required this.sender,
    required this.senderName,
    required this.messageType,
    required this.attachmentUrl,
    required this.createdAt,
    required this.replyPreview,
    required this.like,
    required this.dislike,
    required this.myReaction,
  });

  factory ChatMessage.fromJson(Map j) {
    final rx = (j['reactions'] is Map) ? j['reactions'] as Map : const {};
    DateTime created;
    try {
      created = DateTime.parse((j['created_at'] ?? j['created'] ?? '').toString()).toLocal();
    } catch (_) {
      created = DateTime.now();
    }
    int? sid;
    final rawSid = j['sender_id'];
    if (rawSid != null) sid = (rawSid is int) ? rawSid : int.tryParse('$rawSid');
    return ChatMessage(
      id: (j['id'] is int) ? j['id'] : int.tryParse('${j['id']}') ?? 0,
      content: (j['content'] ?? '').toString(),
      senderId: sid,
      sender: j['sender']?.toString(),
      senderName: (j['sender_name'] ?? j['sender'] ?? 'Member').toString(),
      messageType: (j['message_type'] ?? 'text').toString(),
      attachmentUrl: j['attachment_url']?.toString(),
      createdAt: created,
      replyPreview: ReplyPreview.from(j['reply_preview']),
      like: (rx['like'] is int) ? rx['like'] : int.tryParse('${rx['like']}') ?? 0,
      dislike: (rx['dislike'] is int) ? rx['dislike'] : int.tryParse('${rx['dislike']}') ?? 0,
      myReaction: rx['mine']?.toString(),
    );
  }
}

class ChatConversation {
  final int id;
  final String type; // direct | group | channel
  final String displayName;
  final bool otherOnline;
  final DateTime? otherLastSeen;
  final int participantCount;
  final String? myRole;
  final String? description;
  final DateTime? updatedAt;

  ChatConversation({
    required this.id,
    required this.type,
    required this.displayName,
    required this.otherOnline,
    required this.otherLastSeen,
    required this.participantCount,
    required this.myRole,
    required this.description,
    required this.updatedAt,
  });

  bool get isAdmin => myRole == 'admin';

  factory ChatConversation.fromJson(Map j) {
    DateTime? parse(dynamic v) {
      if (v == null) return null;
      try {
        return DateTime.parse(v.toString()).toLocal();
      } catch (_) {
        return null;
      }
    }

    return ChatConversation(
      id: (j['id'] is int) ? j['id'] : int.tryParse('${j['id']}') ?? 0,
      type: (j['type'] ?? 'direct').toString(),
      displayName: (j['display_name'] ?? j['title'] ?? 'Conversation').toString(),
      otherOnline: j['other_online'] == true,
      otherLastSeen: parse(j['other_last_seen']),
      participantCount: (j['participant_count'] is int) ? j['participant_count'] : int.tryParse('${j['participant_count']}') ?? 0,
      myRole: j['my_role']?.toString(),
      description: j['description']?.toString(),
      updatedAt: parse(j['updated_at']),
    );
  }
}
