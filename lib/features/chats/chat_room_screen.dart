import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/chat_api.dart';
import '../../core/network/dio_client.dart';
import '../../core/storage/token_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/json_utils.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/state_views.dart';
import 'chat_bits.dart';
import 'chat_models.dart';
import 'chat_ws.dart';

class ChatRoomScreen extends StatefulWidget {
  final int conversationId;
  final String title;
  const ChatRoomScreen({super.key, required this.conversationId, required this.title});
  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  late final ChatApi _api = ChatApi(context.read<DioClient>().dio);
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _socket = ChatSocket();

  ChatConversation? _conv;
  final List<ChatMessage> _messages = [];
  final Set<int> _seen = {};
  bool _loading = true;
  String? _error;

  ChatMessage? _replyTo;
  String? _pendingPath;
  String? _pendingName;
  bool _sending = false;

  int? get _myId => context.read<AuthProvider>().user?.id;
  String? get _myUsername => context.read<AuthProvider>().user?.username;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    _socket.dispose();
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  bool _isMine(ChatMessage m) =>
      (_myId != null && m.senderId == _myId) || (_myUsername != null && m.sender == _myUsername);

  Future<void> _boot() async {
    try {
      final c = await _api.conversation(widget.conversationId);
      _conv = ChatConversation.fromJson(c);
    } catch (_) {
      _conv = null;
    }
    await _loadMessages();
    final token = await context.read<TokenStorage>().accessToken;
    if (!mounted) return;
    _socket.connect(widget.conversationId, token);
    _socket.stream.listen(_onFrame);
  }

