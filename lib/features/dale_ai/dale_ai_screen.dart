import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_service.dart';
import '../../core/network/dio_client.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/json_utils.dart';

class _Msg {
  final String text;
  final bool fromUser;
  _Msg(this.text, this.fromUser);
}

class DaleAiScreen extends StatefulWidget {
  const DaleAiScreen({super.key});
  @override
  State<DaleAiScreen> createState() => _DaleAiScreenState();
}

class _DaleAiScreenState extends State<DaleAiScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _messages = [
    _Msg("Hi, I'm Dale. Ask me about pricing, tasks, or your farm.", false),
  ];
  bool _sending = false;

  ApiService get _api => ApiService(context.read<DioClient>().dio);

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _messages.add(_Msg(text, true));
      _sending = true;
      _controller.clear();
    });
    _scrollDown();
    try {
      final reply = await _api.askDale(text);
      setState(() => _messages.add(_Msg(
          reply.isEmpty ? 'No response received.' : reply, false)));
    } catch (e) {
      setState(() => _messages.add(_Msg(friendlyError(e), false)));
    } finally {
      setState(() => _sending = false);
      _scrollDown();
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxW = Responsive.contentMaxWidth(context);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (_, i) => _Bubble(_messages[i]),
              ),
            ),
            if (_sending)
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text('Dale is thinking...',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(
                          hintText: 'Message Dale...',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FloatingActionButton(
                      onPressed: _sending ? null : _send,
                      backgroundColor: AppColors.primary,
                      elevation: 0,
                      child: const Icon(Icons.send_rounded, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final _Msg msg;
  const _Bubble(this.msg);

  @override
  Widget build(BuildContext context) {
    final fromUser = msg.fromUser;
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        decoration: BoxDecoration(
          color: fromUser ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Text(
          msg.text,
          style: TextStyle(
              color: fromUser ? Colors.white : AppColors.textDark, height: 1.35),
        ),
      ),
    );
  }
}