  Future<void> _loadMessages() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await _api.messages(widget.conversationId);
      final parsed = raw.map(ChatMessage.fromJson).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      _seen
        ..clear()
        ..addAll(parsed.map((m) => m.id));
      setState(() {
        _messages
          ..clear()
          ..addAll(parsed);
        _loading = false;
      });
      _jumpToBottom();
    } catch (e) {
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  void _onFrame(Map<String, dynamic> d) {
    if (!mounted) return;
    if (d['_presence'] is Map && _conv != null && _conv!.type == 'direct') {
      setState(() {});
      return;
    }
    if (d['id'] == null) return;
    final m = ChatMessage.fromJson(d);
    if (d['_update'] == true) {
      _patch(m);
      return;
    }
    if (_seen.contains(m.id)) return;
    _seen.add(m.id);
    setState(() => _messages.add(m));
    _jumpToBottom();
  }

  void _patch(ChatMessage m) {
    final i = _messages.indexWhere((x) => x.id == m.id);
    if (i != -1) setState(() => _messages[i] = m);
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.any, withData: false);
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    if (f.path == null) return;
    setState(() {
      _pendingPath = f.path;
      _pendingName = f.name;
    });
  }

  Future<void> _pickAudio() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.audio, withData: false);
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    if (f.path == null) return;
    setState(() {
      _pendingPath = f.path;
      _pendingName = f.name;
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty && _pendingPath == null) return;
    setState(() => _sending = true);
    try {
      final created = await _api.sendMessage(
        conversation: widget.conversationId,
        content: text.isEmpty ? null : text,
        replyTo: _replyTo?.id,
        filePath: _pendingPath,
        fileName: _pendingName,
      );
      final m = ChatMessage.fromJson(created);
      if (!_seen.contains(m.id)) {
        _seen.add(m.id);
        _messages.add(m);
      }
      _input.clear();
      setState(() {
        _replyTo = null;
        _pendingPath = null;
        _pendingName = null;
      });
      _jumpToBottom();
    } catch (e) {
      if (mounted) showToast(context, 'Failed to send', success: false);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _react(ChatMessage m, String reaction) async {
    try {
      final updated = await _api.react(m.id, reaction);
      _patch(ChatMessage.fromJson(updated));
    } catch (_) {}
  }

  void _openMsgMenu(ChatMessage m) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _menuRow(Icons.reply_rounded, 'Reply', () {
              Navigator.pop(context);
              setState(() => _replyTo = m);
            }),
            _menuRow(Icons.thumb_up_alt_rounded, 'Like', () {
              Navigator.pop(context);
              _react(m, 'like');
            }),
            _menuRow(Icons.thumb_down_alt_rounded, 'Dislike', () {
              Navigator.pop(context);
              _react(m, 'dislike');
            }),
            _menuRow(Icons.forward_rounded, 'Forward', () {
              Navigator.pop(context);
              _openForward(m);
            }),
          ],
        ),
      ),
    );
  }

  Widget _menuRow(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: AppColors.g700),
      title: Text(label, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
      onTap: onTap,
    );
  }

  Future<void> _openForward(ChatMessage m) async {
    final convs = await _api.conversations();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
        decoration: const BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Forward to…',
                  style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.inkWarm)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: convs.map((c) {
                  final cc = ChatConversation.fromJson(c);
                  return ListTile(
                    leading: const Icon(Icons.chat_bubble_rounded, color: AppColors.g600),
                    title: Text(cc.displayName),
                    onTap: () async {
                      Navigator.pop(context);
                      var content = m.content;
                      if (m.attachmentUrl != null) {
                        content = (content.isNotEmpty ? '$content\n' : '') + (absoluteUrl(m.attachmentUrl) ?? m.attachmentUrl!);
                      }
                      try {
                        await _api.sendMessage(conversation: cc.id, content: content.isEmpty ? '[forwarded]' : content);
                        if (mounted) showToast(context, 'Forwarded');
                      } catch (_) {
                        if (mounted) showToast(context, 'Could not forward', success: false);
                      }
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMembers() async {
    if (_conv == null || _conv!.type == 'direct') return;
    final members = await _api.members(widget.conversationId);
    if (!mounted) return;
    final amAdmin = _conv!.isAdmin;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        decoration: const BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Members',
                  style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.inkWarm)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: members.map((p) {
                  final username = (p['username'] ?? '').toString();
                  final role = (p['role'] ?? '').toString();
                  final online = p['online'] == true;
                  return ListTile(
                    leading: ConvAvatar(name: username, online: online, size: 38),
                    title: Text(username),
                    subtitle: Text(role == 'admin' ? 'Admin' : (online ? 'Active now' : 'Offline')),
                    trailing: (amAdmin && role != 'admin')
                        ? TextButton(
                            onPressed: () async {
                              try {
                                await _api.removeMember(widget.conversationId, p['user']);
                                if (mounted) Navigator.pop(context);
                              } catch (_) {}
                            },
                            child: const Text('Remove', style: TextStyle(color: Color(0xFFDC2626))),
                          )
                        : null,
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isGroup = _conv != null && _conv!.type != 'direct';
    String subtitle = '';
    if (_conv != null) {
      if (_conv!.type == 'direct') {
        subtitle = _conv!.otherOnline ? 'Active now' : (_conv!.otherLastSeen != null ? 'last seen ${timeAgo(_conv!.otherLastSeen)}' : 'offline');
      } else {
        subtitle = '${_conv!.type == 'channel' ? 'Channel' : 'Group'} · ${_conv!.participantCount} members';
      }
    }

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: const Color(0xFF22432C),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w700, fontSize: 17)),
            if (subtitle.isNotEmpty)
              Text(subtitle, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: Color(0xFFBBF7D0))),
          ],
        ),
        actions: [
          if (isGroup) IconButton(onPressed: _openMembers, icon: const Icon(Icons.group_rounded)),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _body()),
          if (_replyTo != null) _replyBar(),
          if (_pendingPath != null) _attachmentBar(),
          _composer(),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const LoadingView();
    if (_error != null) return ErrorView(message: _error!, onRetry: _loadMessages);
    if (_messages.isEmpty) {
      return const EmptyView(text: 'No messages yet. Say hello!', icon: Icons.waving_hand_rounded);
    }
    final widgets = <Widget>[];
    DateTime? lastDay;
    for (final m in _messages) {
      final day = DateTime(m.createdAt.year, m.createdAt.month, m.createdAt.day);
      if (lastDay == null || day != lastDay) {
        widgets.add(_dayDivider(dayLabel(m.createdAt)));
        lastDay = day;
      }
      widgets.add(_bubble(m));
    }
    return RefreshIndicator(
      onRefresh: _loadMessages,
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        children: widgets,
      ),
    );
  }

  Widget _dayDivider(String label) => Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999), border: Border.all(color: AppColors.line)),
          child: Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppColors.slate500, fontWeight: FontWeight.w600)),
        ),
      );

  Widget _bubble(ChatMessage m) {
    final mine = _isMine(m);
    final showName = !mine && _conv != null && _conv!.type != 'direct';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _openMsgMenu(m),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(11, 7, 11, 5),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.74),
          decoration: BoxDecoration(
            gradient: mine ? AppColors.emeraldGrad : null,
            color: mine ? null : const Color(0xFFE3F3E6),
            border: mine ? null : Border.all(color: const Color(0xFFC7E7CF)),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(mine ? 16 : 4),
              bottomRight: Radius.circular(mine ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showName)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(m.senderName,
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.g700)),
                ),
              if (m.replyPreview != null) _replyQuote(m.replyPreview!, mine),
              if (m.content.isNotEmpty)
                Text(m.content, style: TextStyle(fontSize: 14, height: 1.35, color: mine ? Colors.white : AppColors.inkWarm)),
              if (m.messageType == 'audio' && m.attachmentUrl != null)
                AudioAttachment(url: m.attachmentUrl!, mine: mine)
              else
                attachmentWidget(m),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (m.like > 0) _pill('👍 ${m.like}', mine),
                  if (m.dislike > 0) _pill('👎 ${m.dislike}', mine),
                  Text(clock(m.createdAt),
                      style: TextStyle(fontSize: 10, color: mine ? Colors.white.withValues(alpha: 0.85) : AppColors.slate500)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(String t, bool mine) => Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: mine ? Colors.white.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(t, style: TextStyle(fontSize: 10, color: mine ? Colors.white : AppColors.slate600)),
      );

  Widget _replyQuote(ReplyPreview r, bool mine) => Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: mine ? Colors.white.withValues(alpha: 0.18) : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border(left: BorderSide(color: mine ? const Color(0xFFBBF7D0) : AppColors.green, width: 3)),
        ),
        child: Text('${r.senderName}: ${r.snippet}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: mine ? Colors.white : AppColors.slate600)),
      );

  Widget _replyBar() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        color: const Color(0xFFEEF7F0),
        child: Row(
          children: [
            const Icon(Icons.reply_rounded, color: AppColors.g700, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Replying to ${_replyTo!.senderName}: ${_replyTo!.content.isEmpty ? '[${_replyTo!.messageType}]' : _replyTo!.content}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: AppColors.slate600)),
            ),
            IconButton(onPressed: () => setState(() => _replyTo = null), icon: const Icon(Icons.close, size: 18)),
          ],
        ),
      );

  Widget _attachmentBar() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        color: const Color(0xFFFBF7EE),
        child: Row(
          children: [
            const Icon(Icons.attach_file_rounded, color: AppColors.g700, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_pendingName ?? 'Attachment',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: AppColors.slate600)),
            ),
            IconButton(
                onPressed: () => setState(() {
                      _pendingPath = null;
                      _pendingName = null;
                    }),
                icon: const Icon(Icons.close, size: 18)),
          ],
        ),
      );

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _circleBtn(Icons.attach_file_rounded, _pickFile),
            _circleBtn(Icons.mic_rounded, _pickAudio),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 6),
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Type your message…',
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.cream,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                  ),
                ),
              ),
            ),
            GestureDetector(
              onTap: _sending ? null : _send,
              child: Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(gradient: AppColors.emeraldGrad, shape: BoxShape.circle),
                child: _sending
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                    : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.cream,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.line),
          ),
          child: Icon(icon, size: 20, color: AppColors.g700),
        ),
      );
}
